# Omarchy N1X bring-up

This branch publishes the experimental September 2026 N1X implementation. The three matching branches are:

- [Kernel and package recipes](https://github.com/spencerbull/omarchy-pkgs/tree/n1x-bringup)
- [Omarchy installer](https://github.com/spencerbull/omarchy/tree/n1x-bringup)
- [AArch64 ISO builder](https://github.com/spencerbull/omarchy-iso/tree/n1x-bringup)

Each fork also has an `n1x-base` branch at the last commit before its N1X snapshot. The pull request from `n1x-bringup` to `n1x-base` shows the N1X changes on top of the earlier GB10/AArch64 foundation; it is not a proposal to merge into upstream or the fork's default branch.

## Recorded hardware status

On September 3, the Dell XPS 16 DX16263 booted the installed system with the panel console and LUKS prompt visible. Kernel `7.0.14-2-n1x` restored the internal keyboard and touchpad after the MediaTek I2C ACPI and GPIO debounce patches. A software-rendered Hyprland desktop ran on SimpleDRM with the NVIDIA stack disabled.

NVIDIA 610.57.04 bound GPU `10de:2e06` but failed to initialize GSP. GPU acceleration, the FF-A embedded-controller interface (battery/lid/thermal/UCSI), invisible hyprlock under software rendering, and automatic rescue-UKI refresh after kernel upgrades remain open in this snapshot. Hardware results are historical; this publication does not claim a new kernel/ISO build or physical retest. The historical `TODO.md` and `N1X_HANDOFF.md` contain earlier entries superseded by their later dated results.

## Installer changes

The N1X path explicitly selects and validates `linux-n1x` and matching headers before removing the generic kernel. Its implementation is in [`install/config/hardware/nvidia/n1x-kernel.sh`](install/config/hardware/nvidia/n1x-kernel.sh), with diagnostics and SSH recovery alongside it.

[`install/login/limine-snapper.sh`](install/login/limine-snapper.sh) adds `console=tty0 acpi=nospcr`, removes conflicting quiet defaults, gives the rescue entry its own command line, and verifies the generated AArch64 boot entries. It omits Plymouth on AArch64, avoids forced early NVIDIA module injection for N1X, and uses `snapper --no-dbus` in the installer.

Use this checkout with the matching ISO branch via `OMARCHY_PATH` and `--local-source`; the ISO guide contains the command. The original early-input module list still names Tegra I2C, but the actual internal-input fix is the patched MediaTek driver in the companion kernel package.

Focused verification from this repository root:

```bash
bash test/omarchy-hw-nvidia-gb10-test.sh
```

The target-only software-rendering workaround is documented as a historical result, not claimed as an installer default in this snapshot.
