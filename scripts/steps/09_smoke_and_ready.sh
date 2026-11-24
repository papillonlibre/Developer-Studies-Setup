# Step 9: smoke test and readiness. Sourced by setup.sh.
# The smoke test is also installed in ~/study so it can be re-run by hand.
# shellcheck shell=bash

render "$REPO_ROOT/configs/smoke.conf.tmpl" "$STUDY_DIR/smoke.conf"
install -m 755 "$REPO_ROOT/scripts/smoke_test.sh" "$STUDY_DIR/smoke-test.sh"
chown -R "$TARGET_USER":"$TARGET_USER" "$STUDY_DIR" "$MODEL_DIR" 2>/dev/null || true

info "Running smoke test..."
if as_user bash "$STUDY_DIR/smoke-test.sh"; then SMOKE="PASSED"; else SMOKE="FAILED"; fi

if [[ "$SMOKE" == "PASSED" ]]; then
  sudo touch "$SENTINEL"
  echo "=== Ready ===" | sudo tee -a "$LAUNCH_LOG" >/dev/null
else
  warn "Smoke test FAILED, sentinel not written. See $LAUNCH_LOG"
fi

info "════════════════════════════════════════════════════"
info "  Spindrift VM setup: smoke test $SMOKE"
info "  GPU:        ${GPU_COUNT}x ${GPU_NAME}"
info "  Model:      ${MODEL_ALIAS} @ http://127.0.0.1:${LLAMA_PORT}/v1"
info "  Hermes:     ${HERMES_VERSION} (${HERMES_REF}) + nemo-relay ${NEMO_RELAY_VERSION}"
info "  Relay→Helix: ${INTAKE_OTLP_URL}"
info "  Traces:     $STUDY_DIR/traces ($n files, pinned ${TRACES_SHA:0:7})"
info "  Helix pin:  ${HELIX_VERSION_TAG} (docs: ${HELIX_DOCS_URL})"
info "  Sentinel:   $SENTINEL"
info "════════════════════════════════════════════════════"
[[ "$SMOKE" == "PASSED" ]]
