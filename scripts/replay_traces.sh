#!/usr/bin/env bash
# Manual re-run / facilitator override. The watcher normally does this automatically.
exec python3 -I "$(dirname "$0")/replay-traces.py" "$@"
