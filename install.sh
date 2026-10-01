#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -eEo pipefail

# Define Omarchy locations
export OMARCHY_PATH="$HOME/.local/share/omarchy"
export OMARCHY_INSTALL="$OMARCHY_PATH/install"
export OMARCHY_INSTALL_LOG_FILE="/var/log/omarchy-install.log"
export PATH="$OMARCHY_PATH/bin:$PATH"

# Reject unsupported or incomplete ARM invocation before helper loading can
# install presentation packages or otherwise mutate the target. During early
# N1x enablement, the complete development image is the authorization boundary;
# do not infer a specific product from Coleman-only hardware identifiers.
machine_arch=$(uname -m)
if [[ $machine_arch != x86_64 ]]; then
  if [[ $machine_arch != aarch64 ]]; then
    echo -e "\e[31mOmarchy install is unsupported on this architecture.\e[0m"
    exit 1
  fi
  if [[ ${OMARCHY_ARM_IMAGE_INSTALL:-} != 1 || ${OMARCHY_ARM_PLATFORM:-} != "gb10" && ${OMARCHY_ARM_PLATFORM:-} != "n1x" || -n ${OMARCHY_ONLINE_INSTALL:-} || ${OMARCHY_CHROOT_INSTALL:-} != 1 ]]; then
    echo -e "\e[31mAArch64 requires the complete authorized development installer image; direct and online installs are not available.\e[0m"
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
