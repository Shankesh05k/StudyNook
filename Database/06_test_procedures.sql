SET DEFINE OFF
SET SERVEROUTPUT ON
SET LINESIZE 150

PROMPT
PROMPT === T1: functions. Expect 2 | 100 | 4.67 | 0 | 1 ===
SELECT fn_active_penalties(5)  AS karthik_active_penalties,
       fn_attendance_rate(1)   AS aarav_attendance_pct,
       fn_avg_rating(1)        AS quiet_room_a_rating,
       fn_is_available(1, 13)  AS roomA_slot13_free,
       fn_is_available(1, 14)  AS roomA_slot14_free
FROM   dual;

PROMPT
PROMPT === T2: member with 2 active penalties is blocked. Expect ORA-20006 ===
DECLARE
  v_id NUMBER;
BEGIN
  sp_book_space(5, 1, 14, v_id);
  DBMS_OUTPUT.PUT_LINE('T2 UNEXPECTED: booked ' || v_id);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('T2 rejected as expected: ' || SQLERRM);
END;
/

PROMPT
PROMPT === T3: booking lifecycle. Expect OK, then ORA-20008, OK cancel, ORA-20012, ORA-20011 ===
DECLARE
  v_id  NUMBER;
  v_id2 NUMBER;
BEGIN
  sp_book_space(2, 1, 14, v_id);
  DBMS_OUTPUT.PUT_LINE('T3a OK: Diya booked Quiet Room A, new booking_id = ' || v_id);
  BEGIN
    sp_book_space(3, 1, 14, v_id2);
    DBMS_OUTPUT.PUT_LINE('T3b UNEXPECTED: double booking allowed');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('T3b rejected as expected: ' || SQLERRM);
  END;
  sp_cancel_booking(v_id, 2);
  DBMS_OUTPUT.PUT_LINE('T3c OK: booking ' || v_id || ' cancelled');
  BEGIN
    sp_cancel_booking(v_id, 2);
    DBMS_OUTPUT.PUT_LINE('T3d UNEXPECTED: cancelled twice');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('T3d rejected as expected: ' || SQLERRM);
  END;
  BEGIN
    sp_cancel_booking(24, 2);
    DBMS_OUTPUT.PUT_LINE('T3e UNEXPECTED: cancelled someone else''s booking');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('T3e rejected as expected: ' || SQLERRM);
  END;
END;
/

PROMPT
PROMPT === T4: check-in / check-out / feedback on booking 23 (simulated 12 Oct times) ===
PROMPT Expect: ORA-20023 for too-early check-in, then OK x3, then ORA-20021 and ORA-20044
DECLARE
BEGIN
  BEGIN
    sp_check_in(24, TIMESTAMP '2026-10-12 07:00:00');
    DBMS_OUTPUT.PUT_LINE('T4a UNEXPECTED: early check-in allowed');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('T4a rejected as expected: ' || SQLERRM);
  END;
  sp_check_in(23, TIMESTAMP '2026-10-12 09:05:00');
  DBMS_OUTPUT.PUT_LINE('T4b OK: booking 23 checked in');
  sp_check_out(23, TIMESTAMP '2026-10-12 10:50:00');
  DBMS_OUTPUT.PUT_LINE('T4c OK: booking 23 checked out (now Completed)');
  sp_submit_feedback(1, 23, 5, 'Test review from the procedure tests');
  DBMS_OUTPUT.PUT_LINE('T4d OK: feedback saved');
  BEGIN
    sp_check_in(23, TIMESTAMP '2026-10-12 09:10:00');
    DBMS_OUTPUT.PUT_LINE('T4e UNEXPECTED: checked in twice');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('T4e rejected as expected: ' || SQLERRM);
  END;
  BEGIN
    sp_submit_feedback(1, 23, 4, 'second review');
    DBMS_OUTPUT.PUT_LINE('T4f UNEXPECTED: second feedback allowed');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('T4f rejected as expected: ' || SQLERRM);
  END;
END;
/

PROMPT
PROMPT === Result check: booking 23 should now be Completed with a check-in row ===
SELECT b.booking_id, b.booking_status, c.checkin_status,
       TO_CHAR(c.checkin_time, 'HH24:MI') AS in_time, TO_CHAR(c.checkout_time, 'HH24:MI') AS out_time
FROM   booking b
LEFT   JOIN check_in c ON c.booking_id = b.booking_id
WHERE  b.booking_id IN (23, 24)
ORDER  BY b.booking_id;

PROMPT
PROMPT === T4b: days left on each penalty (only Active ones have a number) ===
PROMPT Expect: penalties 1 and 4 (Karthik, 5 and 6 Oct) show about 8 and 9 days from 11 Oct; 2 and 3 are empty
SELECT penalty_id, status, TO_CHAR(penalty_date, 'DD Mon') AS issued, fn_penalty_days_left(penalty_id) AS days_left
FROM   penalty
ORDER  BY penalty_id;

PROMPT
PROMPT === T5: penalty expiry. Karthik Raj's two penalties are from 5 and 6 Oct 2026 ===
PROMPT Expect: 0 expired now, then 2 expired as of 21 Oct, then Karthik can book again
DECLARE
  v_n  NUMBER;
  v_id NUMBER;
BEGIN
  sp_expire_penalties(NULL, v_n);
  DBMS_OUTPUT.PUT_LINE('T5a expired now: ' || v_n || ' (penalties are younger than 14 days)');
  sp_expire_penalties(TO_DATE('2026-10-21 00:00', 'YYYY-MM-DD HH24:MI'), v_n);
  DBMS_OUTPUT.PUT_LINE('T5b expired as of 21 Oct: ' || v_n);
  DBMS_OUTPUT.PUT_LINE('T5c Karthik active penalties now: ' || fn_active_penalties(5));
  sp_book_space(5, 1, 14, v_id);
  DBMS_OUTPUT.PUT_LINE('T5d OK: Karthik can book again, booking_id = ' || v_id);
END;
/
