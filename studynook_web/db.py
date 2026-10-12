"""Thin database layer. All business rules live in Oracle (procedures, triggers,
constraints); this file only runs queries and calls stored procedures."""
import oracledb
import config

_pool = None


class UserError(Exception):
    """A rule violation raised by the database, with a message fit to show the user."""


def _init():
    global _pool
    if _pool is not None:
        return
    if config.ORACLE_CLIENT_DIR:
        oracledb.init_oracle_client(lib_dir=config.ORACLE_CLIENT_DIR)
    else:
        oracledb.init_oracle_client()
    _pool = oracledb.create_pool(
        user=config.DB_USER,
        password=config.DB_PASSWORD,
        dsn=config.DB_DSN,
        min=1, max=4, increment=1,
    )


def friendly_message(exc):
    """ORA-20xxx errors come from our own procedures and are written for users."""
    if isinstance(exc, oracledb.DatabaseError) and exc.args:
        err = exc.args[0]
        text = getattr(err, "message", str(err))
        first = text.strip().splitlines()[0] if text.strip() else str(err)
        code = getattr(err, "code", None)
        if code and 20000 <= code <= 20999:
            return first.split(": ", 1)[1] if ": " in first else first
        if code == 1:
            return "That record already exists."
        return "The database rejected that request (" + first[:140] + ")."
    return str(exc)


def query(sql, **params):
    """Run a SELECT and return a list of dicts with lower-case keys."""
    _init()
    with _pool.acquire() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            cols = [d[0].lower() for d in cur.description]
            return [dict(zip(cols, row)) for row in cur.fetchall()]


def call(name, args, out_number=False, n_out=0):
    """Call a stored procedure.
    out_number: the last parameter is one OUT NUMBER (e.g. the new booking id) -> returns that int.
    n_out: the last n parameters are OUT NUMBERs -> returns a list of ints."""
    _init()
    with _pool.acquire() as conn:
        with conn.cursor() as cur:
            try:
                if n_out:
                    outs = [cur.var(oracledb.NUMBER) for _ in range(n_out)]
                    cur.callproc(name, list(args) + outs)
                    return [int(o.getvalue()) for o in outs]
                if out_number:
                    out = cur.var(oracledb.NUMBER)
                    cur.callproc(name, list(args) + [out])
                    return int(out.getvalue())
                cur.callproc(name, list(args))
                return None
            except oracledb.DatabaseError as exc:
                conn.rollback()
                raise UserError(friendly_message(exc))


def execute(sql, **params):
    """Run one INSERT/UPDATE/DELETE and commit. Database triggers still fire."""
    _init()
    with _pool.acquire() as conn:
        with conn.cursor() as cur:
            try:
                cur.execute(sql, params)
                conn.commit()
            except oracledb.DatabaseError as exc:
                conn.rollback()
                raise UserError(friendly_message(exc))
