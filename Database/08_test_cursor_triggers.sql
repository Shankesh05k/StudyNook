SET DEFINE OFF
SET SERVEROUTPUT ON
SET LINESIZE 150
COLUMN name       FORMAT A18
COLUMN reason     FORMAT A22
COLUMN old_status FORMAT A12
COLUMN new_status FORMAT A12
COLUMN changed_by FORMAT A12

PROMPT
PROMPT === TR1: a Completed booking cannot go back to Confirmed. Expect ORA-20050 ===
BEGIN
  UPDATE booking SET booking_status = 'Confirmed' WHERE booking_id = 1;
  DBMS_OUTPUT.PUT_LINE('TR1 UNEXPECTED: status change allowed');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('TR1 rejected as expected: ' || SQLERRM);
END;
/

PROMPT
PROMPT === TR2: feedback integrity trigger. Expect ORA-20051, then ORA-20054 ===
BEGIN
  INSERT INTO feedback (member_id, space_id, booking_id, rating) VALUES (2, 4, 8, 4);
  DBMS_OUTPUT.PUT_LINE('TR2a UNEXPECTED: feedback from the wrong member allowed');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('TR2a rejected as expected: ' || SQLERRM);
END;
/
BEGIN
  INSERT INTO feedback (member_id, space_id, booking_id, rating) VALUES (1, 1, 23, 5);
  DBMS_OUTPUT.PUT_LINE('TR2b UNEXPECTED: feedback on a Confirmed booking allowed');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('TR2b rejected as expected: ' || SQLERRM);
END;
/

PROMPT
PROMPT === TR3: a member cancels booking 25, the audit trigger logs it ===
BEGIN
  sp_cancel_booking(25, 10);
  DBMS_OUTPUT.PUT_LINE('TR3 OK: booking 25 cancelled');
END;
/

PROMPT
PROMPT === TR4: closing Discussion Hub 2 (space 5) for maintenance auto-cancels its future bookings ===
PROMPT Expect booking 28 to become Cancelled (booking 28 is Rohan Iyer on 12 Oct 16:00)
UPDATE study_space SET status = 'Maintenance' WHERE space_id = 5;
SELECT booking_id, booking_status FROM booking WHERE booking_id IN (28, 11, 21) ORDER BY booking_id;
PROMPT (bookings 11 and 21 are in the past, so they must stay Completed and No-Show)
UPDATE study_space SET status = 'Available' WHERE space_id = 5;
COMMIT;

PROMPT
PROMPT === CUR1: no-show sweep at the real current time ===
PROMPT Expect: marked 0, penalties issued 1 (the old no-show, booking 21, gets its missing penalty)
DECLARE
  v_marked NUMBER;
  v_pen    NUMBER;
BEGIN
  sp_mark_no_shows(NULL, v_marked, v_pen);
  DBMS_OUTPUT.PUT_LINE('CUR1: marked ' || v_marked || ' bookings as No-Show, issued ' || v_pen || ' penalties');
END;
/
SELECT p.penalty_id, m.name, p.booking_id, p.reason, p.status
FROM   penalty p JOIN campus_member m ON m.member_id = p.member_id
WHERE  p.booking_id = 21;

PROMPT
PROMPT === CUR2: sweep as if it were 14 Oct 2026, after all the 12-13 Oct slots ended ===
PROMPT Expect: marked 5 (bookings 23, 24, 26, 29, 30), penalties issued 5 by trigger TR3
DECLARE
  v_marked NUMBER;
  v_pen    NUMBER;
BEGIN
  sp_mark_no_shows((TRUNC(SYSDATE) + 3), v_marked, v_pen);
  DBMS_OUTPUT.PUT_LINE('CUR2: marked ' || v_marked || ' bookings as No-Show, issued ' || v_pen || ' penalties');
END;
/

PROMPT
PROMPT === CUR3: printed penalty report (cursor FOR loop). Expect Karthik Raj on top with 2, blocked ===
EXEC sp_penalty_report

PROMPT
PROMPT === Audit log: expect 7 rows (2 cancellations, then 5 Confirmed -> No-Show) ===
SELECT audit_id, booking_id, old_status, new_status, TO_CHAR(changed_at, 'HH24:MI:SS') AS at_time, changed_by
FROM   booking_audit
ORDER  BY audit_id;
