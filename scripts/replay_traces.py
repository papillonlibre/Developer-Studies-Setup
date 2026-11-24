#!/usr/bin/env python3
"""Replay the staged production ATIF traces into NeMo Helix Intake (v0.6 /ingest/atif).

  replay-traces.py            replay now (fails fast if Intake is not healthy)
  replay-traces.py --wait     block until Intake is healthy, then replay (what the watcher runs)

Installed to ~/study/replay-traces.py by setup. Fixed-seed shuffle (same order for every
participant, no grouping in ingest order). Step timestamps are shifted so the traces sit in the
last ~hour, in shuffled order: the originals are older than Studio's 30-day default lookback
and would be invisible. REPLAY_SHIFT_TIMESTAMPS=0 disables the shift. State lives in
<study>/.replay-state.json; once all traces are ingested <study>/.replayed is written and
re-runs are no-ops.
"""
import datetime, glob, json, os, random, re, sys, time, urllib.error, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.environ.get("NMP_BASE_URL", "http://127.0.0.1:8080").rstrip("/")
WS = os.environ.get("WORKSPACE", "default")
SHIFT = os.environ.get("REPLAY_SHIFT_TIMESTAMPS", "1") == "1"
TOKEN = os.environ.get("NMP_ACCESS_TOKEN", "")
STATE = os.path.join(HERE, ".replay-state.json")
DONE = os.path.join(HERE, ".replayed")
GAP = 60  # seconds between trace start times
HEALTH = f"{BASE}/apis/intake/v2/workspaces/{WS}/spans?page=1&page_size=1"
INGEST = f"{BASE}/apis/intake/v2/workspaces/{WS}/ingest/atif"
TS = re.compile(r"^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(\.\d+)?(.*)$")
FMT = "%Y-%m-%dT%H:%M:%S"


def req(url, data=None):
    r = urllib.request.Request(url, data=data, method="POST" if data is not None else "GET")
    if data is not None:
        r.add_header("Content-Type", "application/json")
    if TOKEN:
        r.add_header("Authorization", "Bearer " + TOKEN)
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            return resp.status, resp.read(300).decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read(300).decode("utf-8", "replace")
    except Exception as e:  # connection refused etc.
        return 0, str(e)


def healthy():
    # Healthy = 200. 503 means Intake is up but cannot reach ClickHouse.
    return req(HEALTH)[0] == 200


def shift_trace(d, start_new):
    """Rebase this trace's step timestamps so its first step starts at start_new (UTC)."""
    stamps = [s.get("timestamp") for s in d.get("steps", []) if s.get("timestamp")]
    if not stamps:
        return
    first = min(datetime.datetime.strptime(TS.match(t).group(1), FMT) for t in stamps)
    delta = start_new - first
    for s in d["steps"]:
        t = s.get("timestamp")
        m = TS.match(t) if t else None
        if m:
            base = datetime.datetime.strptime(m.group(1), FMT) + delta
            s["timestamp"] = base.strftime(FMT) + (m.group(2) or "") + m.group(3)


def main():
    if os.path.exists(DONE):
        print("Already replayed (" + DONE + ")")
        return 0
    if "--wait" in sys.argv:
        while not healthy():
            time.sleep(10)
    elif not healthy():
        print("Intake is not healthy yet: GET " + HEALTH + " did not return 200")
        return 2
    files = sorted(glob.glob(os.path.join(HERE, "traces", "*.atif.json")))
    random.Random(20260617).shuffle(files)
    state = {}
    if os.path.exists(STATE):
        with open(STATE) as fh:
            state = json.load(fh)
    now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None, microsecond=0)
    state.setdefault("window_start", (now - datetime.timedelta(minutes=5, seconds=GAP * len(files))).strftime(FMT))
    state.setdefault("done", [])
    w0 = datetime.datetime.strptime(state["window_start"], FMT)
    ok = bad = 0
    for i, f in enumerate(files):
        name = os.path.basename(f)
        if name in state["done"]:
            ok += 1
            continue
        with open(f, encoding="utf-8") as fh:
            d = json.load(fh)
        if SHIFT:
            shift_trace(d, w0 + datetime.timedelta(seconds=GAP * i))
        code, body = req(INGEST, json.dumps(d).encode("utf-8"))
        if code == 201:
            ok += 1
            state["done"].append(name)
        else:
            bad += 1
            print(f"FAIL {code} {name}: {body}")
        with open(STATE, "w") as fh:
            json.dump(state, fh)
    print(f"Ingested: {ok}  Failed: {bad}  -> {INGEST}")
    if bad == 0:
        open(DONE, "w").write(datetime.datetime.now(datetime.timezone.utc).isoformat() + "\n")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
