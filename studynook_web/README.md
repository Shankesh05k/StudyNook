# StudyNook web app (Flask + Oracle 11g XE)

Every button calls a stored procedure from 05_procedures.sql. The database enforces the rules.

## One-time setup (Windows)

1. Make sure 01_ddl.sql, 02_dml.sql and 05_procedures.sql have been run in your Oracle schema.
2. Check that Python is 64-bit (Oracle XE 11g is 64-bit, and the two must match):
       python -c "import struct; print(struct.calcsize('P')*8)"
   It should print 64.
3. Open a terminal in this folder and create the environment:
       python -m venv venv
       venv\Scripts\activate
       pip install -r requirements.txt
4. Open config.py and set DB_PASSWORD to your Oracle password.
   Also check ORACLE_CLIENT_DIR. This must be the folder that contains oci.dll:
       dir C:\oraclexe\app\oracle\product\11.2.0\server\bin\oci.dll
   If that file is not found, search for it: dir C:\oraclexe\oci.dll /s
5. Start the site:
       python app.py
   Open http://127.0.0.1:5000

Member sign-in: type a campus email from the members table (for example aarav.mehta@vit.ac.in),
or press one of the demo accounts on the sign-in screen.

Admin page extras (need 07_cursor_triggers.sql run in Oracle first): the no-show sweep button,
the space status control and the booking status log.

Admin reports: http://127.0.0.1:5000/admin/login  (password in config.py, default admin123)

## Simulated time

Sample bookings are on 12 and 13 Oct 2026 and check-in opens 15 minutes before a slot.
Use "Simulated time" at the bottom of any member page to set a time inside the slot, for example
2026-10-12 09:05, then press Check in on that booking.

## Troubleshooting

- DPI-1047 "Cannot locate a 64-bit Oracle Client library": ORACLE_CLIENT_DIR is wrong, or Python is 32-bit.
- DPY-3010 "connections to this database server version are not supported": thick mode is not active;
  keep ORACLE_CLIENT_DIR set.
- ORA-12514 / ORA-12505: wrong service name. In config.py use localhost:1521/XE. Run `lsnrctl status` to see the name.
- ORA-01017: wrong username or password.
- If oci.dll is missing from your XE folder: install Oracle Instant Client 19c Basic (64-bit),
  unzip it, and point ORACLE_CLIENT_DIR at the unzipped folder.
- The pinned driver version (oracledb 3.1.1) is deliberate: newer releases dropped support for 11.2 client libraries.
