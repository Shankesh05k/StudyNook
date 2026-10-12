-- StudyNook - quick sanity checks (run after 01_ddl.sql and 02_dml.sql)
SET DEFINE OFF
SET LINESIZE 150
SET PAGESIZE 50
COLUMN name        FORMAT A20
COLUMN space_name  FORMAT A18
COLUMN booking_status FORMAT A15

PROMPT
PROMPT === Check 1: bookings per status (expect Completed 15, Confirmed 7, No-Show 5, Cancelled 2) ===
SELECT booking_status, COUNT(*) AS total
FROM   booking
GROUP  BY booking_status
ORDER  BY total DESC;

PROMPT
PROMPT === Check 2: upcoming confirmed bookings, 4-table join (expect 7 rows, 12-13 Oct) ===
SELECT b.booking_id, m.name, s.space_name,
       TO_CHAR(t.slot_date, 'DD-MON-YYYY') AS slot_date, t.start_time, t.end_time
FROM   booking b
JOIN   campus_member m ON m.member_id = b.member_id
JOIN   study_space   s ON s.space_id  = b.space_id
JOIN   time_slot     t ON t.slot_id   = b.slot_id
WHERE  b.booking_status = 'Confirmed'
ORDER  BY t.slot_date, t.start_time, b.booking_id;

PROMPT
PROMPT === Check 3: no-shows vs penalties per member (expect Karthik Raj 2/2, Dr. Ramesh T 1/0) ===
SELECT m.name, COUNT(b.booking_id) AS no_shows, COUNT(p.penalty_id) AS penalties
FROM   campus_member m
JOIN   booking b ON b.member_id = m.member_id AND b.booking_status = 'No-Show'
LEFT   JOIN penalty p ON p.booking_id = b.booking_id
GROUP  BY m.name
ORDER  BY no_shows DESC, m.name;

PROMPT
PROMPT === Check 4: average rating per space (expect 7 rows, Discussion Hub 3 on top) ===
SELECT s.space_name, COUNT(f.feedback_id) AS reviews, ROUND(AVG(f.rating), 2) AS avg_rating
FROM   study_space s
JOIN   feedback f ON f.space_id = s.space_id
GROUP  BY s.space_name
ORDER  BY avg_rating DESC, s.space_name;

PROMPT
PROMPT === Check 5: any double-booked space+slot among active bookings? (expect: no rows selected) ===
SELECT space_id, slot_id, COUNT(*) AS active_bookings
FROM   booking
WHERE  booking_status <> 'Cancelled'
GROUP  BY space_id, slot_id
HAVING COUNT(*) > 1;

PROMPT
PROMPT === Check 6: rule enforcement - BOTH statements below are MEANT to fail ===
PROMPT --- 6a: double booking (expect ORA-00001 on UQ_ACTIVE_SPACE_SLOT)
INSERT INTO booking (member_id, space_id, slot_id) VALUES (2, 1, 13);

PROMPT --- 6b: deleting a booking that has a check-in (expect ORA-02292 child record found)
DELETE FROM booking WHERE booking_id = 1;

ROLLBACK;
