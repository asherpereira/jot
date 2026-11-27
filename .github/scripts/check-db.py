import sqlite3
import sys
import time
from pathlib import Path

root = Path(sys.argv[1])
for attempt in range(30):
    for db in root.rglob("jot.sqlite"):
        with sqlite3.connect(f"{db.resolve().as_uri()}?mode=ro", uri=True) as connection:
            tables = {r[0] for r in connection.execute("select name from sqlite_master where type='table'")}
        if {"homework", "watch_receipt"} <= tables:
            print(f"Jot opened its SQLite database at {db}")
            sys.exit(0)
    time.sleep(1)
raise SystemExit("No Jot database with the expected schema appeared")
