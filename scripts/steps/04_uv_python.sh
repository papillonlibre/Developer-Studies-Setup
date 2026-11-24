# Step 4: uv (checksum-verified) and the two Pythons. Sourced by setup.sh.
# Python 3.11 is for Hermes, 3.12 is for Helix.
# shellcheck shell=bash

as_user mkdir -p "$BIN_DIR"
if [[ -x "$BIN_DIR/uv" ]] && [[ "$(as_user "$BIN_DIR/uv" --version | awk '{print $2}')" == "$UV_VERSION" ]]; then
  info "uv $UV_VERSION already installed"
else
  info "Installing uv $UV_VERSION..."
  uv_tmp="$(mktemp)"
  retry 3 10 "download uv installer" curl -fsSL "https://astral.sh/uv/${UV_VERSION}/install.sh" -o "$uv_tmp"
  actual="$(sha256sum "$uv_tmp" | awk '{print $1}')"
  [[ "$actual" == "$UV_INSTALLER_SHA256" ]] \
    || { rm -f "$uv_tmp"; fail "uv installer checksum mismatch\n  expected $UV_INSTALLER_SHA256\n  actual   $actual"; }
  chmod 755 "$uv_tmp"
  as_user env UV_UNMANAGED_INSTALL="$BIN_DIR" sh "$uv_tmp"
  rm -f "$uv_tmp"
fi
as_user uv python install "$HERMES_PYTHON" "$HELIX_PYTHON"
info "uv $(as_user uv --version | awk '{print $2}'); Pythons ready: $HERMES_PYTHON (Hermes), $HELIX_PYTHON (Helix)"

# Put ~/.local/bin on PATH for login shells, so participants can reach uv and uv-installed tools.
grep -q 'spindrift-path' "$TARGET_HOME/.bashrc" 2>/dev/null \
  || printf '\n# spindrift-path\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$TARGET_HOME/.bashrc"
