#!/usr/bin/env bash
# Brev launchable setup script. This is the ONLY thing pasted into Brev; it fetches this
# repository at a pinned version and runs scripts/setup.sh from it.
#
# Pin REPO_REF to a full commit SHA before real use, so every VM gets identical scripts.
# For testing you can leave it on "main" or override it:  REPO_REF=<sha> bash bootstrap.sh
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/papillonlibre/Developer-Studies-Setup.git}"
REPO_REF="${REPO_REF:-main}"
DEST="${DEST:-/opt/developer-studies-setup}"

SUDO=""; [[ "$(id -u)" -eq 0 ]] || SUDO="sudo"

command -v git >/dev/null 2>&1 || { $SUDO apt-get update -qq && $SUDO apt-get install -y -qq git; }

$SUDO rm -rf "$DEST"
$SUDO mkdir -p "$DEST"
$SUDO git -C "$DEST" init --quiet
$SUDO git -C "$DEST" remote add origin "$REPO_URL"
$SUDO git -C "$DEST" fetch --quiet --depth 1 origin "$REPO_REF"
$SUDO git -C "$DEST" checkout --quiet --detach FETCH_HEAD

# A full 40-character SHA must match exactly what was checked out.
if [[ "$REPO_REF" =~ ^[0-9a-f]{40}$ ]]; then
  [[ "$($SUDO git -C "$DEST" rev-parse HEAD)" == "$REPO_REF" ]] || { echo "checked-out commit does not match REPO_REF" >&2; exit 1; }
fi

# `sudo` records the login user in SUDO_USER, so files are installed for that user, not root.
exec $SUDO bash "$DEST/scripts/setup.sh"
