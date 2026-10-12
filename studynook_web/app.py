"""StudyNook - campus study-space booking. Every action calls a stored procedure
in Oracle; the database enforces the rules and this app just shows the result."""
import datetime
import functools

import oracledb
from flask import Flask, flash, redirect, render_template, request, session, url_for

import config
import db

app = Flask(__name__)
app.secret_key = config.SECRET_KEY


# ---------------------------------------------------------------- helpers
def member_required(view):
    @functools.wraps(view)
    def wrapped(*args, **kwargs):
        if "member_id" not in session:
            return redirect(url_for("login"))
        return view(*args, **kwargs)
    return wrapped


def admin_required(view):
    @functools.wraps(view)
    def wrapped(*args, **kwargs):
        if not session.get("admin"):
            return redirect(url_for("admin_login"))
        return view(*args, **kwargs)
    return wrapped


def sim_time():
    """Optional simulated time used for check-in/out, so a booking on a future date can be tested."""
    value = session.get("sim_time")
    if not value:
        return None
    return datetime.datetime.strptime(value, "%Y-%m-%dT%H:%M")


def run(action, success):
    try:
        result = action()
        flash(success, "ok")
        return result
    except db.UserError as exc:
        flash(str(exc), "error")
        return None


@app.context_processor
def inject_globals():
    return {
        "me": session.get("member_name"),
        "is_member": "member_id" in session,
        "is_admin": bool(session.get("admin")),
        "sim_time_value": session.get("sim_time", ""),
    }


@app.template_filter("initials")
def initials(name):
    words = [w for w in (name or "").replace(".", " ").split() if w.lower() != "dr"]
    if not words:
        return "?"
    if len(words) == 1:
        return words[0][:2].upper()
    return (words[0][0] + words[-1][0]).upper()


@app.template_filter("first_name")
def first_name(name):
    parts = (name or "").split()
    if len(parts) > 1 and parts[0].lower().startswith("dr"):
        return " ".join(parts[:2])
    return parts[0] if parts else ""


@app.errorhandler(oracledb.Error)
def database_down(exc):
    return render_template("error.html", detail=str(exc)), 500


# ---------------------------------------------------------------- sign in / out
@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        member_id = request.form.get("member_id", type=int)
        email = request.form.get("email", "").strip().lower()
        if member_id:
            rows = db.query("SELECT member_id, name FROM campus_member WHERE member_id = :mid", mid=member_id)
        elif email:
            rows = db.query("SELECT member_id, name FROM campus_member WHERE LOWER(email) = :em", em=email)
        else:
            rows = []
        if rows:
            session.clear()
            session["member_id"] = int(rows[0]["member_id"])
            session["member_name"] = rows[0]["name"]
            return redirect(url_for("dashboard"))
        flash("No campus member has that email address. Check the spelling or pick a demo account.", "error")
    members = db.query("SELECT member_id, name, member_type, department FROM campus_member ORDER BY name")
    facts = db.query(
        """SELECT (SELECT COUNT(*) FROM study_space WHERE status = 'Available')           AS spaces,
                  (SELECT COUNT(*) FROM campus_member)                                    AS members,
                  (SELECT COUNT(*) FROM booking WHERE booking_status <> 'Cancelled')      AS bookings
           FROM dual""")[0]
    return render_template("login.html", members=members, facts=facts)


@app.route("/logout", methods=["POST"])
def logout():
    session.clear()
    return redirect(url_for("login"))


# ---------------------------------------------------------------- member pages
@app.route("/")
@member_required
def dashboard():
    mid = session["member_id"]
    try:
        db.call("sp_expire_penalties", [None], n_out=1)   # penalties older than 14 days expire
    except db.UserError:
        pass   # 05_procedures.sql has not been re-run yet
    stats = db.query(
        "SELECT fn_attendance_rate(:mid) AS attendance, fn_active_penalties(:mid) AS active_penalties FROM dual",
        mid=mid)[0]
    upcoming = db.query(
        """SELECT b.booking_id, s.space_name, s.location,
                  TO_CHAR(t.slot_date, 'DD Mon YYYY') AS date_label,
                  TO_CHAR(t.slot_date, 'DD') AS day_num, TO_CHAR(t.slot_date, 'Mon') AS mon,
                  TO_CHAR(t.slot_date, 'Dy') AS dow, t.start_time, t.end_time
           FROM   booking b
           JOIN   study_space s ON s.space_id = b.space_id
           JOIN   time_slot   t ON t.slot_id  = b.slot_id
           WHERE  b.member_id = :mid AND b.booking_status = 'Confirmed'
           ORDER  BY t.slot_date, t.start_time""", mid=mid)
    penalties = db.query(
        """SELECT p.penalty_id, p.reason, p.status, TO_CHAR(p.penalty_date, 'DD Mon YYYY') AS date_label,
                  s.space_name
           FROM   penalty p
           JOIN   booking b     ON b.booking_id = p.booking_id
           JOIN   study_space s ON s.space_id   = b.space_id
           WHERE  p.member_id = :mid
           ORDER  BY p.penalty_date DESC, p.penalty_id DESC""", mid=mid)
    return render_template("dashboard.html", stats=stats, upcoming=upcoming, penalties=penalties)


@app.route("/book")
@member_required
def book():
    mid = session["member_id"]
    date_rows = db.query(
        "SELECT DISTINCT TO_CHAR(slot_date, 'YYYY-MM-DD') AS d FROM time_slot "
        "WHERE slot_date >= TRUNC(SYSDATE) ORDER BY 1")
    dates = []
    for row in date_rows:
        parsed = datetime.datetime.strptime(row["d"], "%Y-%m-%d")
        dates.append((row["d"], parsed.strftime("%a"), parsed.strftime("%d %b")))
    if not dates:
        return render_template("book.html", dates=[], selected=None, slots=[], grid=[], free_count=0)

    selected = request.args.get("date")
    if selected not in [d[0] for d in dates]:
        selected = dates[0][0]

    now = db.query("SELECT SYSDATE AS now FROM dual")[0]["now"]
    slots = db.query(
        "SELECT slot_id, start_time, end_time, fn_slot_start(slot_id) AS start_dt "
        "FROM time_slot WHERE slot_date = TO_DATE(:dt, 'YYYY-MM-DD') ORDER BY start_time", dt=selected)
    spaces = db.query(
        "SELECT space_id, space_name, location, capacity, space_type, status "
        "FROM study_space ORDER BY space_type, space_name")
    booked_rows = db.query(
        """SELECT b.space_id, b.slot_id, b.member_id
           FROM   booking b JOIN time_slot t ON t.slot_id = b.slot_id
           WHERE  t.slot_date = TO_DATE(:dt, 'YYYY-MM-DD') AND b.booking_status <> 'Cancelled'""", dt=selected)
    booked = {(int(r["space_id"]), int(r["slot_id"])): int(r["member_id"]) for r in booked_rows}

    grid = []
    for sp in spaces:
        cells = []
        for sl in slots:
            key = (int(sp["space_id"]), int(sl["slot_id"]))
            if key in booked:
                state = "mine" if booked[key] == mid else "taken"
            elif sp["status"] != "Available":
                state = "closed"
            elif sl["start_dt"] <= now:
                state = "past"
            else:
                state = "free"
            cells.append({"slot": sl, "state": state})
        grid.append({"space": sp, "cells": cells})
    free_count = sum(1 for row in grid for c in row["cells"] if c["state"] == "free")
    return render_template("book.html", dates=dates, selected=selected, slots=slots, grid=grid,
                           free_count=free_count)


@app.route("/book", methods=["POST"])
@member_required
def book_post():
    space_id = request.form.get("space_id", type=int)
    slot_id = request.form.get("slot_id", type=int)
    day = request.form.get("date", "")
    booking_id = run(lambda: db.call("sp_book_space", [session["member_id"], space_id, slot_id], out_number=True),
                     "Booked. Your booking number is shown in My bookings.")
    return redirect(url_for("book", date=day))


@app.route("/bookings")
@member_required
def bookings():
    rows = db.query(
        """SELECT b.booking_id, b.booking_status, s.space_name, s.location,
                  TO_CHAR(t.slot_date, 'DD Mon YYYY') AS date_label,
                  TO_CHAR(t.slot_date, 'DD') AS day_num, TO_CHAR(t.slot_date, 'Mon') AS mon,
                  TO_CHAR(t.slot_date, 'Dy') AS dow, t.start_time, t.end_time,
                  c.checkin_id, c.checkout_time,
                  TO_CHAR(c.checkin_time, 'HH24:MI')  AS in_time,
                  TO_CHAR(c.checkout_time, 'HH24:MI') AS out_time,
                  f.rating
           FROM   booking b
           JOIN   study_space s ON s.space_id = b.space_id
           JOIN   time_slot   t ON t.slot_id  = b.slot_id
           LEFT   JOIN check_in c ON c.booking_id = b.booking_id
           LEFT   JOIN feedback f ON f.booking_id = b.booking_id
           WHERE  b.member_id = :mid
           ORDER  BY t.slot_date DESC, t.start_time DESC, b.booking_id DESC""", mid=session["member_id"])
    return render_template("bookings.html", rows=rows)


@app.route("/cancel", methods=["POST"])
@member_required
def cancel():
    booking_id = request.form.get("booking_id", type=int)
    run(lambda: db.call("sp_cancel_booking", [booking_id, session["member_id"]]), "Booking cancelled.")
    return redirect(url_for("bookings"))


@app.route("/checkin", methods=["POST"])
@member_required
def checkin():
    booking_id = request.form.get("booking_id", type=int)
    run(lambda: db.call("sp_check_in", [booking_id, sim_time()]), "Checked in. Enjoy your session.")
    return redirect(url_for("bookings"))


@app.route("/checkout", methods=["POST"])
@member_required
def checkout():
    booking_id = request.form.get("booking_id", type=int)
    run(lambda: db.call("sp_check_out", [booking_id, sim_time()]), "Checked out. You can now leave a review.")
    return redirect(url_for("bookings"))


@app.route("/feedback", methods=["POST"])
@member_required
def feedback():
    booking_id = request.form.get("booking_id", type=int)
    rating = request.form.get("rating", type=int)
    comments = request.form.get("comments", "").strip()[:300] or None
    run(lambda: db.call("sp_submit_feedback", [session["member_id"], booking_id, rating, comments]),
        "Thanks, your review is saved.")
    return redirect(url_for("bookings"))


@app.route("/demo-clock", methods=["POST"])
@member_required
def demo_clock():
    value = request.form.get("sim_time", "").strip()
    if request.form.get("action") == "clear" or not value:
        session.pop("sim_time", None)
        flash("Simulated time cleared. Check-in and check-out use the real time.", "ok")
    else:
        try:
            datetime.datetime.strptime(value, "%Y-%m-%dT%H:%M")
            session["sim_time"] = value
            flash("Simulated time applied. Check-in and check-out will use that time.", "ok")
        except ValueError:
            flash("That date and time was not understood.", "error")
    return redirect(request.referrer or url_for("bookings"))


@app.route("/spaces")
@member_required
def spaces():
    rows = db.query(
        """SELECT s.space_id, s.space_name, s.location, s.capacity, s.space_type, s.status,
                  fn_avg_rating(s.space_id) AS avg_rating,
                  (SELECT COUNT(*) FROM feedback f WHERE f.space_id = s.space_id) AS reviews
           FROM   study_space s
           ORDER  BY s.space_type, s.space_name""")
    latest = db.query(
        """SELECT * FROM (
             SELECT s.space_name, f.rating, f.comments, m.name,
                    TO_CHAR(f.feedback_date, 'DD Mon YYYY') AS date_label
             FROM   feedback f
             JOIN   study_space s   ON s.space_id  = f.space_id
             JOIN   campus_member m ON m.member_id = f.member_id
             WHERE  f.comments IS NOT NULL
             ORDER  BY f.feedback_date DESC, f.feedback_id DESC)
           WHERE ROWNUM <= 8""")
    return render_template("spaces.html", rows=rows, latest=latest)


# ---------------------------------------------------------------- administrator
@app.route("/admin/login", methods=["GET", "POST"])
def admin_login():
    if request.method == "POST":
        if request.form.get("password") == config.ADMIN_PASSWORD:
            session.clear()
            session["admin"] = True
            return redirect(url_for("admin"))
        flash("Wrong administrator password.", "error")
    return render_template("admin_login.html")


@app.route("/admin")
@admin_required
def admin():
    totals = db.query(
        """SELECT (SELECT COUNT(*) FROM booking)                                    AS bookings,
                  (SELECT COUNT(*) FROM booking WHERE booking_status = 'No-Show')  AS no_shows,
                  (SELECT COUNT(*) FROM penalty WHERE status = 'Active')           AS active_penalties,
                  (SELECT ROUND(AVG(rating), 2) FROM feedback)                     AS avg_rating
           FROM dual""")[0]
    utilization = db.query(
        """SELECT s.space_name, s.status,
                  COUNT(b.booking_id) AS total_bookings,
                  SUM(CASE WHEN b.booking_status = 'Completed' THEN 1 ELSE 0 END) AS attended,
                  SUM(CASE WHEN b.booking_status = 'No-Show'   THEN 1 ELSE 0 END) AS no_shows,
                  ROUND(100 * SUM(CASE WHEN b.booking_status = 'Completed' THEN 1 ELSE 0 END)
                        / NULLIF(SUM(CASE WHEN b.booking_status IN ('Completed','No-Show') THEN 1 ELSE 0 END), 0), 1)
                        AS attendance_pct
           FROM   study_space s
           LEFT   JOIN booking b ON b.space_id = s.space_id
           GROUP  BY s.space_name, s.status
           ORDER  BY attendance_pct, s.space_name""")
    offenders = db.query(
        """SELECT m.name, m.member_type, COUNT(b.booking_id) AS no_shows, COUNT(p.penalty_id) AS penalties,
                  fn_active_penalties(m.member_id) AS active_penalties
           FROM   campus_member m
           JOIN   booking b ON b.member_id = m.member_id AND b.booking_status = 'No-Show'
           LEFT   JOIN penalty p ON p.booking_id = b.booking_id
           GROUP  BY m.member_id, m.name, m.member_type
           ORDER  BY no_shows DESC, m.name""")
    slots = db.query(
        """SELECT t.start_time || '-' || t.end_time AS slot, COUNT(b.booking_id) AS bookings
           FROM   time_slot t
           JOIN   booking b ON b.slot_id = t.slot_id AND b.booking_status <> 'Cancelled'
           GROUP  BY t.start_time, t.end_time
           ORDER  BY bookings DESC, slot""")
    recent = db.query(
        """SELECT * FROM (
             SELECT b.booking_id, m.name, s.space_name, b.booking_status,
                    TO_CHAR(t.slot_date, 'DD Mon YYYY') AS date_label, t.start_time, t.end_time
             FROM   booking b
             JOIN   campus_member m ON m.member_id = b.member_id
             JOIN   study_space   s ON s.space_id  = b.space_id
             JOIN   time_slot     t ON t.slot_id   = b.slot_id
             ORDER  BY t.slot_date DESC, t.start_time DESC, b.booking_id DESC)
           WHERE ROWNUM <= 15""")
    all_spaces = db.query("SELECT space_id, space_name, location, status FROM study_space ORDER BY space_name")
    try:
        audit = db.query(
            """SELECT * FROM (
                 SELECT a.booking_id, a.old_status, a.new_status, a.changed_by,
                        TO_CHAR(a.changed_at, 'DD Mon HH24:MI:SS') AS when_label
                 FROM   booking_audit a ORDER BY a.audit_id DESC)
               WHERE ROWNUM <= 10""")
    except oracledb.DatabaseError:
        audit = None   # 07_cursor_triggers.sql has not been run yet
    return render_template("admin.html", totals=totals, utilization=utilization,
                           offenders=offenders, slots=slots, recent=recent,
                           all_spaces=all_spaces, audit=audit)


@app.route("/admin/sweep", methods=["POST"])
@admin_required
def admin_sweep():
    as_of = None
    raw = request.form.get("as_of", "").strip()
    if raw:
        try:
            as_of = datetime.datetime.strptime(raw, "%Y-%m-%dT%H:%M")
        except ValueError:
            flash("That date and time was not understood.", "error")
            return redirect(url_for("admin"))
    try:
        marked, penalized = db.call("sp_mark_no_shows", [as_of], n_out=2)
        expired = db.call("sp_expire_penalties", [as_of], n_out=1)[0]
        flash("Sweep finished: {} booking{} marked No-Show, {} penalt{} issued and {} old penalt{} expired.".format(
            marked, "" if marked == 1 else "s", penalized, "y" if penalized == 1 else "ies",
            expired, "y" if expired == 1 else "ies"), "ok")
    except db.UserError as exc:
        flash(str(exc), "error")
    return redirect(url_for("admin"))


@app.route("/admin/space-status", methods=["POST"])
@admin_required
def admin_space_status():
    space_id = request.form.get("space_id", type=int)
    status = request.form.get("status", "")
    before = db.query("SELECT COUNT(*) AS n FROM booking WHERE space_id = :sid AND booking_status = 'Confirmed'",
                      sid=space_id)[0]["n"]
    try:
        db.execute("UPDATE study_space SET status = :st WHERE space_id = :sid", st=status, sid=space_id)
    except db.UserError as exc:
        flash(str(exc), "error")
        return redirect(url_for("admin"))
    after = db.query("SELECT COUNT(*) AS n FROM booking WHERE space_id = :sid AND booking_status = 'Confirmed'",
                     sid=space_id)[0]["n"]
    cancelled = int(before) - int(after)
    message = "Space status changed to {}.".format(status)
    if cancelled > 0:
        message += " The database cancelled {} future booking{} automatically.".format(cancelled, "" if cancelled == 1 else "s")
    flash(message, "ok")
    return redirect(url_for("admin"))


if __name__ == "__main__":
    app.run(debug=True)
