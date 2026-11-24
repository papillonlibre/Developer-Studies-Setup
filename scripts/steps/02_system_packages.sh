# Step 2: apt packages. Sourced by setup.sh.
# shellcheck shell=bash

info "Installing system packages..."
wait_for_apt_lock
retry 3 10 "apt-get update" sudo apt-get update -qq
# gettext-base provides envsubst, which fills the config templates in configs/.
retry 3 10 "apt-get install" sudo apt-get install -y -qq \
  ca-certificates curl git jq tar build-essential gettext-base >/dev/null 2>&1
command -v envsubst >/dev/null 2>&1 || fail "envsubst missing after installing gettext-base"
info "System packages installed"
