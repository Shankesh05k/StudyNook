SET DEFINE OFF
SET LINESIZE 160
SET PAGESIZE 50
COLUMN name        FORMAT A20
COLUMN space_name  FORMAT A18
COLUMN department  FORMAT A24
COLUMN member_type FORMAT A20
COLUMN slot        FORMAT A13

PROMPT
PROMPT === Q1 [LEFT JOIN + CASE + GROUP BY] Space utilization and attendance rate ===
PROMPT Business use: which spaces are booked but not actually used?
PROMPT Expect 8 rows: Quiet Room A 5/3/1/75, Discussion Hubs 1 and 2 at 33.3, Maker Studio 0 bookings
SELECT s.space_name,
       COUNT(b.booking_id) AS total_bookings,
       SUM(CASE WHEN b.booking_status = 'Completed' THEN 1 ELSE 0 END) AS attended,
       SUM(CASE WHEN b.booking_status = 'No-Show'   THEN 1 ELSE 0 END) AS no_shows,
       ROUND(100 * SUM(CASE WHEN b.booking_status = 'Completed' THEN 1 ELSE 0 END)
             / NULLIF(SUM(CASE WHEN b.booking_status IN ('Completed','No-Show') THEN 1 ELSE 0 END), 0), 1) AS attendance_pct
FROM   study_space s
LEFT   JOIN booking b ON b.space_id = s.space_id
GROUP  BY s.space_name
ORDER  BY attendance_pct, s.space_name;

PROMPT
PROMPT === Q2 [GROUP BY + HAVING] Repeat offenders (2 or more no-shows) ===
PROMPT Expect 1 row: Karthik Raj, 2
SELECT m.name, m.department, COUNT(*) AS no_shows
FROM   campus_member m
JOIN   booking b ON b.member_id = m.member_id
WHERE  b.booking_status = 'No-Show'
GROUP  BY m.member_id, m.name, m.department
HAVING COUNT(*) >= 2;

PROMPT
PROMPT === Q3 [NOT EXISTS subquery] Completed bookings with no feedback yet ===
PROMPT Expect 3 rows: booking 8 Ananya Das, 15 Suresh Babu, 22 Vikram Singh
SELECT b.booking_id, m.name, s.space_name
FROM   booking b
JOIN   campus_member m ON m.member_id = b.member_id
JOIN   study_space   s ON s.space_id  = b.space_id
WHERE  b.booking_status = 'Completed'
AND    NOT EXISTS (SELECT 1 FROM feedback f WHERE f.booking_id = b.booking_id)
ORDER  BY b.booking_id;

PROMPT
PROMPT === Q4 [Scalar subquery in HAVING] Spaces rated below the overall average (overall = 4.0) ===
PROMPT Expect 3 rows: Discussion Hub 2 (2), Discussion Hub 1 (3), Quiet Room C (3)
SELECT s.space_name, COUNT(f.feedback_id) AS reviews, ROUND(AVG(f.rating), 2) AS avg_rating
FROM   study_space s
JOIN   feedback f ON f.space_id = s.space_id
GROUP  BY s.space_name
HAVING AVG(f.rating) < (SELECT AVG(rating) FROM feedback)
ORDER  BY avg_rating, s.space_name;

PROMPT
PROMPT === Q5 [Date arithmetic + GROUP BY] Average session length (minutes) by member type ===
PROMPT Expect: Student 11 sessions about 104.4, Teaching Assistant 3 about 102.7, Professor 1 = 90
SELECT m.member_type,
       COUNT(*) AS sessions,
       ROUND(AVG((CAST(c.checkout_time AS DATE) - CAST(c.checkin_time AS DATE)) * 24 * 60), 1) AS avg_minutes
FROM   check_in c
JOIN   booking b       ON b.booking_id = c.booking_id
JOIN   campus_member m ON m.member_id  = b.member_id
WHERE  c.checkout_time IS NOT NULL
GROUP  BY m.member_type
ORDER  BY sessions DESC;

PROMPT
PROMPT === Q6 [JOIN with filter in ON clause] Most popular time slots (active bookings only) ===
PROMPT Expect: 09:00-11:00 = 9, 11:00-13:00 = 7, 14:00-16:00 = 6, 16:00-18:00 = 5
SELECT t.start_time || '-' || t.end_time AS slot, COUNT(b.booking_id) AS bookings
FROM   time_slot t
JOIN   booking b ON b.slot_id = t.slot_id AND b.booking_status <> 'Cancelled'
GROUP  BY t.start_time, t.end_time
ORDER  BY bookings DESC, slot;

PROMPT
PROMPT === Q7 [Multi-table JOIN + GROUP BY] No-show rate by department ===
PROMPT Expect: CSE 9 bookings/3 no-shows (33.3), ECE 7/1 (14.3), IT 4/1 (25), others 0
SELECT m.department,
       COUNT(b.booking_id) AS bookings,
       SUM(CASE WHEN b.booking_status = 'No-Show' THEN 1 ELSE 0 END) AS no_shows,
       ROUND(100 * SUM(CASE WHEN b.booking_status = 'No-Show' THEN 1 ELSE 0 END) / COUNT(b.booking_id), 1) AS no_show_pct
FROM   campus_member m
JOIN   booking b ON b.member_id = m.member_id
GROUP  BY m.department
ORDER  BY no_shows DESC, m.department;

PROMPT
PROMPT === Q8 [Set operation MINUS inside IN] Members who booked but never actually attended ===
PROMPT Expect 3 rows: Dr. Ramesh T, Karthik Raj, Mohammed Faiz
SELECT m.member_id, m.name, m.member_type
FROM   campus_member m
WHERE  m.member_id IN (SELECT member_id FROM booking
                       MINUS
                       SELECT member_id FROM booking WHERE booking_status = 'Completed')
ORDER  BY m.name;

PROMPT
PROMPT === Q9 [Inline view + ROWNUM] Top 3 most-booked spaces (ties broken by name) ===
PROMPT Expect: Quiet Room A 5, then Discussion Hub 1 = 4, Discussion Hub 2 = 4
SELECT *
FROM  (SELECT s.space_name, COUNT(b.booking_id) AS active_bookings
       FROM   study_space s
       JOIN   booking b ON b.space_id = s.space_id AND b.booking_status <> 'Cancelled'
       GROUP  BY s.space_name
       ORDER  BY active_bookings DESC, s.space_name)
WHERE ROWNUM <= 3;
