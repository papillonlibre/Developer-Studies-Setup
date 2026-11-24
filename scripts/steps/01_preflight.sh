# Step 1: preflight. Sourced by setup.sh. Fails fast on hardware that cannot run the model.
# shellcheck shell=bash

info "Preflight checks..."
command -v nvidia-smi >/dev/null 2>&1 || fail "nvidia-smi not found: this setup needs a GPU instance with the NVIDIA driver"
GPU_NAME="$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
GPU_COUNT="$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)"
GPU_CC="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1 | tr -d ' ')"
GPU_MEM_MB="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1 | tr -d ' ')"
info "GPU: ${GPU_COUNT}x ${GPU_NAME} (compute ${GPU_CC}, ${GPU_MEM_MB} MiB)"

# The Bolt GGUF supports Ada (8.9) and Blackwell (10.x/12.x). Ampere (8.0/8.6) is NOT supported.
if awk "BEGIN{exit !($GPU_CC < 8.9)}"; then
  fail "GPU compute capability ${GPU_CC} < 8.9 (Ada). Nemotron Bolt GGUF supports Ada/Blackwell only. Use an L40S."
fi

# The pinned llama.cpp image declares that it needs a driver supporting CUDA >= 12.8.
# Brev's L40S images ship driver 565 (CUDA 12.7). Pilot 2026-11-20: the image runs fine on 12.7
# (chat, tool calling and DFlash all work) once the container toolkit's version check is skipped.
CUDA_VER="$(nvidia-smi | sed -n 's/.*CUDA Version: \([0-9]*\.[0-9]*\).*/\1/p' | head -1)"
info "Driver supports CUDA ${CUDA_VER:-unknown}"
NVIDIA_BYPASS_ARGS=()
if [[ -n "$CUDA_VER" ]] && awk "BEGIN{exit !($CUDA_VER < 12.8)}"; then
  warn "Driver supports CUDA ${CUDA_VER} < 12.8 (image requirement). Skipping the check with NVIDIA_DISABLE_REQUIRE=1 (verified in the 2026-11-20 pilot)."
  NVIDIA_BYPASS_ARGS=(-e NVIDIA_DISABLE_REQUIRE=1)
fi

((GPU_MEM_MB >= 40000)) || warn "GPU has <40GB; the 262144-ctx recipe needs 48GB+. Consider LLAMA_CTX=65536."

FREE_GB="$(df -BG --output=avail "$TARGET_HOME" | tail -1 | tr -dc '0-9')"
((FREE_GB >= 100)) || warn "Only ${FREE_GB}GB free in $TARGET_HOME. Need ~30GB model + ~16GB Helix + Docker images; recommend 100GB+."
