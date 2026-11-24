#!/usr/bin/env bash
# Verifies the known-good environment. Exit 0 = ready for a participant.
#
# Setup installs this as ~/study/smoke-test.sh next to ~/study/smoke.conf (rendered from
# configs/smoke.conf.tmpl), so it can be re-run by hand, for example before each session:
#     ~/study/smoke-test.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/smoke.conf"
export PATH="$HOME/.local/bin:$PATH"
pass=0; failn=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS  $d"; pass=$((pass+1)); else echo "FAIL  $d"; failn=$((failn+1)); fi; }

chat() { curl -fsS "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' -d "$1"; }
T_CHAT='{"model":"'$ALIAS'","messages":[{"role":"user","content":"Reply with the single word: ready"}],"max_tokens":512,"chat_template_kwargs":{"enable_thinking":false}}'
T_TOOL='{"model":"'$ALIAS'","messages":[{"role":"user","content":"What is the weather in Paris? Use the tool."}],"tools":[{"type":"function","function":{"name":"get_weather","description":"Get weather","parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}}],"max_tokens":1024,"chat_template_kwargs":{"enable_thinking":false}}'

# Only these files may exist under the study folders (everything else is unexpected).
unexpected_files() {
  find "$STUDY" "$AUT" -type f \
    ! -path "$STUDY/traces/*.atif.json" ! -path "$STUDY/traces/SHA256SUMS" \
    ! -path "$STUDY/ETHOS.md" ! -path "$STUDY/local-model.env" \
    ! -path "$STUDY/replay-traces.*" ! -path "$STUDY/replay-watcher.log" ! -path "$STUDY/.replay*" \
    ! -path "$STUDY/smoke*" \
    ! -path "$AUT/SOUL.md" ! -path "$AUT/pyproject.toml" ! -path "$AUT/fixtures/world-v2.json" \
    ! -path "$AUT/mcp/*"
}
no_unexpected_files() { [ -z "$(unexpected_files)" ]; }
traces_dir_clean() { [ -z "$(find "$STUDY/traces" -type f ! -name '*.atif.json' ! -name SHA256SUMS)" ]; }
no_example_repo_clone() { [ ! -e "$HOME/nemoclaw-community" ]; }
traces_sanitized() { python3 -I "$REPO_ROOT/scripts/sanitize_traces.py" "$AGENT_VERSION" "$STUDY/traces" "$AGENT_NAME" "$ALIAS" --check; }

# --- Machine
check "NVIDIA GPU visible"                     nvidia-smi
check "GPU is Ada or newer (cc >= 8.9)"        bash -c 'awk "BEGIN{exit !($(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1) >= 8.9)}"'
check "Docker works"                           docker ps
check "Docker can see the GPU"                 docker run --rm --gpus all ubuntu:22.04 nvidia-smi
check "uv >= 0.9.14 (Helix 0.6 minimum)"       bash -c 'printf "%s\n0.9.14\n" "$(uv --version | awk "{print \$2}")" | sort -V -C -r'
check "Python $HELIX_PYTHON available"         uv run --python "$HELIX_PYTHON" python -V
check "RAM >= 8GB"                             bash -c '[ "$(awk "/MemTotal/{print int(\$2/1048576)}" /proc/meminfo)" -ge 8 ]'
check "Disk >= 16GB free"                      bash -c '[ "$(df -BG --output=avail "$HOME" | tail -1 | tr -dc 0-9)" -ge 16 ]'
# --- Model
check "llama-server healthy"                   curl -fsS "http://127.0.0.1:$PORT/health"
check "Model alias is served"                  bash -c "curl -fsS http://127.0.0.1:$PORT/v1/models | jq -e '.data[]|select(.id==\"$ALIAS\")'"
check "Chat completion works"                  bash -c "$(declare -f chat); PORT=$PORT; chat '$T_CHAT' | jq -e '.choices[0].message.content|length>0'"
check "Tool calling works"                     bash -c "$(declare -f chat); PORT=$PORT; chat '$T_TOOL' | jq -e '.choices[0].message.tool_calls|length>0'"
# --- Hermes + Relay
check "Hermes $HERMES_VERSION + nemo-relay $NEMO_RELAY_VERSION" bash -c "$HERMES_PY - <<PY
from importlib.metadata import version
from hermes_cli import __version__
assert __version__ == '$HERMES_VERSION', __version__
assert version('nemo-relay') == '$NEMO_RELAY_VERSION'
PY"
# (`hermes doctor` never mentions Relay, so Relay is proven by the two trajectory checks below.)
rm -f "$RELAY_OUT"/atif/*.json
check "Hermes completes a turn (no Intake running)" bash -c 'hermes chat --provider "'$HERMES_PROVIDER'" --model "'$ALIAS'" --query "Reply with exactly: SMOKE_OK" --max-turns 3 --run-budget 180 --accept-hooks --quiet | grep -q SMOKE_OK'
check "Relay wrote an ATIF trajectory"         bash -c 'find "'$RELAY_OUT'/atif" -name "trajectory-*.json" -size +0c | grep -q .'
check "Live Relay trajectory carries agent version $AGENT_VERSION" bash -c 'grep -hq "\"version\": *\"'$AGENT_VERSION'\"" "'$RELAY_OUT'"/atif/trajectory-*.json'
rm -f "$RELAY_OUT"/atif/*.json    # leave participants a clean directory
# --- Study files
check "$EXPECTED ATIF traces staged"           bash -c "[ \"\$(ls $STUDY/traces/*.atif.json | wc -l)\" -eq $EXPECTED ]"
check "Trace checksums match"                  bash -c "cd $STUDY/traces && sha256sum -c --quiet SHA256SUMS"
check "Traces describe ONE agent ($AGENT_NAME $AGENT_VERSION @ $ALIAS)" traces_sanitized
check "Replay watcher armed (or already replayed)" bash -c "systemctl is-active --quiet spindrift-replay || pgrep -f replay-traces.py >/dev/null || test -e $STUDY/.replayed"
check "ETHOS.md staged"                        test -s "$STUDY/ETHOS.md"
check "Agent-under-test files staged (SOUL, MCP, world)" bash -c "test -s $AUT/SOUL.md && test -s $AUT/fixtures/world-v2.json && test -s $AUT/mcp/pa_style_mock_mcp/tools.py"
check "No unexpected files in the study folders" no_unexpected_files
check "Traces folder holds only traces and checksums" traces_dir_clean
check "No clone of the example repo on disk"   no_example_repo_clone
# --- Helix preconditions (Helix itself must NOT be present)
check "Port 8080 free for Helix"               bash -c '! ss -ltn | grep -q ":8080 "'
check "NeMo Helix NOT preinstalled"            bash -c '! command -v nemo'
check "Helix repo NOT cloned"                  bash -c '! ls -d $HOME/nemo-platform $HOME/nemo-helix 2>/dev/null | grep -q .'
check "Reach PyPI (nemo-platform)"             curl -fsSI https://pypi.org/simple/nemo-platform/
check "Reach Helix v0.6 docs"                  curl -fsSI "$DOCS_URL"
check "Reach Helix 0.6.0 code tag"             curl -fsSI "$CODE_URL"
echo "----"; echo "passed=$pass failed=$failn"
[ "$failn" -eq 0 ]
