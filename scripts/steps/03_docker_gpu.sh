# Step 3: Docker + NVIDIA Container Toolkit. Sourced by setup.sh.
# Helix's local services and the llama.cpp server both run in Docker.
# shellcheck shell=bash

if ! command -v docker >/dev/null 2>&1; then
  info "Installing Docker..."
  wait_for_apt_lock
  retry 3 10 "install docker" sudo apt-get install -y -qq docker.io >/dev/null 2>&1
fi
sudo systemctl enable --now docker
sudo usermod -aG docker "$TARGET_USER" 2>/dev/null || true
# SSH sessions won't see the new docker group until re-login. Docker permissions are not
# what participants are being tested on, so make the socket usable now.
sudo chmod 666 /var/run/docker.sock
info "Docker: $(docker --version)"

if ! docker info 2>/dev/null | grep -qi 'nvidia'; then
  info "Installing NVIDIA Container Toolkit..."
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | sudo gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
  wait_for_apt_lock
  retry 3 10 "apt-get update (nvidia)" sudo apt-get update -qq
  retry 3 10 "install nvidia-container-toolkit" sudo apt-get install -y -qq nvidia-container-toolkit >/dev/null 2>&1
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker
  sudo chmod 666 /var/run/docker.sock
fi

# Pilot 2026-11-20 (Brev L40S, driver 565.57.01, toolkit 1.20.2): config.toml had mode="cdi" but no
# CDI spec existed and `nvidia-ctk cdi generate` crashed (free(): invalid pointer), so every GPU
# container failed with "unresolvable CDI devices nvidia.com/gpu=all". Legacy mode works.
if grep -Eq '^mode *= *"(cdi|auto)"' /etc/nvidia-container-runtime/config.toml 2>/dev/null \
   && [[ ! -s /etc/cdi/nvidia.yaml ]]; then
  info "Toolkit is in CDI/auto mode with no CDI spec; switching nvidia-container-runtime to legacy mode"
  sudo nvidia-ctk config --set nvidia-container-runtime.mode=legacy --in-place
  sudo systemctl restart docker
  sudo chmod 666 /var/run/docker.sock
fi
info "NVIDIA Container Toolkit ready"
