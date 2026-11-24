#!/usr/bin/env bash
# Builds the study VM: installs, pins, stages and smoke-tests everything that is NOT under study,
# so any friction a participant meets comes from the product and its docs, not from the machine.
#
# Run as the login user with sudo (it needs root, but installs files for the login user):
#     sudo bash scripts/setup.sh
# Normally bootstrap.sh does this for you (see README.md).
#
# What it does, in order (each step is its own file in scripts/):
#   01_preflight           check the GPU, driver and disk
#   02_system_packages     apt packages
#   03_docker_gpu          Docker + NVIDIA Container Toolkit
#   04_uv_python           uv (checksum-verified) + Python 3.11 and 3.12
#   05_model               Nemotron Bolt GGUF served by llama.cpp on 127.0.0.1:8000
#   06_hermes              Hermes Agent (pinned) wired to the local model and to NeMo Relay
#   07_study_files         the example traces, ETHOS.md and the agent-under-test files
#   08_replay_watcher      arms the service that loads the traces into Helix Intake
#   09_smoke_and_ready     runs smoke_test.sh and writes the ready sentinel
#
# What it deliberately does NOT do: install NeMo Helix (participants do that),
# or clone the Helix repo or docs.
#
# Pins live in configs/versions.env, names and ports in configs/study.env.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

# shellcheck source=lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"

# Everything below is also written to the launch log.
mkdir -p "$(dirname "$LAUNCH_LOG")"
exec > >(tee -a "$LAUNCH_LOG") 2>&1

STEPS=(
  01_preflight
  02_system_packages
  03_docker_gpu
  04_uv_python
  05_model
  06_hermes
  07_study_files
  08_replay_watcher
  09_smoke_and_ready
)

for step in "${STEPS[@]}"; do
  # Steps are sourced (not run) so they share the settings and helpers above.
  # shellcheck disable=SC1090
  source "$REPO_ROOT/scripts/steps/${step}.sh"
done
