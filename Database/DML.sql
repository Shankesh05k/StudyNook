SET DEFINE OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON

DELETE FROM feedback;
DELETE FROM penalty;
DELETE FROM check_in;
DELETE FROM booking;
DELETE FROM time_slot;
DELETE FROM study_space;
DELETE FROM campus_member;
COMMIT;

BEGIN
  FOR q IN (SELECT sequence_name FROM user_sequences
            WHERE sequence_name IN ('SEQ_MEMBER','SEQ_SPACE','SEQ_SLOT','SEQ_BOOKING',
                                    'SEQ_CHECKIN','SEQ_PENALTY','SEQ_FEEDBACK')) LOOP
    EXECUTE IMMEDIATE 'DROP SEQUENCE ' || q.sequence_name;
    EXECUTE IMMEDIATE 'CREATE SEQUENCE ' || q.sequence_name || ' START WITH 1 INCREMENT BY 1 NOCACHE';
  END LOOP;
END;
/

-- ---------- 1. CAMPUS_MEMBER (15) : 10 students, 3 TAs, 2 professors ----------
-- 1
INSERT INTO campus_member (name, email, phone, department, member_type) VALUES ('Aarav Mehta',     'aarav.mehta@vit.ac.in',     '9876500001', 'CSE',         'Student');
-- 2
INSERT INTO campus_member (name, email, phone, department, member_type) VALUES ('Diya Nair',       'diya.nair@vit.ac.in',       '9876500002', 'CSE',         'Student');
-- 3
INSERT INTO campus_member (name, email, phone, department, member_type) VALUES ('Rohan Iyer',      'rohan.iyer@vit.ac.in',      '9876500003', 'ECE',         'Student');
-- 4
INSERT INTO campus_member (name, email, phone, department, member_type) VALUES ('Sneha Reddy',     'sneha.reddy@vit.ac.in',     '9876500004', 'IT',          'Student');
-- 5
INSERT INTO campus_member (name, email, phone, department, member_type) VALUES ('Karthik Raj',     'karthik.raj@vit.ac.in',     '9876500005', 'CSE',         'Student');
-- 6
INSERT INTO campus_member (name, email, phone, department, member_type) VALUES ('Priya Sharma',    'priya.sharma@vit.ac.in',    '9876500006', 'Mechanical',  'Student');
-- 7
INSERT INTO campus_member (name, email, phone, department, member_type) VALUES ('Vikram Singh',    'vikram.singh@vit.ac.in',    '9876500007', 'Civil',       'Student');
-- 8
INSERT INTO campus_member (name, email, phone, department, member_type) VALUES ('Ananya Das',      'ananya.das@vit.ac.in',      '9876500008', 'CSE',         'Student');
-- 9
INSERT INTO campus_member (name, email, phone, department, member_type) VALUES ('Mohammed Faiz',   'mohammed.faiz@vit.ac.in',   '9876500009', 'ECE',         'Student');
-- 10
INSERT INTO campus_member (name, email, phone, department, member_type) VALUES ('Lakshmi Menon',   'lakshmi.menon@vit.ac.in',   '9876500010', 'IT',          'Student');
-- 11
INSERT INTO campus_member (name, email, phone, department, member_type) VALUES ('Arjun Pillai',    'arjun.pillai@vit.ac.in',    '9876500011', 'CSE',         'Teaching Assistant');
-- 12
INSERT INTO campus_member (name, email, phone, department, member_type) VALUES ('Meera Krishnan',  'meera.krishnan@vit.ac.in',  '9876500012', 'ECE',         'Teaching Assistant');
-- 13
INSERT INTO campus_member (name, email, phone, department, member_type) VALUES ('Suresh Babu',     'suresh.babu@vit.ac.in',     '9876500013', 'Mechanical',  'Teaching Assistant');
-- 14
INSERT INTO campus_member (name, email, phone, department, member_type) VALUES ('Dr. Kavitha R',   'kavitha.r@vit.ac.in',       '9876500014', 'CSE',         'Professor');
-- 15
INSERT INTO campus_member (name, email, phone, department, member_type) VALUES ('Dr. Ramesh T',    'ramesh.t@vit.ac.in',        '9876500015', 'IT',          'Professor');

-- ---------- 2. STUDY_SPACE (8) ----------
-- 1
INSERT INTO study_space (space_name, location, capacity, space_type, status) VALUES ('Quiet Room A',    'Library, Ground Floor',    4,  'Study Room',      'Available');
-- 2
INSERT INTO study_space (space_name, location, capacity, space_type, status) VALUES ('Quiet Room B',    'Library, Ground Floor',    4,  'Study Room',      'Available');
-- 3
INSERT INTO study_space (space_name, location, capacity, space_type, status) VALUES ('Quiet Room C',    'Library, First Floor',     6,  'Study Room',      'Available');
-- 4
INSERT INTO study_space (space_name, location, capacity, space_type, status) VALUES ('Discussion Hub 1','Library, First Floor',  8,  'Discussion Area', 'Available');
-- 5
INSERT INTO study_space (space_name, location, capacity, space_type, status) VALUES ('Discussion Hub 2','Library, Second Floor',  8,  'Discussion Area', 'Available');
-- 6
INSERT INTO study_space (space_name, location, capacity, space_type, status) VALUES ('Discussion Hub 3','Library, Third Floor',  10, 'Discussion Area', 'Available');
-- 7
INSERT INTO study_space (space_name, location, capacity, space_type, status) VALUES ('Innovation Lab',  'PRP , Fifth Floor',           12, 'Project Space',   'Available');
-- 8
INSERT INTO study_space (space_name, location, capacity, space_type, status) VALUES ('Maker Studio',    'SJT Eighth Floor',           15, 'Project Space',   'Maintenance');

-- ---------- 3. TIME_SLOT (20) : 4 slots/day x 5 days ----------
-- Slot ids 1-12  = 5, 6, 7 Oct 2026 (past, used for history)
-- Slot ids 13-20 = 12, 13 Oct 2026 (upcoming bookings)
DECLARE
  TYPE t_num IS TABLE OF NUMBER;
  TYPE t_str IS TABLE OF VARCHAR2(5);
  v_offsets t_num := t_num(0, 1, 2, 7, 8);                       -- days after 5 Oct 2026
  v_starts  t_str := t_str('09:00', '11:00', '14:00', '16:00');
  v_ends    t_str := t_str('11:00', '13:00', '16:00', '18:00');
BEGIN
  FOR i IN 1 .. v_offsets.COUNT LOOP
    FOR j IN 1 .. v_starts.COUNT LOOP
      INSERT INTO time_slot (slot_date, start_time, end_time)
      VALUES ((TRUNC(SYSDATE) - 6) + v_offsets(i), v_starts(j), v_ends(j));
    END LOOP;
  END LOOP;
END;
/

-- ---------- 4. BOOKING (30) ----------
-- columns: member, space, slot, booking_date, status
-- Day 1 (5 Oct)
-- b1
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (1,  1, 1,  (TRUNC(SYSDATE) - 8), 'Completed');
-- b2
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (2,  1, 2,  (TRUNC(SYSDATE) - 8), 'Completed');
-- b3
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (3,  2, 1,  (TRUNC(SYSDATE) - 8), 'Completed');
-- b4
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (4,  4, 2,  (TRUNC(SYSDATE) - 7), 'Completed');
-- b5
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (5,  4, 3,  (TRUNC(SYSDATE) - 7), 'No-Show');
-- b6
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (6,  7, 3,  (TRUNC(SYSDATE) - 7), 'Completed');
-- b7 (slot freed...)
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (7,  3, 4,  (TRUNC(SYSDATE) - 7), 'Cancelled');
-- b8 (...and re-booked by another member)
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (8,  3, 4,  (TRUNC(SYSDATE) - 7), 'Completed');
-- Day 2 (6 Oct)
-- b9
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (1,  2, 5,  (TRUNC(SYSDATE) - 7), 'Completed');
-- b10
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (9,  5, 5,  (TRUNC(SYSDATE) - 6), 'No-Show');
-- b11
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (10, 5, 6,  (TRUNC(SYSDATE) - 6), 'Completed');
-- b12
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (11, 6, 6,  (TRUNC(SYSDATE) - 6), 'Completed');
-- b13
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (12, 7, 7,  (TRUNC(SYSDATE) - 6), 'Completed');
-- b14
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (2,  1, 8,  (TRUNC(SYSDATE) - 6), 'No-Show');
-- b15
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (13, 6, 7,  (TRUNC(SYSDATE) - 6), 'Completed');
-- b16 (repeat no-show)
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (5,  4, 8,  (TRUNC(SYSDATE) - 6), 'No-Show');
-- Day 3 (7 Oct)
-- b17
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (3,  1, 9,  (TRUNC(SYSDATE) - 6), 'Completed');
-- b18
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (14, 7, 10, (TRUNC(SYSDATE) - 5), 'Completed');
-- b19
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (4,  2, 10, (TRUNC(SYSDATE) - 5), 'Cancelled');
-- b20
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (6,  3, 11, (TRUNC(SYSDATE) - 5), 'Completed');
-- b21 (no penalty yet: cursor demo)
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (15, 5, 12, (TRUNC(SYSDATE) - 5), 'No-Show');
-- b22
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (7,  6, 9,  (TRUNC(SYSDATE) - 6), 'Completed');
-- Upcoming (12-13 Oct)
-- b23
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (1,  1, 13, (TRUNC(SYSDATE) - 2), 'Confirmed');
-- b24
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (8,  4, 13, (TRUNC(SYSDATE) - 2), 'Confirmed');
-- b25
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (10, 2, 14, (TRUNC(SYSDATE) - 2), 'Confirmed');
-- b26
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (12, 7, 15, (TRUNC(SYSDATE) - 1), 'Confirmed');
-- b27
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (9,  5, 16, (TRUNC(SYSDATE) - 2), 'Cancelled');
-- b28
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (3,  5, 16, (TRUNC(SYSDATE) - 1), 'Confirmed');
-- b29
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (13, 6, 17, (TRUNC(SYSDATE) - 1), 'Confirmed');
-- b30
INSERT INTO booking (member_id, space_id, slot_id, booking_date, booking_status) VALUES (11, 3, 18, (TRUNC(SYSDATE) - 1), 'Confirmed');

-- ---------- 5. CHECK_IN (15) : one per Completed booking ----------
INSERT INTO check_in (booking_id, checkin_time, checkout_time, checkin_status) VALUES (1,  (TRUNC(SYSDATE) - 6 + 9/24 + 4/1440), (TRUNC(SYSDATE) - 6 + 10/24 + 52/1440), 'Checked Out');
INSERT INTO check_in (booking_id, checkin_time, checkout_time, checkin_status) VALUES (2,  (TRUNC(SYSDATE) - 6 + 11/24 + 2/1440), (TRUNC(SYSDATE) - 6 + 12/24 + 55/1440), 'Checked Out');
INSERT INTO check_in (booking_id, checkin_time, checkout_time, checkin_status) VALUES (3,  (TRUNC(SYSDATE) - 6 + 9/24 + 10/1440), (TRUNC(SYSDATE) - 6 + 10/24 + 58/1440), 'Checked Out');
INSERT INTO check_in (booking_id, checkin_time, checkout_time, checkin_status) VALUES (4,  (TRUNC(SYSDATE) - 6 + 11/24 + 5/1440), (TRUNC(SYSDATE) - 6 + 12/24 + 40/1440), 'Checked Out');
INSERT INTO check_in (booking_id, checkin_time, checkout_time, checkin_status) VALUES (6,  (TRUNC(SYSDATE) - 6 + 14/24 + 3/1440), (TRUNC(SYSDATE) - 6 + 15/24 + 58/1440), 'Checked Out');
INSERT INTO check_in (booking_id, checkin_time, checkout_time, checkin_status) VALUES (8,  (TRUNC(SYSDATE) - 6 + 16/24 + 1/1440), (TRUNC(SYSDATE) - 6 + 17/24 + 45/1440), 'Checked Out');
INSERT INTO check_in (booking_id, checkin_time, checkout_time, checkin_status) VALUES (9,  (TRUNC(SYSDATE) - 5 + 9/24), (TRUNC(SYSDATE) - 5 + 10/24 + 30/1440), 'Checked Out');
INSERT INTO check_in (booking_id, checkin_time, checkout_time, checkin_status) VALUES (11, (TRUNC(SYSDATE) - 5 + 11/24 + 10/1440), (TRUNC(SYSDATE) - 5 + 12/24 + 59/1440), 'Checked Out');
INSERT INTO check_in (booking_id, checkin_time, checkout_time, checkin_status) VALUES (12, (TRUNC(SYSDATE) - 5 + 11/24), (TRUNC(SYSDATE) - 5 + 12/24 + 50/1440), 'Checked Out');
INSERT INTO check_in (booking_id, checkin_time, checkout_time, checkin_status) VALUES (13, (TRUNC(SYSDATE) - 5 + 14/24 + 7/1440), (TRUNC(SYSDATE) - 5 + 15/24 + 55/1440), 'Checked Out');
INSERT INTO check_in (booking_id, checkin_time, checkout_time, checkin_status) VALUES (15, (TRUNC(SYSDATE) - 5 + 14/24), (TRUNC(SYSDATE) - 5 + 15/24 + 30/1440), 'Checked Out');
INSERT INTO check_in (booking_id, checkin_time, checkout_time, checkin_status) VALUES (17, (TRUNC(SYSDATE) - 4 + 9/24 + 2/1440), (TRUNC(SYSDATE) - 4 + 10/24 + 59/1440), 'Checked Out');
INSERT INTO check_in (booking_id, checkin_time, checkout_time, checkin_status) VALUES (18, (TRUNC(SYSDATE) - 4 + 11/24 + 15/1440), (TRUNC(SYSDATE) - 4 + 12/24 + 45/1440), 'Checked Out');
INSERT INTO check_in (booking_id, checkin_time, checkout_time, checkin_status) VALUES (20, (TRUNC(SYSDATE) - 4 + 14/24 + 1/1440), (TRUNC(SYSDATE) - 4 + 15/24 + 50/1440), 'Checked Out');
INSERT INTO check_in (booking_id, checkin_time, checkout_time, checkin_status) VALUES (22, (TRUNC(SYSDATE) - 4 + 9/24 + 20/1440), (TRUNC(SYSDATE) - 4 + 10/24 + 40/1440), 'Checked Out');

-- ---------- 6. PENALTY (4) : for no-shows b5, b10, b14, b16 ----------
-- No-show b21 (member 15) is deliberately left WITHOUT a penalty so the
-- no-show sweep cursor (later step) has something to find.
INSERT INTO penalty (member_id, booking_id, reason, penalty_date, status) VALUES (5, 5,  'No-show for booking', (TRUNC(SYSDATE) - 6), 'Active');
INSERT INTO penalty (member_id, booking_id, reason, penalty_date, status) VALUES (9, 10, 'No-show for booking', (TRUNC(SYSDATE) - 5), 'Active');
INSERT INTO penalty (member_id, booking_id, reason, penalty_date, status) VALUES (2, 14, 'No-show for booking', (TRUNC(SYSDATE) - 5), 'Waived');
INSERT INTO penalty (member_id, booking_id, reason, penalty_date, status) VALUES (5, 16, 'Repeat no-show',      (TRUNC(SYSDATE) - 5), 'Active');

-- ---------- 7. FEEDBACK (12) : only on Completed bookings; member & space match the booking ----------
INSERT INTO feedback (member_id, space_id, booking_id, rating, comments, feedback_date) VALUES (1,  1, 1,  5, 'Quiet and well lit.',                 (TRUNC(SYSDATE) - 6));
INSERT INTO feedback (member_id, space_id, booking_id, rating, comments, feedback_date) VALUES (2,  1, 2,  4, 'Good room, chairs could be better.',  (TRUNC(SYSDATE) - 6));
INSERT INTO feedback (member_id, space_id, booking_id, rating, comments, feedback_date) VALUES (3,  2, 3,  4, 'Nice for solo study.',               (TRUNC(SYSDATE) - 6));
INSERT INTO feedback (member_id, space_id, booking_id, rating, comments, feedback_date) VALUES (4,  4, 4,  3, 'Whiteboard markers were dry.',        (TRUNC(SYSDATE) - 6));
INSERT INTO feedback (member_id, space_id, booking_id, rating, comments, feedback_date) VALUES (6,  7, 6,  5, 'Great for project work.',            (TRUNC(SYSDATE) - 6));
INSERT INTO feedback (member_id, space_id, booking_id, rating, comments, feedback_date) VALUES (1,  2, 9,  4, 'Comfortable, AC a bit cold.',        (TRUNC(SYSDATE) - 5));
INSERT INTO feedback (member_id, space_id, booking_id, rating, comments, feedback_date) VALUES (10, 5, 11, 2, 'Projector was not working.',         (TRUNC(SYSDATE) - 5));
INSERT INTO feedback (member_id, space_id, booking_id, rating, comments, feedback_date) VALUES (11, 6, 12, 5, 'Perfect for tutorial sessions.',    (TRUNC(SYSDATE) - 5));
INSERT INTO feedback (member_id, space_id, booking_id, rating, comments, feedback_date) VALUES (12, 7, 13, 4, 'Plenty of power sockets.',          (TRUNC(SYSDATE) - 5));
INSERT INTO feedback (member_id, space_id, booking_id, rating, comments, feedback_date) VALUES (3,  1, 17, 5, 'My favourite room.',                (TRUNC(SYSDATE) - 4));
INSERT INTO feedback (member_id, space_id, booking_id, rating, comments, feedback_date) VALUES (14, 7, 18, 4, 'Good for research meetings.',       (TRUNC(SYSDATE) - 4));
INSERT INTO feedback (member_id, space_id, booking_id, rating, comments, feedback_date) VALUES (6,  3, 20, 3, 'Slightly noisy from corridor.',     (TRUNC(SYSDATE) - 4));

COMMIT;

-- =====================================================================
-- MODIFICATION & DELETION (UPDATE / DELETE demonstrations)
-- =====================================================================

-- U1: a member changes department
UPDATE campus_member SET department = 'AI and Data Engineering' WHERE member_id = 1;

-- U2: room expanded - capacity increase
UPDATE study_space SET capacity = 8 WHERE space_name = 'Quiet Room C';

-- U3: member has served their penalty - mark it Cleared
UPDATE penalty SET status = 'Cleared' WHERE penalty_id = 2;

-- U4: Maker Studio maintenance finished - open it for booking
UPDATE study_space SET status = 'Available' WHERE space_name = 'Maker Studio';

-- D1: delete a cancelled booking that has no check-in/penalty/feedback
DELETE FROM booking WHERE booking_id = 19 AND booking_status = 'Cancelled';

-- D2: insert a mistaken duplicate member, then remove it
INSERT INTO campus_member (name, email, phone, department, member_type)
VALUES ('Test User', 'test.user@vit.ac.in', '9000000000', 'CSE', 'Student');
DELETE FROM campus_member WHERE email = 'test.user@vit.ac.in';

COMMIT;


-- ---------- Verify row counts (expect 15 / 8 / 20 / 29 / 15 / 4 / 12) ----------
SELECT 'CAMPUS_MEMBER' AS tbl, COUNT(*) AS rows_ FROM campus_member UNION ALL
SELECT 'STUDY_SPACE',   COUNT(*) FROM study_space   UNION ALL
SELECT 'TIME_SLOT',     COUNT(*) FROM time_slot     UNION ALL
SELECT 'BOOKING',       COUNT(*) FROM booking       UNION ALL
SELECT 'CHECK_IN',      COUNT(*) FROM check_in      UNION ALL
SELECT 'PENALTY',       COUNT(*) FROM penalty       UNION ALL
SELECT 'FEEDBACK',      COUNT(*) FROM feedback;
