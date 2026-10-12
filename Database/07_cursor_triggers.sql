SET DEFINE OFF
SET SERVEROUTPUT ON

-- ---------------------------------------------------------------------
-- 0. Audit table for booking status changes (re-created on every run)
-- ---------------------------------------------------------------------
BEGIN
  FOR t IN (SELECT table_name FROM user_tables WHERE table_name = 'BOOKING_AUDIT') LOOP
    EXECUTE IMMEDIATE 'DROP TABLE booking_audit PURGE';
  END LOOP;
  FOR q IN (SELECT sequence_name FROM user_sequences WHERE sequence_name = 'SEQ_AUDIT') LOOP
    EXECUTE IMMEDIATE 'DROP SEQUENCE seq_audit';
  END LOOP;
END;
/

-- No foreign key on purpose: an audit log must survive even if a booking row is deleted.
CREATE TABLE booking_audit (
  audit_id    NUMBER       NOT NULL,
  booking_id  NUMBER       NOT NULL,
  old_status  VARCHAR2(15),
  new_status  VARCHAR2(15) NOT NULL,
  changed_at  TIMESTAMP    DEFAULT SYSTIMESTAMP NOT NULL,
  changed_by  VARCHAR2(30) DEFAULT USER NOT NULL,
  CONSTRAINT pk_audit PRIMARY KEY (audit_id)
);

CREATE SEQUENCE seq_audit START WITH 1 INCREMENT BY 1 NOCACHE;

CREATE OR REPLACE TRIGGER trg_audit_id
BEFORE INSERT ON booking_audit
FOR EACH ROW
BEGIN
  IF :NEW.audit_id IS NULL THEN
    SELECT seq_audit.NEXTVAL INTO :NEW.audit_id FROM dual;
  END IF;
END;
/

-- ---------------------------------------------------------------------
-- 1. Helper procedure: issue a penalty for a no-show booking
--    (no COMMIT here: it is also called from a trigger)
--    First penalty of a member = 'No-show for booking', later ones = 'Repeat no-show'.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_issue_penalty (
  p_booking_id IN NUMBER,
  p_member_id  IN NUMBER
) IS
  v_prior  NUMBER;
  v_reason penalty.reason%TYPE;
BEGIN
  SELECT COUNT(*) INTO v_prior FROM penalty WHERE member_id = p_member_id;
  IF v_prior = 0 THEN
    v_reason := 'No-show for booking';
  ELSE
    v_reason := 'Repeat no-show';
  END IF;
  INSERT INTO penalty (member_id, booking_id, reason)
  VALUES (p_member_id, p_booking_id, v_reason);
EXCEPTION
  WHEN DUP_VAL_ON_INDEX THEN
    NULL;
END sp_issue_penalty;
/

-- ---------------------------------------------------------------------
-- 2. TRIGGERS
-- ---------------------------------------------------------------------

-- T1: a finished booking can no longer change status.
--     Only a Confirmed booking may become Cancelled, Completed or No-Show.
CREATE OR REPLACE TRIGGER trg_booking_status_check
BEFORE UPDATE OF booking_status ON booking
FOR EACH ROW
WHEN (OLD.booking_status <> NEW.booking_status)
BEGIN
  IF :OLD.booking_status <> 'Confirmed' THEN
    RAISE_APPLICATION_ERROR(-20050, 'A ' || :OLD.booking_status ||
      ' booking can no longer change status (tried to set ' || :NEW.booking_status || ')');
  END IF;
END;
/

-- T2: audit log of every booking status change.
CREATE OR REPLACE TRIGGER trg_booking_audit
AFTER UPDATE OF booking_status ON booking
FOR EACH ROW
WHEN (OLD.booking_status <> NEW.booking_status)
BEGIN
  INSERT INTO booking_audit (booking_id, old_status, new_status)
  VALUES (:NEW.booking_id, :OLD.booking_status, :NEW.booking_status);
END;
/

-- T3: becoming a no-show automatically creates the penalty.
CREATE OR REPLACE TRIGGER trg_booking_noshow_penalty
AFTER UPDATE OF booking_status ON booking
FOR EACH ROW
WHEN (NEW.booking_status = 'No-Show' AND OLD.booking_status <> 'No-Show')
BEGIN
  sp_issue_penalty(:NEW.booking_id, :NEW.member_id);
END;
/

-- T4: closing a space for maintenance cancels its future bookings that have not been used.
CREATE OR REPLACE TRIGGER trg_space_closed_cancels
AFTER UPDATE OF status ON study_space
FOR EACH ROW
WHEN (NEW.status IN ('Maintenance', 'Closed') AND OLD.status <> NEW.status)
BEGIN
  UPDATE booking
  SET    booking_status = 'Cancelled'
  WHERE  space_id = :NEW.space_id
  AND    booking_status = 'Confirmed'
  AND    NOT EXISTS (SELECT 1 FROM check_in c WHERE c.booking_id = booking.booking_id)
  AND    fn_slot_start(slot_id) > SYSDATE;
END;
/

-- T5: feedback integrity - same member, same space, and a Completed booking.
CREATE OR REPLACE TRIGGER trg_feedback_rules
BEFORE INSERT ON feedback
FOR EACH ROW
DECLARE
  v_member booking.member_id%TYPE;
  v_space  booking.space_id%TYPE;
  v_status booking.booking_status%TYPE;
BEGIN
  BEGIN
    SELECT member_id, space_id, booking_status INTO v_member, v_space, v_status
    FROM   booking WHERE booking_id = :NEW.booking_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20053, 'Feedback refers to a booking that does not exist');
  END;
  IF v_member <> :NEW.member_id THEN
    RAISE_APPLICATION_ERROR(-20051, 'Feedback must come from the member who made the booking');
  END IF;
  IF v_space <> :NEW.space_id THEN
    RAISE_APPLICATION_ERROR(-20052, 'Feedback must be about the space that was booked');
  END IF;
  IF v_status <> 'Completed' THEN
    RAISE_APPLICATION_ERROR(-20054, 'Feedback is only allowed for Completed bookings');
  END IF;
END;
/

-- ---------------------------------------------------------------------
-- 3. CURSORS
-- ---------------------------------------------------------------------

-- No-show sweep.
--  Cursor 1 (parameterized, FOR UPDATE): locks each Confirmed booking whose slot has ended
--           with no check-in and marks it No-Show (trigger T3 then issues the penalty).
--  Cursor 2 (cursor FOR loop): finds No-Show bookings that still have no penalty
--           (for example older data) and issues one.
--  p_as_of = the moment to judge "slot ended" by; NULL means now. Handy for demos.
CREATE OR REPLACE PROCEDURE sp_mark_no_shows (
  p_as_of     IN  DATE,
  o_marked    OUT NUMBER,
  o_penalized OUT NUMBER
) IS
  CURSOR c_missed (p_now DATE) IS
    SELECT b.booking_id, b.member_id
    FROM   booking b
    WHERE  b.booking_status = 'Confirmed'
    AND    fn_slot_end(b.slot_id) < p_now
    AND    NOT EXISTS (SELECT 1 FROM check_in c WHERE c.booking_id = b.booking_id)
    FOR UPDATE OF b.booking_status;
  CURSOR c_unpenalized IS
    SELECT b.booking_id, b.member_id
    FROM   booking b
    WHERE  b.booking_status = 'No-Show'
    AND    NOT EXISTS (SELECT 1 FROM penalty p WHERE p.booking_id = b.booking_id);
  v_now        DATE := NVL(p_as_of, SYSDATE);
  v_missed     c_missed%ROWTYPE;
  v_pen_before NUMBER;
  v_pen_after  NUMBER;
BEGIN
  o_marked := 0;
  SELECT COUNT(*) INTO v_pen_before FROM penalty;
  OPEN c_missed(v_now);
  LOOP
    FETCH c_missed INTO v_missed;
    EXIT WHEN c_missed%NOTFOUND;
    UPDATE booking SET booking_status = 'No-Show' WHERE CURRENT OF c_missed;
    o_marked := o_marked + 1;
  END LOOP;
  CLOSE c_missed;
  FOR r IN c_unpenalized LOOP
    sp_issue_penalty(r.booking_id, r.member_id);
  END LOOP;
  SELECT COUNT(*) INTO v_pen_after FROM penalty;
  o_penalized := v_pen_after - v_pen_before;
  COMMIT;
END sp_mark_no_shows;
/

-- Printed report of members with active penalties (cursor FOR loop + DBMS_OUTPUT).
CREATE OR REPLACE PROCEDURE sp_penalty_report IS
  CURSOR c_rep IS
    SELECT m.name, m.member_type, COUNT(*) AS active_cnt
    FROM   campus_member m
    JOIN   penalty p ON p.member_id = m.member_id
    WHERE  p.status = 'Active'
    GROUP  BY m.member_id, m.name, m.member_type
    ORDER  BY active_cnt DESC, m.name;
BEGIN
  DBMS_OUTPUT.PUT_LINE('Members with active penalties');
  DBMS_OUTPUT.PUT_LINE('-------------------------------------------------------------');
  FOR r IN c_rep LOOP
    DBMS_OUTPUT.PUT_LINE(RPAD(r.name, 18) || RPAD(r.member_type, 20) || r.active_cnt ||
                         CASE WHEN r.active_cnt >= 2 THEN '   (blocked from booking)' END);
  END LOOP;
END sp_penalty_report;
/

-- ---------------------------------------------------------------------
-- COMPILE CHECK: expect "no rows selected"
-- ---------------------------------------------------------------------
SELECT name, type, line, text FROM user_errors ORDER BY name, type, sequence;
