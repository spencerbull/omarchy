is_arm_image=0
if [[ $(uname -m) == aarch64 ]]; then
  if [[ ${OMARCHY_ARM_IMAGE_INSTALL:-} != 1 ]]; then
    echo "Error: ARM image authorization disappeared before NVIDIA driver installation" >&2
    return 1
  fi
  is_arm_image=1
fi

if (( is_arm_image )) || lspci | grep -qi 'nvidia'; then
  if (( is_arm_image )); then
    case ${OMARCHY_ARM_PLATFORM:-} in
      gb10) KERNEL_HEADERS="linux-gb10-headers" ;;
      n1x) KERNEL_HEADERS="linux-n1x-headers" ;;
      *)
        echo "Error: the authorized ARM image has no supported platform profile" >&2
        return 1
        ;;
    esac
    PACKAGES=(nvidia-open-dkms=610.57.04-1 nvidia-utils=610.57.04-1 libva-nvidia-driver)
    GPU_ARCH="turing_plus"
  else
    # Check which kernel is installed and set appropriate headers package
    KERNEL_HEADERS="$(pacman -Qqs '^linux(-zen|-lts|-hardened)?$' | head -1)-headers"
  fi

  if (( ! is_arm_image )) && omarchy-hw-nvidia-gsp; then
    PACKAGES=(nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver)
    GPU_ARCH="turing_plus"
  elif (( ! is_arm_image )) && omarchy-hw-nvidia-without-gsp; then
    PACKAGES=(nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils)
    GPU_ARCH="maxwell_pascal_volta"
  fi
  # Bail if no supported GPU
  if [[ -z ${PACKAGES+x} ]]; then
    echo "No compatible driver for your NVIDIA GPU. See: https://wiki.archlinux.org/title/NVIDIA"
    exit 0
  fi

  if ! omarchy-pkg-add "$KERNEL_HEADERS" "${PACKAGES[@]}"; then
    echo "Error: failed to install the NVIDIA driver transaction" >&2
    return 1
  fi
  if (( is_arm_image )); then
    if [[ $(pacman -Q nvidia-open-dkms 2>/dev/null | awk '{print $2}') != 610.57.04-1 ]] ||
      [[ $(pacman -Q nvidia-utils 2>/dev/null | awk '{print $2}') != 610.57.04-1 ]] ||
      ! pacman -Q "$KERNEL_HEADERS" libva-nvidia-driver >/dev/null; then
      echo "Error: the authorized ARM image NVIDIA driver transaction is incomplete" >&2
      return 1
    fi
  fi

  if (( is_arm_image )) && [[ ${OMARCHY_ARM_PLATFORM:-} == "n1x" ]]; then
    # Preserve the firmware framebuffer and console during initial N1x
    # bring-up. The working GB10/FastOS boot chain loads NVIDIA after root;
    # forcing these modules into the initramfs made nomodeset ineffective and
    # left the N1x target with an unexplained black screen.
    sudo rm -f /etc/mkinitcpio.conf.d/nvidia.conf
    sudo tee /etc/modprobe.d/nvidia.conf <<'EOF' >/dev/null
options nvidia_drm modeset=0
EOF
  else
    # Configure modprobe and mkinitcpio for early KMS on supported x86 GPUs.
    sudo tee /etc/modprobe.d/nvidia.conf <<'EOF' >/dev/null
options nvidia_drm modeset=1
EOF
    sudo tee /etc/mkinitcpio.conf.d/nvidia.conf <<'EOF' >/dev/null
MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
EOF
  fi

  # Add NVIDIA environment variables based on GPU architecture
  if [[ $GPU_ARCH = "turing_plus" ]]; then
    # Turing+ (RTX 20xx, GTX 16xx, and newer) with GSP firmware support
    cat >>"$HOME/.config/hypr/envs.lua" <<'EOF'

-- NVIDIA (Turing+ with GSP firmware)
hl.env("NVD_BACKEND", "direct")
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
EOF
  elif [[ $GPU_ARCH = "maxwell_pascal_volta" ]]; then
    # Maxwell/Pascal/Volta (GTX 9xx/10xx, GT 10xx, Quadro P/M/GV, MX series, Titan X/Xp/V) lack GSP firmware
    cat >>"$HOME/.config/hypr/envs.lua" <<'EOF'

-- NVIDIA (Maxwell/Pascal/Volta without GSP firmware)
hl.env("NVD_BACKEND", "egl")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
EOF
  fi
fi
