#!/usr/bin/env python3
"""Make the staged production traces describe ONE agent, the same one live Hermes reports.

  sanitize_traces.py VERSION FOLDER NAME MODEL           rewrite the traces in place
  sanitize_traces.py VERSION FOLDER NAME MODEL --check   verify only; exit 1 if any trace differs

What it changes (idempotent; everything else in the files is left alone):
  * agent.name, agent.version and agent.model_name are set to NAME, VERSION and MODEL,
    and the model that recorded the traces is replaced by MODEL in every step.
  * the per-trace case identifier (extra.logical_case_id) is removed.

Timestamps are shifted later, at replay time (replay_traces.py), not here.
"""
import glob
import json
import sys

RECORDED_MODEL = "nvidia/nvidia/nemotron-3-ultra"   # the model name the example's traces recorded
DROP_FROM_EXTRA = ("logical_case_id",)


def trace_files(folder):
    return sorted(glob.glob(folder + "/*.atif.json"))


def rewrite(folder, version, name, model):
    for path in trace_files(folder):
        with open(path, encoding="utf-8") as fh:
            raw = fh.read()
        data = json.loads(raw.replace(RECORDED_MODEL, model))
        agent = data.setdefault("agent", {})
        agent["name"], agent["version"], agent["model_name"] = name, version, model
        for key in DROP_FROM_EXTRA:
            data.get("extra", {}).pop(key, None)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False, indent=2)
            fh.write("\n")


def check(folder, version, name, model):
    problems = 0
    for path in trace_files(folder):
        with open(path, encoding="utf-8") as fh:
            raw = fh.read()
        data = json.loads(raw)
        agent = data.get("agent", {})
        want = {"name": name, "version": version, "model_name": model}
        ok = (
            all(agent.get(k) == v for k, v in want.items())
            and RECORDED_MODEL not in raw
            and not any(k in data.get("extra", {}) for k in DROP_FROM_EXTRA)
        )
        if not ok:
            problems += 1
            print("not sanitized:", path)
    return problems


def main(argv):
    flags = [a for a in argv if a.startswith("--")]
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 4:
        print(__doc__)
        return 2
    version, folder, name, model = args
    if "--check" in flags:
        return 1 if check(folder, version, name, model) else 0
    rewrite(folder, version, name, model)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
