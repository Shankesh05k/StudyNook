-- =====================================================================
-- StudyNook : Smart Campus Study Space Reservation & Utilization System
-- Review II - Step 1 : DDL & Constraints   (Oracle 10g / 11g / 12c+ compatible)
-- =====================================================================

-- ---------- Clean re-run (child tables first) ----------
BEGIN
  FOR t IN (SELECT table_name FROM user_tables
            WHERE table_name IN ('FEEDBACK','PENALTY','CHECK_IN','BOOKING',
                                 'TIME_SLOT','STUDY_SPACE','CAMPUS_MEMBER')) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
  END LOOP;
  FOR q IN (SELECT sequence_name FROM user_sequences
            WHERE sequence_name IN ('SEQ_MEMBER','SEQ_SPACE','SEQ_SLOT','SEQ_BOOKING',
                                    'SEQ_CHECKIN','SEQ_PENALTY','SEQ_FEEDBACK')) LOOP
    EXECUTE IMMEDIATE 'DROP SEQUENCE ' || q.sequence_name;
  END LOOP;
END;
/

-- ---------- 1. CAMPUS_MEMBER ----------
CREATE TABLE campus_member (
  member_id    NUMBER,
  name         VARCHAR2(60)  NOT NULL,
  email        VARCHAR2(100) NOT NULL,
  phone        VARCHAR2(15),
  department   VARCHAR2(50),
  member_type  VARCHAR2(20)  NOT NULL,
  CONSTRAINT pk_member        PRIMARY KEY (member_id),
  CONSTRAINT uq_member_email  UNIQUE (email),
  CONSTRAINT ck_member_type   CHECK (member_type IN ('Student','Teaching Assistant','Professor')),
  CONSTRAINT ck_member_email  CHECK (email LIKE '%_@_%._%'),
  CONSTRAINT ck_member_phone  CHECK (phone IS NULL OR REGEXP_LIKE(phone, '^[0-9+ -]{7,15}$'))
);

-- ---------- 2. STUDY_SPACE ----------
CREATE TABLE study_space (
  space_id    NUMBER,
  space_name  VARCHAR2(60) NOT NULL,
  location    VARCHAR2(80) NOT NULL,
  capacity    NUMBER(3)    NOT NULL,
  space_type  VARCHAR2(30) NOT NULL,
  status      VARCHAR2(15) DEFAULT 'Available' NOT NULL,
  CONSTRAINT pk_space         PRIMARY KEY (space_id),
  CONSTRAINT uq_space_name    UNIQUE (space_name, location),
  CONSTRAINT ck_space_cap     CHECK (capacity > 0),
  CONSTRAINT ck_space_type    CHECK (space_type IN ('Study Room','Discussion Area','Project Space')),
  CONSTRAINT ck_space_status  CHECK (status IN ('Available','Maintenance','Closed'))
);

-- ---------- 3. TIME_SLOT ----------
-- Times stored as 'HH24:MI' text (zero-padded, so string comparison is valid)
CREATE TABLE time_slot (
  slot_id     NUMBER,
  slot_date   DATE        NOT NULL,
  start_time  VARCHAR2(5) NOT NULL,
  end_time    VARCHAR2(5) NOT NULL,
  CONSTRAINT pk_slot        PRIMARY KEY (slot_id),
  CONSTRAINT uq_slot        UNIQUE (slot_date, start_time, end_time),
  CONSTRAINT ck_slot_fmt    CHECK (REGEXP_LIKE(start_time, '^([01][0-9]|2[0-3]):[0-5][0-9]$')
                              AND REGEXP_LIKE(end_time,   '^([01][0-9]|2[0-3]):[0-5][0-9]$')),
  CONSTRAINT ck_slot_order  CHECK (end_time > start_time)
);

-- ---------- 4. BOOKING (central entity) ----------
CREATE TABLE booking (
  booking_id      NUMBER,
  member_id       NUMBER       NOT NULL,
  space_id        NUMBER       NOT NULL,
  slot_id         NUMBER       NOT NULL,
  booking_date    DATE         DEFAULT SYSDATE NOT NULL,
  booking_status  VARCHAR2(15) DEFAULT 'Confirmed' NOT NULL,
  CONSTRAINT pk_booking        PRIMARY KEY (booking_id),
  CONSTRAINT fk_bk_member      FOREIGN KEY (member_id) REFERENCES campus_member(member_id),
  CONSTRAINT fk_bk_space       FOREIGN KEY (space_id)  REFERENCES study_space(space_id),
  CONSTRAINT fk_bk_slot        FOREIGN KEY (slot_id)   REFERENCES time_slot(slot_id),
  CONSTRAINT ck_bk_status      CHECK (booking_status IN ('Confirmed','Cancelled','Completed','No-Show'))
);

-- DOUBLE-BOOKING RULE (enforced by the database itself):
-- a (space, slot) pair may appear only once among NON-cancelled bookings.
-- The CASE returns NULL for cancelled rows, and Oracle ignores all-NULL keys in unique indexes.
CREATE UNIQUE INDEX uq_active_space_slot ON booking (
  CASE WHEN booking_status <> 'Cancelled' THEN space_id END,
  CASE WHEN booking_status <> 'Cancelled' THEN slot_id  END
);

CREATE INDEX ix_booking_member ON booking(member_id);
CREATE INDEX ix_booking_slot   ON booking(slot_id);

-- ---------- 5. CHECK_IN ----------
CREATE TABLE check_in (
  checkin_id      NUMBER,
  booking_id      NUMBER    NOT NULL,
  checkin_time    TIMESTAMP NOT NULL,
  checkout_time   TIMESTAMP,
  checkin_status  VARCHAR2(15) DEFAULT 'Checked In' NOT NULL,
  CONSTRAINT pk_checkin       PRIMARY KEY (checkin_id),
  CONSTRAINT uq_checkin_bk    UNIQUE (booking_id),               -- one check-in per booking
  CONSTRAINT fk_ci_booking    FOREIGN KEY (booking_id) REFERENCES booking(booking_id),
  CONSTRAINT ck_ci_status     CHECK (checkin_status IN ('Checked In','Checked Out')),
  CONSTRAINT ck_ci_times      CHECK (checkout_time IS NULL OR checkout_time >= checkin_time)
);

-- ---------- 6. PENALTY ----------
CREATE TABLE penalty (
  penalty_id    NUMBER,
  member_id     NUMBER        NOT NULL,
  booking_id    NUMBER        NOT NULL,
  reason        VARCHAR2(100) NOT NULL,
  penalty_date  DATE          DEFAULT SYSDATE NOT NULL,
  status        VARCHAR2(10)  DEFAULT 'Active' NOT NULL,
  CONSTRAINT pk_penalty       PRIMARY KEY (penalty_id),
  CONSTRAINT uq_penalty_bk    UNIQUE (booking_id),               -- one penalty per booking
  CONSTRAINT fk_pn_member     FOREIGN KEY (member_id)  REFERENCES campus_member(member_id),
  CONSTRAINT fk_pn_booking    FOREIGN KEY (booking_id) REFERENCES booking(booking_id),
  CONSTRAINT ck_pn_status     CHECK (status IN ('Active','Waived','Cleared'))
);

-- ---------- 7. FEEDBACK ----------
CREATE TABLE feedback (
  feedback_id    NUMBER,
  member_id      NUMBER NOT NULL,
  space_id       NUMBER NOT NULL,
  booking_id     NUMBER NOT NULL,
  rating         NUMBER(1) NOT NULL,
  comments       VARCHAR2(300),
  feedback_date  DATE DEFAULT SYSDATE NOT NULL,
  CONSTRAINT pk_feedback      PRIMARY KEY (feedback_id),
  CONSTRAINT uq_feedback_bk   UNIQUE (booking_id),               -- one feedback per booking
  CONSTRAINT fk_fb_member     FOREIGN KEY (member_id)  REFERENCES campus_member(member_id),
  CONSTRAINT fk_fb_space      FOREIGN KEY (space_id)   REFERENCES study_space(space_id),
  CONSTRAINT fk_fb_booking    FOREIGN KEY (booking_id) REFERENCES booking(booking_id),
  CONSTRAINT ck_fb_rating     CHECK (rating BETWEEN 1 AND 5)
);

-- ---------- Auto-numbering: sequence + BEFORE INSERT trigger per table ----------
-- (replaces identity columns, which need Oracle 12c+)

CREATE SEQUENCE seq_member START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_space START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_slot START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_booking START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_checkin START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_penalty START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_feedback START WITH 1 INCREMENT BY 1 NOCACHE;

CREATE OR REPLACE TRIGGER trg_member_id
BEFORE INSERT ON campus_member
FOR EACH ROW
BEGIN
  IF :NEW.member_id IS NULL THEN
    SELECT seq_member.NEXTVAL INTO :NEW.member_id FROM dual;
  END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_space_id
BEFORE INSERT ON study_space
FOR EACH ROW
BEGIN
  IF :NEW.space_id IS NULL THEN
    SELECT seq_space.NEXTVAL INTO :NEW.space_id FROM dual;
  END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_slot_id
BEFORE INSERT ON time_slot
FOR EACH ROW
BEGIN
  IF :NEW.slot_id IS NULL THEN
    SELECT seq_slot.NEXTVAL INTO :NEW.slot_id FROM dual;
  END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_booking_id
BEFORE INSERT ON booking
FOR EACH ROW
BEGIN
  IF :NEW.booking_id IS NULL THEN
    SELECT seq_booking.NEXTVAL INTO :NEW.booking_id FROM dual;
  END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_checkin_id
BEFORE INSERT ON check_in
FOR EACH ROW
BEGIN
  IF :NEW.checkin_id IS NULL THEN
    SELECT seq_checkin.NEXTVAL INTO :NEW.checkin_id FROM dual;
  END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_penalty_id
BEFORE INSERT ON penalty
FOR EACH ROW
BEGIN
  IF :NEW.penalty_id IS NULL THEN
    SELECT seq_penalty.NEXTVAL INTO :NEW.penalty_id FROM dual;
  END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_feedback_id
BEFORE INSERT ON feedback
FOR EACH ROW
BEGIN
  IF :NEW.feedback_id IS NULL THEN
    SELECT seq_feedback.NEXTVAL INTO :NEW.feedback_id FROM dual;
  END IF;
END;
/

-- ---------- Verify ----------
SELECT table_name FROM user_tables ORDER BY table_name;
SELECT table_name, constraint_name, constraint_type
FROM   user_constraints
WHERE  table_name IN ('CAMPUS_MEMBER','STUDY_SPACE','TIME_SLOT','BOOKING','CHECK_IN','PENALTY','FEEDBACK')
  AND  constraint_type IN ('P','R','U','C')
  AND  constraint_name NOT LIKE 'SYS_C%'
ORDER BY table_name, constraint_type;
