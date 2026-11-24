# Step 6: Hermes Agent (the agent under test) + NeMo Relay. Sourced by setup.sh.
# Pinned by commit; dependencies come from Hermes' own lockfile (nemo-relay comes with it).
# shellcheck shell=bash

if [[ -d "$HERMES_DIR/.git" && "$(git -C "$HERMES_DIR" rev-parse HEAD 2>/dev/null)" == "$HERMES_COMMIT" ]]; then
  info "Hermes source already at $HERMES_REF (${HERMES_COMMIT:0:7})"
else
  info "Fetching Hermes Agent $HERMES_REF (${HERMES_COMMIT:0:7})..."
  rm -rf "$HERMES_DIR"
  as_user git init --quiet "$HERMES_DIR"
  as_user git -C "$HERMES_DIR" remote add origin "$HERMES_REPO"
  retry 3 10 "fetch hermes" as_user git -C "$HERMES_DIR" fetch --depth 1 origin "$HERMES_COMMIT"
  as_user git -C "$HERMES_DIR" checkout --quiet --detach FETCH_HEAD
fi
[[ "$(git -C "$HERMES_DIR" rev-parse HEAD)" == "$HERMES_COMMIT" ]] || fail "Hermes checkout is not at pinned commit"

info "Installing Hermes dependencies (uv sync --frozen)..."
# Pilot 2026-11-20: `--locked` fails on the pinned Hermes commit under uv 0.12.9 ("lockfile needs to be
# updated", after an exclude-newer change for google-cloud-pubsub). `--frozen` installs exactly what
# uv.lock records without re-validating it, so versions stay pinned and nothing is re-resolved.
retry 3 15 "uv sync hermes" as_user env \
  UV_MANAGED_PYTHON=1 UV_PROJECT_ENVIRONMENT="$HERMES_DIR/.venv" \
  uv sync --project "$HERMES_DIR" --frozen --no-dev --python "$HERMES_PYTHON"
[[ -x "$HERMES_PY" ]] || fail "Hermes venv was not created"

read -r got_hermes got_relay < <("$HERMES_PY" - <<'PY'
from importlib.metadata import version
from hermes_cli import __version__
print(__version__, version("nemo-relay"))
PY
)
[[ "$got_hermes" == "$HERMES_VERSION" ]] || fail "Expected Hermes $HERMES_VERSION, found $got_hermes"
[[ "$got_relay" == "$NEMO_RELAY_VERSION" ]] || fail "Expected nemo-relay $NEMO_RELAY_VERSION, found $got_relay"
info "Hermes $got_hermes with nemo-relay $got_relay"

# Hermes config (points at the local model) and the NeMo Relay config (built in to Hermes;
# exports ATIF trajectories to disk and live OTLP to Helix Intake). Both are templates in configs/.
as_user mkdir -p "$HERMES_HOME_DIR" "$RELAY_OUT_DIR/atif"
render "$REPO_ROOT/configs/hermes-config.yaml.tmpl" "$HERMES_HOME_DIR/config.yaml"
render "$REPO_ROOT/configs/relay-plugins.toml.tmpl" "$HERMES_HOME_DIR/plugins.toml"

# `hermes` wrapper: always selects the Relay config and sets the local key, in any shell.
render "$REPO_ROOT/configs/hermes-wrapper.sh.tmpl" "$BIN_DIR/hermes"
chmod 755 "$BIN_DIR/hermes"
chown -R "$TARGET_USER":"$TARGET_USER" "$HERMES_HOME_DIR" "$RELAY_OUT_DIR" "$BIN_DIR/hermes"
info "Hermes configured (config: $HERMES_HOME_DIR, source: $HERMES_DIR, trajectories: $RELAY_OUT_DIR/atif)"
