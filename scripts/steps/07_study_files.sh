# Step 7: the files participants work with. Sourced by setup.sh.
#   ~/study/traces/                  the production traces (ATIF), made to describe one agent
#   ~/study/ETHOS.md                 the project's ethos file
#   ~/study/local-model.env          the local model endpoint, in the form Helix's setup reads
#   ~/hermes-agent-under-test/       the agent's instructions file, its MCP tools and their fixture
# Everything is pinned to one commit and fetched from an allow-list, so nothing else is on disk.
# shellcheck shell=bash

as_user mkdir -p "$STUDY_DIR/traces"
if [[ "$(ls "$STUDY_DIR/traces"/*.atif.json 2>/dev/null | wc -l)" -eq "$EXPECTED_TRACE_COUNT" \
      && -s "$AUT_DIR/SOUL.md" && -s "$AUT_DIR/fixtures/world-v2.json" ]]; then
  info "Traces + agent-under-test files already staged"
else
  info "Fetching production traces, ETHOS.md, and agent-under-test files @ ${TRACES_SHA:0:7}..."
  tmp="$(mktemp -d)"
  git clone --quiet --filter=blob:none --no-checkout --sparse "$TRACES_REPO" "$tmp/repo"
  # Allow-list only: nothing outside this list is ever checked out.
  git -C "$tmp/repo" sparse-checkout set --no-cone \
    "/$EXAMPLE_DIR/ETHOS.md" \
    "/$EXAMPLE_DIR/traces/world-v3/production/*.atif.json" \
    "/$EXAMPLE_DIR/profiles/baseline-soul.md" \
    "/$EXAMPLE_DIR/src/pa_style_mock_mcp/*.py" \
    "/$EXAMPLE_DIR/fixtures/world-v2.json" \
    "/$EXAMPLE_DIR/pyproject.toml"
  git -C "$tmp/repo" checkout --quiet "$TRACES_SHA"
  src="$tmp/repo/$EXAMPLE_DIR"
  cp "$src"/traces/world-v3/production/*.atif.json "$STUDY_DIR/traces/"
  cp "$src"/ETHOS.md "$STUDY_DIR/ETHOS.md"
  # Agent under test = Hermes (installed in step 6) + SOUL.md + the fictional MCP tools.
  # SOUL.md is the agent's only instructions file; tools are discovered over MCP.
  # ETHOS.md is for the analysis tooling, not for the agent.
  mkdir -p "$AUT_DIR/mcp" "$AUT_DIR/fixtures"
  cp "$src"/profiles/baseline-soul.md "$AUT_DIR/SOUL.md"
  cp -r "$src"/src/pa_style_mock_mcp "$AUT_DIR/mcp/pa_style_mock_mcp"
  cp "$src"/fixtures/world-v2.json "$AUT_DIR/fixtures/world-v2.json"
  cp "$src"/pyproject.toml "$AUT_DIR/pyproject.toml"
  rm -rf "$tmp"   # no .git left behind
  chown -R "$TARGET_USER":"$TARGET_USER" "$AUT_DIR" 2>/dev/null || true
fi
n="$(ls "$STUDY_DIR/traces"/*.atif.json | wc -l)"
((n == EXPECTED_TRACE_COUNT)) || fail "Expected $EXPECTED_TRACE_COUNT traces, found $n"

# Make the traces describe the same single agent that live Hermes reports (see sanitize_traces.py).
# Runs every time, so a re-run of setup repairs the files.
python3 -I "$REPO_ROOT/scripts/sanitize_traces.py" \
  "$HERMES_AGENT_VERSION" "$STUDY_DIR/traces" "$HERMES_AGENT_NAME" "$MODEL_ALIAS"
chown "$TARGET_USER":"$TARGET_USER" "$STUDY_DIR/traces"/*.atif.json 2>/dev/null || true
( cd "$STUDY_DIR/traces" && sha256sum ./*.atif.json > "$STUDY_DIR/traces/SHA256SUMS" )
info "Staged $n ATIF traces + ETHOS.md in $STUDY_DIR"

# Local model endpoint for Helix's setup (see configs/local-model.env.tmpl).
render "$REPO_ROOT/configs/local-model.env.tmpl" "$STUDY_DIR/local-model.env"
