#!/usr/bin/env bash
# Shared settings and helpers. Sourced by scripts/setup.sh. Never run directly.
# shellcheck shell=bash

: "${REPO_ROOT:?REPO_ROOT must be set by the caller (scripts/setup.sh does this)}"

# ── Settings ─────────────────────────────────────────────────────────
# `set -a` exports everything defined below, so config templates can use it (see render()).
set -a
# shellcheck source=../../configs/versions.env
source "$REPO_ROOT/configs/versions.env"
# shellcheck source=../../configs/study.env
source "$REPO_ROOT/configs/study.env"

# The login user who will use the VM. Setup runs as root (via sudo), so find the real user.
TARGET_USER="${SUDO_USER:-$(id -un)}"
if [[ "$TARGET_USER" == "root" ]]; then
  # Launched as plain root (no sudo): use the first normal account, not /root.
  _alt_user="$(getent passwd | awk -F: '$3>=1000 && $3<60000 {print $1; exit}')"
  if [[ -n "$_alt_user" ]]; then TARGET_USER="$_alt_user"; fi
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

STUDY_DIR="${STUDY_DIR:-${TARGET_HOME}/study}"
MODEL_DIR="${MODEL_DIR:-${TARGET_HOME}/models/nemotron-bolt}"
HERMES_DIR="${HERMES_DIR:-${TARGET_HOME}/hermes-agent}"
AUT_DIR="${AUT_DIR:-${TARGET_HOME}/hermes-agent-under-test}"   # the agent under test (SOUL, MCP tools, fixture)
HERMES_HOME_DIR="${TARGET_HOME}/.hermes"
RELAY_OUT_DIR="${TARGET_HOME}/hermes-traces"
BIN_DIR="${TARGET_HOME}/.local/bin"
HERMES_PY="${HERMES_DIR}/.venv/bin/python"

DEBIAN_FRONTEND=noninteractive
NEEDRESTART_MODE=a
set +a

# Variables that config templates (configs/*.tmpl) may use. Add a name here when a template needs it.
RENDER_VARS='${REPO_ROOT} ${HERMES_PROVIDER} ${MODEL_ALIAS} ${LLAMA_PORT} ${RELAY_SCHEMA_VERSION} ${HERMES_AGENT_NAME}
${HERMES_AGENT_VERSION} ${RELAY_OUT_DIR} ${RELAY_OTLP_TYPE} ${INTAKE_OTLP_URL} ${INTAKE_WORKSPACE}
${HERMES_HOME_DIR} ${HERMES_PY} ${STUDY_DIR} ${TARGET_USER} ${EXPECTED_TRACE_COUNT} ${HELIX_PYTHON}
${AUT_DIR} ${HERMES_VERSION} ${NEMO_RELAY_VERSION} ${HELIX_DOCS_URL} ${HELIX_CODE_URL}'
RENDER_VARS="${RENDER_VARS//$'\n'/ }"

# ── Logging ──────────────────────────────────────────────────────────
_ts() { date '+%H:%M:%S'; }
info() { printf '\033[0;32m[%s spindrift]\033[0m %s\n' "$(_ts)" "$1"; }
warn() { printf '\033[1;33m[%s spindrift]\033[0m %s\n' "$(_ts)" "$1"; }
fail() { printf '\033[0;31m[%s spindrift]\033[0m %s\n' "$(_ts)" "$1"; exit 1; }

# ── Helpers ──────────────────────────────────────────────────────────
# Usage: retry 3 10 "description" command args...
retry() {
  local max="$1" sleep_sec="$2" desc="$3"; shift 3
  local n=1
  until "$@"; do
    if ((n >= max)); then warn "Failed after $max attempts: $desc"; return 1; fi
    info "Retry $n/$max for: $desc (sleeping ${sleep_sec}s)"
    sleep "$sleep_sec"; ((n++))
  done
}

# Brev VMs sometimes run unattended-upgrades at boot and hold the apt lock.
wait_for_apt_lock() {
  local waited=0
  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
     || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    ((waited >= 180)) && { warn "apt lock still held after 180s, proceeding"; return 0; }
    ((waited % 15 == 0)) && info "Waiting for apt lock... (${waited}s)"
    sleep 5; ((waited += 5))
  done
}

# Run a command as the login user, with ~/.local/bin on PATH.
as_user() { sudo -u "$TARGET_USER" -H env "PATH=$BIN_DIR:$PATH" "$@"; }

# Fill a config template with the settings above: render <template> <output-file>
render() {
  [[ -f "$1" ]] || fail "template not found: $1"
  envsubst "$RENDER_VARS" < "$1" > "$2"
}
