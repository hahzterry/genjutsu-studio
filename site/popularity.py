"""Write site/popularity.json: paid, completed videos per trend in the last 30 days (counts only, no
personal data). Run before `python3 site/build.py` when you want the gallery order refreshed.
Needs SUPABASE_ACCESS_TOKEN (source ~/.claude/.env). Test (mock) and refunded jobs, and the owner's test accounts (TEST_EMAILS), don't count."""
import json, os, pathlib, urllib.request

REF = "tbljgxkbocunzoqvkoeu"
SQL = """select trend, count(*)::int n from jobs
         where status = 'completed' and not mock and not refunded and created_at > now() - interval '30 days'
           and user_id not in (select id from auth.users where lower(email) = any(%s))
         group by trend"""
tests = [e.strip().lower() for e in os.environ.get("TEST_EMAILS", "shoamtal@gmail.com").split(",") if e.strip()]
SQL = SQL % ("array[" + ",".join("'" + e.replace("'", "''") + "'" for e in tests) + "]::text[]")
req = urllib.request.Request(f"https://api.supabase.com/v1/projects/{REF}/database/query", method="POST",
                             data=json.dumps({"query": SQL}).encode(),
                             headers={"Authorization": f"Bearer {os.environ['SUPABASE_ACCESS_TOKEN']}",
                                      "Content-Type": "application/json", "User-Agent": "genjutsu-build"})
rows = json.load(urllib.request.urlopen(req, timeout=60))
if not isinstance(rows, list): raise SystemExit(f"query failed: {str(rows)[:200]}")
# Only real trends: jobs.trend is client-sent, so drop anything not in trends.json (+ custom, old aliases).
known = {t["slug"] for t in json.loads(pathlib.Path(__file__).with_name("trends.json").read_text())["trends"]} | {"custom", "hotel-lobby-v2"}
out = {r["trend"]: r["n"] for r in rows if r.get("trend") in known}
path = pathlib.Path(__file__).with_name("popularity.json")
path.write_text(json.dumps(dict(sorted(out.items())), indent=1) + "\n")
print(f"wrote {path.name}: {out}")
