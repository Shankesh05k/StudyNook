# ---------------------------------------------------------------
# StudyNook web app - settings. Edit the values below.
# ---------------------------------------------------------------
import os

DB_USER = os.environ.get("STUDYNOOK_DB_USER", "Shankesh")
DB_PASSWORD = os.environ.get("STUDYNOOK_DB_PASSWORD", "user123")
DB_DSN = os.environ.get("STUDYNOOK_DB_DSN", "localhost:1521/XE")   # host:port/service_name

# Your Oracle 11g XE is too old for the driver's default "thin" mode, so the app
# uses Oracle's own client libraries ("thick" mode). Point this at the folder that
# contains oci.dll. Default XE 11.2 location shown here.
ORACLE_CLIENT_DIR = os.environ.get(
    "STUDYNOOK_CLIENT_DIR",
    r"C:\oraclexe\app\oracle\product\11.2.0\server\bin",
)

SECRET_KEY = "ADMINSP"
ADMIN_PASSWORD = os.environ.get("STUDYNOOK_ADMIN_PASSWORD", "admin123")

