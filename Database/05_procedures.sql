SET DEFINE OFF
SET SERVEROUTPUT ON

-- ---------------------------------------------------------------------
-- FUNCTIONS
-- ---------------------------------------------------------------------

-- Start / end of a slot as a DATE (NULL if the slot does not exist)
CREATE OR REPLACE FUNCTION fn_slot_start (p_slot_id IN NUMBER) RETURN DATE IS
  v_start DATE;
BEGIN
  SELECT TO_DATE(TO_CHAR(slot_date, 'YYYY-MM-DD') || ' ' || start_time, 'YYYY-MM-DD HH24:MI')
  INTO   v_start
  FROM   time_slot
  WHERE  slot_id = p_slot_id;
  RETURN v_start;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RETURN NULL;
END fn_slot_start;
/

CREATE OR REPLACE FUNCTION fn_slot_end (p_slot_id IN NUMBER) RETURN DATE IS
  v_end DATE;
BEGIN
  SELECT TO_DATE(TO_CHAR(slot_date, 'YYYY-MM-DD') || ' ' || end_time, 'YYYY-MM-DD HH24:MI')
  INTO   v_end
  FROM   time_slot
  WHERE  slot_id = p_slot_id;
  RETURN v_end;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RETURN NULL;
END fn_slot_end;
/

-- Number of ACTIVE penalties a member currently has
CREATE OR REPLACE FUNCTION fn_active_penalties (p_member_id IN NUMBER) RETURN NUMBER IS
  v_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_cnt
  FROM   penalty
  WHERE  member_id = p_member_id AND status = 'Active';
  RETURN v_cnt;
END fn_active_penalties;
/

-- 1 if the space is open and has no active booking in that slot, else 0
CREATE OR REPLACE FUNCTION fn_is_available (p_space_id IN NUMBER, p_slot_id IN NUMBER) RETURN NUMBER IS
  v_status study_space.status%TYPE;
  v_cnt    NUMBER;
BEGIN
  BEGIN
    SELECT status INTO v_status FROM study_space WHERE space_id = p_space_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RETURN 0;
  END;
  IF v_status <> 'Available' THEN
    RETURN 0;
  END IF;
  SELECT COUNT(*) INTO v_cnt
  FROM   booking
  WHERE  space_id = p_space_id AND slot_id = p_slot_id AND booking_status <> 'Cancelled';
  IF v_cnt > 0 THEN
    RETURN 0;
  END IF;
  RETURN 1;
END fn_is_available;
/

-- Member attendance rate in %: completed / (completed + no-show). NULL if no history yet.
CREATE OR REPLACE FUNCTION fn_attendance_rate (p_member_id IN NUMBER) RETURN NUMBER IS
  v_att NUMBER;
  v_ns  NUMBER;
BEGIN
  SELECT NVL(SUM(CASE WHEN booking_status = 'Completed' THEN 1 ELSE 0 END), 0),
         NVL(SUM(CASE WHEN booking_status = 'No-Show'   THEN 1 ELSE 0 END), 0)
  INTO   v_att, v_ns
  FROM   booking
  WHERE  member_id = p_member_id;
  IF v_att + v_ns = 0 THEN
    RETURN NULL;
  END IF;
  RETURN ROUND(100 * v_att / (v_att + v_ns), 1);
END fn_attendance_rate;
/

-- How many days an Active penalty lasts. The one place this number lives.
CREATE OR REPLACE FUNCTION fn_penalty_expiry_days RETURN NUMBER IS
BEGIN
  RETURN 14;
END fn_penalty_expiry_days;
/

-- Whole days left before an Active penalty expires (NULL if it is not Active or does not exist)
CREATE OR REPLACE FUNCTION fn_penalty_days_left (p_penalty_id IN NUMBER) RETURN NUMBER IS
  v_date   penalty.penalty_date%TYPE;
  v_status penalty.status%TYPE;
  v_left   NUMBER;
BEGIN
  SELECT penalty_date, status INTO v_date, v_status
  FROM   penalty WHERE penalty_id = p_penalty_id;
  IF v_status <> 'Active' THEN
    RETURN NULL;
  END IF;
  v_left := CEIL(v_date + fn_penalty_expiry_days - SYSDATE);
  IF v_left < 0 THEN
    v_left := 0;
  END IF;
  RETURN v_left;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RETURN NULL;
END fn_penalty_days_left;
/

-- Average rating of a space (NULL if no feedback yet)
CREATE OR REPLACE FUNCTION fn_avg_rating (p_space_id IN NUMBER) RETURN NUMBER IS
  v_avg NUMBER;
BEGIN
  SELECT ROUND(AVG(rating), 2) INTO v_avg FROM feedback WHERE space_id = p_space_id;
  RETURN v_avg;
END fn_avg_rating;
/

-- ---------------------------------------------------------------------
-- PROCEDURES
-- ---------------------------------------------------------------------

-- EXPIRE OLD PENALTIES
-- An Active penalty older than 14 days becomes Cleared, so a blocked member is never locked out for good.
-- Cursor: parameterized, FOR UPDATE, UPDATE ... WHERE CURRENT OF.
-- p_as_of = the moment to judge age by; NULL means now (a test can pass a later date).
CREATE OR REPLACE PROCEDURE sp_expire_penalties (
  p_as_of   IN  DATE,
  o_expired OUT NUMBER
) IS
  c_expiry_days CONSTANT NUMBER := fn_penalty_expiry_days;
  CURSOR c_old (p_cutoff DATE) IS
    SELECT penalty_id
    FROM   penalty
    WHERE  status = 'Active' AND penalty_date <= p_cutoff
    FOR UPDATE OF status;
  v_row c_old%ROWTYPE;
BEGIN
  o_expired := 0;
  OPEN c_old(NVL(p_as_of, SYSDATE) - c_expiry_days);
  LOOP
    FETCH c_old INTO v_row;
    EXIT WHEN c_old%NOTFOUND;
    UPDATE penalty SET status = 'Cleared' WHERE CURRENT OF c_old;
    o_expired := o_expired + 1;
  END LOOP;
  CLOSE c_old;
  COMMIT;
END sp_expire_penalties;
/

-- BOOK A SPACE
-- Rules: member and space exist, space is Available, slot exists and has not started,
-- member has fewer than 2 active penalties (penalties older than 14 days expire first), member has no other booking in that slot,
-- and the space is free (the unique index is the final guard against double booking).
CREATE OR REPLACE PROCEDURE sp_book_space (
  p_member_id  IN  NUMBER,
  p_space_id   IN  NUMBER,
  p_slot_id    IN  NUMBER,
  o_booking_id OUT NUMBER
) IS
  c_max_active_penalties CONSTANT NUMBER := 2;
  v_dummy  NUMBER;
  v_status study_space.status%TYPE;
  v_start  DATE;
  v_expired NUMBER;
BEGIN
  BEGIN
    SELECT member_id INTO v_dummy FROM campus_member WHERE member_id = p_member_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20001, 'Member not found');
  END;
  BEGIN
    SELECT status INTO v_status FROM study_space WHERE space_id = p_space_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20002, 'Study space not found');
  END;
  IF v_status <> 'Available' THEN
    RAISE_APPLICATION_ERROR(-20003, 'This space is not open for booking (status: ' || v_status || ')');
  END IF;
  v_start := fn_slot_start(p_slot_id);
  IF v_start IS NULL THEN
    RAISE_APPLICATION_ERROR(-20004, 'Time slot not found');
  END IF;
  IF v_start <= SYSDATE THEN
    RAISE_APPLICATION_ERROR(-20005, 'This time slot has already started or passed');
  END IF;
  sp_expire_penalties(NULL, v_expired);
  IF fn_active_penalties(p_member_id) >= c_max_active_penalties THEN
    RAISE_APPLICATION_ERROR(-20006, 'Booking blocked: member has ' || fn_active_penalties(p_member_id) || ' active penalties');
  END IF;
  SELECT COUNT(*) INTO v_dummy
  FROM   booking
  WHERE  member_id = p_member_id AND slot_id = p_slot_id AND booking_status <> 'Cancelled';
  IF v_dummy > 0 THEN
    RAISE_APPLICATION_ERROR(-20007, 'You already have a booking in this time slot');
  END IF;
  BEGIN
    INSERT INTO booking (member_id, space_id, slot_id)
    VALUES (p_member_id, p_space_id, p_slot_id)
    RETURNING booking_id INTO o_booking_id;
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      RAISE_APPLICATION_ERROR(-20008, 'This space is already booked for the selected time slot');
  END;
  COMMIT;
END sp_book_space;
/

-- CANCEL A BOOKING
-- Rules: booking exists, belongs to the member, is Confirmed, and its slot has not started.
CREATE OR REPLACE PROCEDURE sp_cancel_booking (
  p_booking_id IN NUMBER,
  p_member_id  IN NUMBER
) IS
  v_member booking.member_id%TYPE;
  v_status booking.booking_status%TYPE;
  v_slot   booking.slot_id%TYPE;
BEGIN
  BEGIN
    SELECT member_id, booking_status, slot_id INTO v_member, v_status, v_slot
    FROM   booking WHERE booking_id = p_booking_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20010, 'Booking not found');
  END;
  IF v_member <> p_member_id THEN
    RAISE_APPLICATION_ERROR(-20011, 'You can only cancel your own bookings');
  END IF;
  IF v_status <> 'Confirmed' THEN
    RAISE_APPLICATION_ERROR(-20012, 'Only Confirmed bookings can be cancelled (current status: ' || v_status || ')');
  END IF;
  IF fn_slot_start(v_slot) <= SYSDATE THEN
    RAISE_APPLICATION_ERROR(-20013, 'This slot has already started and can no longer be cancelled');
  END IF;
  UPDATE booking SET booking_status = 'Cancelled' WHERE booking_id = p_booking_id;
  COMMIT;
END sp_cancel_booking;
/

-- CHECK IN
-- Rules: booking is Confirmed, not already checked in, and the time is inside the window
-- (15 minutes before the slot starts until the slot ends).
-- p_at is optional: leave it out for "now"; pass a time to simulate (handy for demos).
CREATE OR REPLACE PROCEDURE sp_check_in (
  p_booking_id IN NUMBER,
  p_at         IN TIMESTAMP DEFAULT NULL
) IS
  v_at     TIMESTAMP := NVL(p_at, SYSTIMESTAMP);
  v_status booking.booking_status%TYPE;
  v_slot   booking.slot_id%TYPE;
  v_cnt    NUMBER;
BEGIN
  BEGIN
    SELECT booking_status, slot_id INTO v_status, v_slot
    FROM   booking WHERE booking_id = p_booking_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20020, 'Booking not found');
  END;
  IF v_status <> 'Confirmed' THEN
    RAISE_APPLICATION_ERROR(-20021, 'Only Confirmed bookings can be checked in (current status: ' || v_status || ')');
  END IF;
  SELECT COUNT(*) INTO v_cnt FROM check_in WHERE booking_id = p_booking_id;
  IF v_cnt > 0 THEN
    RAISE_APPLICATION_ERROR(-20022, 'This booking is already checked in');
  END IF;
  IF CAST(v_at AS DATE) < fn_slot_start(v_slot) - 15 / 1440 THEN
    RAISE_APPLICATION_ERROR(-20023, 'Check-in opens 15 minutes before the slot starts');
  END IF;
  IF CAST(v_at AS DATE) > fn_slot_end(v_slot) THEN
    RAISE_APPLICATION_ERROR(-20024, 'This slot has already ended');
  END IF;
  INSERT INTO check_in (booking_id, checkin_time, checkin_status)
  VALUES (p_booking_id, v_at, 'Checked In');
  COMMIT;
END sp_check_in;
/

-- CHECK OUT: closes the check-in and marks the booking Completed.
CREATE OR REPLACE PROCEDURE sp_check_out (
  p_booking_id IN NUMBER,
  p_at         IN TIMESTAMP DEFAULT NULL
) IS
  v_at  TIMESTAMP := NVL(p_at, SYSTIMESTAMP);
  v_in  check_in.checkin_time%TYPE;
  v_out check_in.checkout_time%TYPE;
BEGIN
  BEGIN
    SELECT checkin_time, checkout_time INTO v_in, v_out
    FROM   check_in WHERE booking_id = p_booking_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20030, 'No check-in found for this booking');
  END;
  IF v_out IS NOT NULL THEN
    RAISE_APPLICATION_ERROR(-20031, 'This booking is already checked out');
  END IF;
  IF v_at < v_in THEN
    RAISE_APPLICATION_ERROR(-20032, 'Check-out time cannot be before check-in time');
  END IF;
  UPDATE check_in
  SET    checkout_time = v_at, checkin_status = 'Checked Out'
  WHERE  booking_id = p_booking_id;
  UPDATE booking SET booking_status = 'Completed' WHERE booking_id = p_booking_id;
  COMMIT;
END sp_check_out;
/

-- SUBMIT FEEDBACK
-- Rules: booking exists, belongs to the member, is Completed, rating 1-5, one feedback per booking.
CREATE OR REPLACE PROCEDURE sp_submit_feedback (
  p_member_id  IN NUMBER,
  p_booking_id IN NUMBER,
  p_rating     IN NUMBER,
  p_comments   IN VARCHAR2 DEFAULT NULL
) IS
  v_member booking.member_id%TYPE;
  v_space  booking.space_id%TYPE;
  v_status booking.booking_status%TYPE;
  v_cnt    NUMBER;
BEGIN
  BEGIN
    SELECT member_id, space_id, booking_status INTO v_member, v_space, v_status
    FROM   booking WHERE booking_id = p_booking_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20040, 'Booking not found');
  END;
  IF v_member <> p_member_id THEN
    RAISE_APPLICATION_ERROR(-20041, 'You can only review your own bookings');
  END IF;
  IF v_status <> 'Completed' THEN
    RAISE_APPLICATION_ERROR(-20042, 'Feedback is only allowed after the booking is completed');
  END IF;
  IF p_rating IS NULL OR p_rating NOT BETWEEN 1 AND 5 THEN
    RAISE_APPLICATION_ERROR(-20043, 'Rating must be between 1 and 5');
  END IF;
  SELECT COUNT(*) INTO v_cnt FROM feedback WHERE booking_id = p_booking_id;
  IF v_cnt > 0 THEN
    RAISE_APPLICATION_ERROR(-20044, 'Feedback has already been given for this booking');
  END IF;
  INSERT INTO feedback (member_id, space_id, booking_id, rating, comments)
  VALUES (p_member_id, v_space, p_booking_id, p_rating, p_comments);
  COMMIT;
END sp_submit_feedback;
/

-- ---------------------------------------------------------------------
-- COMPILE CHECK: expect "no rows selected"
-- ---------------------------------------------------------------------
SELECT name, type, line, text FROM user_errors ORDER BY name, type, sequence;
