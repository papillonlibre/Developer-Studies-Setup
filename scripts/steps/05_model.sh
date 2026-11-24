# Step 5: Nemotron 3.5 Bolt, served by llama.cpp. Sourced by setup.sh.
# shellcheck shell=bash

as_user mkdir -p "$MODEL_DIR"
if [[ -s "$MODEL_DIR/$MODEL_FILE" && -s "$MODEL_DIR/$MMPROJ_FILE" && -s "$MODEL_DIR/$DRAFT_FILE" ]]; then
  info "Model files already present in $MODEL_DIR"
else
  info "Downloading Bolt GGUF + projector + DFlash drafter (~30GB, resumable)..."
  retry 3 20 "download model" as_user uvx --from "huggingface_hub${HF_HUB_SPEC}" hf download \
    "$MODEL_REPO" "$MODEL_FILE" "$MMPROJ_FILE" --revision "$MODEL_REV" --local-dir "$MODEL_DIR"
  retry 3 20 "download drafter" as_user uvx --from "huggingface_hub${HF_HUB_SPEC}" hf download \
    "$DRAFT_REPO" "$DRAFT_FILE" --revision "$DRAFT_REV" --local-dir "$MODEL_DIR"
fi
info "Recording model checksums..."
( cd "$MODEL_DIR" && sha256sum "$MODEL_FILE" "$MMPROJ_FILE" "$DRAFT_FILE" | tee "$MODEL_DIR/SHA256SUMS" )
# TODO(pilot): once a run is validated, hard-code the expected hashes in configs/versions.env and compare.

info "Pulling llama.cpp ${LLAMA_IMAGE_TAG_FOR_HUMANS} by digest ..."
retry 3 15 "pull llama.cpp image" docker pull "$LLAMA_IMAGE"
info "llama.cpp image: $(docker image inspect "$LLAMA_IMAGE" --format '{{index .RepoDigests 0}}' 2>/dev/null || echo unknown)"

info "Starting llama-server (alias: $MODEL_ALIAS, ctx: $LLAMA_CTX, parallel: $LLAMA_PARALLEL)..."
docker rm -f llama-bolt >/dev/null 2>&1 || true
# Flags follow the model card's 48GB+ recipe. --jinja is required for tool calling.
docker run -d --name llama-bolt --restart unless-stopped --gpus all "${NVIDIA_BYPASS_ARGS[@]}" \
  -p "127.0.0.1:${LLAMA_PORT}:8000" -v "$MODEL_DIR":/models:ro \
  "$LLAMA_IMAGE" \
  --host 0.0.0.0 --port 8000 \
  --model "/models/$MODEL_FILE" --mmproj "/models/$MMPROJ_FILE" --alias "$MODEL_ALIAS" \
  --batch-size 4096 --ubatch-size 2048 \
  --ctx-size "$LLAMA_CTX" --parallel "$LLAMA_PARALLEL" -ngl 999 \
  --spec-type draft-dflash --spec-draft-n-max 7 \
  --spec-draft-model "/models/$DRAFT_FILE" --spec-draft-ngl 999 \
  --temp 1.0 --top-p 0.95 --flash-attn on --jinja >/dev/null

info "Waiting for llama-server to become healthy (model load can take several minutes)..."
for i in $(seq 1 120); do
  if curl -fsS "http://127.0.0.1:${LLAMA_PORT}/health" >/dev/null 2>&1; then
    info "llama-server healthy after ~$((i * 5))s"; break
  fi
  if ! docker ps --format '{{.Names}}' | grep -qx llama-bolt; then
    docker logs --tail 50 llama-bolt || true
    fail "llama-server container exited. Likely GPU/arch or flag incompatibility; see the log above."
  fi
  ((i == 120)) && { docker logs --tail 50 llama-bolt || true; fail "llama-server not healthy after 10 min"; }
  sleep 5
done
