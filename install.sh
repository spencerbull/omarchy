#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -eEo pipefail

# Define Omarchy locations
export OMARCHY_PATH="$HOME/.local/share/omarchy"
export OMARCHY_INSTALL="$OMARCHY_PATH/install"
export OMARCHY_INSTALL_LOG_FILE="/var/log/omarchy-install.log"
export PATH="$OMARCHY_PATH/bin:$PATH"

# Reject unsupported or incomplete ARM invocation before helper loading can
# install presentation packages or otherwise mutate the target.
if [[ $(uname -m) != x86_64 ]]; then
  if ! omarchy-hw-nvidia-gb10; then
    echo -e "\e[31mOmarchy install is unsupported on this architecture. Only x86_64 and the exact NVIDIA GB10 platform are accepted.\e[0m"
    exit 1
  fi
  if [[ -n ${OMARCHY_ONLINE_INSTALL:-} || ${OMARCHY_CHROOT_INSTALL:-} != 1 ]]; then
    echo -e "\e[31mGB10 requires the complete Omarchy installer image; direct and online installs are not available.\e[0m"
    exit 1
  fi
fi

# Install
source "$OMARCHY_INSTALL/helpers/all.sh"
source "$OMARCHY_INSTALL/preflight/all.sh"
source "$OMARCHY_INSTALL/packaging/all.sh"
source "$OMARCHY_INSTALL/config/all.sh"
source "$OMARCHY_INSTALL/login/all.sh"
source "$OMARCHY_INSTALL/post-install/all.sh"
