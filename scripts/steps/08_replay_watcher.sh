# Step 8: arm the replay watcher. Sourced by setup.sh.
#
# Intake does not exist at setup time (participants install Helix themselves), so the traces
# cannot be loaded now. Instead a watcher is armed: it polls Intake's health endpoint and loads
# the traces once, automatically, the first time Intake is healthy.
# Healthy = GET .../spans?page=1&page_size=1 returns 200 (503 means ClickHouse is unreachable).
# shellcheck shell=bash

install -m 755 -o "$TARGET_USER" -g "$TARGET_USER" "$REPO_ROOT/scripts/replay_traces.py" "$STUDY_DIR/replay-traces.py"
install -m 755 -o "$TARGET_USER" -g "$TARGET_USER" "$REPO_ROOT/scripts/replay_traces.sh" "$STUDY_DIR/replay-traces.sh"

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
  # systemd: survives reboots until the replay has completed once.
  render "$REPO_ROOT/configs/spindrift-replay.service.tmpl" /tmp/spindrift-replay.service
  sudo install -m 644 /tmp/spindrift-replay.service /etc/systemd/system/spindrift-replay.service
  rm -f /tmp/spindrift-replay.service
  sudo systemctl daemon-reload
  sudo systemctl enable --now spindrift-replay.service
  info "Replay watcher armed (systemd: spindrift-replay). Traces ingest automatically once Intake is healthy."
else
  warn "No systemd: starting the replay watcher with nohup (will not survive a reboot)"
  as_user env "WORKSPACE=${INTAKE_WORKSPACE}" nohup python3 -I "$STUDY_DIR/replay-traces.py" --wait \
    >"$STUDY_DIR/replay-watcher.log" 2>&1 &
fi
