# GB10 Omarchy installer workstream

## Goal

Create a branch from current `upstream/dev` in the user's Omarchy fork and
produce a bootable aarch64 Omarchy installer image that performs a complete,
unabridged Omarchy installation on NVIDIA GB10 hardware. Partial manifests and
silently omitted x86-only packages are not acceptable.

## Done criteria

- The branch is based on current `upstream/dev` and pushed to
  `spencerbull/omarchy`.
- The installer detects GB10 narrowly and installs `linux-gb10` plus its
  required companion packages without changing the kernel choice on other
  hardware.
- The install source can resolve the exact aarch64 `linux-gb10` package built
  from `spencerbull/omarchy-pkgs@1506367` without relying on an unpublished
  ambient package repository.
- A bootable aarch64 installer image is built successfully and its contents
  are inspected to prove the GB10 kernel package and selection logic are
  present.
- Static checks, focused tests, an independent review, and artifact checks
  pass.

## Worktree and branch

- Canonical checkout: `/home/sbull/omarchy-repos/omarchy` (do not edit)
- Worktree: `/home/sbull/omarchy-repos/omarchy-gb10-installer`
- Branch: `gb10-installer-kernel`
- Base: `upstream/dev` at `b9ddccfc377abe0b8fc3ff1ee5b31a86bf202d4a`
- ISO canonical checkout: `/home/sbull/omarchy-repos/omarchy-iso` (do not edit)
- ISO implementation worktree:
  `/home/sbull/omarchy-repos/omarchy-iso-gb10-dev`
- ISO implementation branch: `gb10-dev-installer-iso`
- ISO implementation base: `origin/main` at
  `168c6edb0b053bad7495bf051326a65c559b805e`
- Package implementation worktree:
  `/home/sbull/omarchy-repos/omarchy-pkgs-linux-gb10`
- Package branch: `linux-gb10`; current pushed head `01f0e735`, including the
  complete native runtime/desktop ports, hardened Chromium-based Spotify
  package, Limine AArch64 hook, and the `yay`/`yay-debug` split required by the
  final offline closure.
- Pushed heads: Omarchy `88e57e27`, ISO `7b5e92a8`, packages `01f0e735`; all
  three fork refs were verified with `git ls-remote` at their respective push
  checkpoints.
- Superseded Quattro ISO investigation worktree was clean, deinitialized, and
  removed after its package audit was captured. Its local scratch branch was
  deleted; the corresponding commit was already present on `origin/quattro`.

## Allowed actions

- Edit, test, commit, and push only the isolated worktree branch.
- Build unsigned local installer/package artifacts in isolated build paths.
- Use a remote build host if required after verifying and isolating its
  checkout and output paths.
- Read the existing `linux-gb10` package branch and built packages.

## Forbidden actions

- Do not modify the canonical Omarchy checkout or its untracked user file.
- Do not install or boot the image on a GB10 automatically.
- Do not edit firmware, EFI entries, services, credentials, or package-repo
  production state.
- Do not publish or sign package repositories, merge branches, or open a pull
  request without separate authorization.
- Do not overwrite existing build or NAS artifacts.

## Required gates

- Confirm the live Omarchy installer and ISO ownership boundaries.
- Confirm a robust, narrow GB10 hardware signal.
- Verify package provenance and dependency resolution.
- Run shell/static tests and repository test suites relevant to the change.
- Build and inspect the aarch64 installer image.
- Run an independent read-only review of the final diff and remediate findings.
- Verify final branch bytes and fork remote head before reporting completion.

## Workers

- Backend: Herdr (`HERDR_ENV=1`).
- `gb10_iso_contract` (Codex, pane `wY:p0`, tab `wY:t6`): read-only
  researcher mapping ISO ownership, installer kernel/package flow, robust GB10
  detection, and minimum cross-repository changes. Cwd:
  `/home/sbull/omarchy-repos/omarchy-gb10-installer`; branch:
  `gb10-installer-kernel`; state: complete. Finding: the ISO must boot its
  live environment with `linux-gb10`, index the prebuilt archive in the
  offline repository, and select the same package for the target. Cleanup
  owner: orchestrator.
- `gb10_arm_packages` (Codex, pane `wY:p11`, tab `wY:t6`): read-only audit of
  the full aarch64 package closure, local PKGBUILD coverage, and the NVIDIA
  580.173.02 GB10 kernel/user-space/firmware requirements. Cwd/worktree:
  `/home/sbull/omarchy-repos/omarchy-iso-gb10-installer`; branch:
  `gb10-installer-iso`; audit complete, then reassigned as the bounded writer
  for `/home/sbull/omarchy-repos/omarchy-iso-gb10-dev` on
  `gb10-dev-installer-iso`; state: complete and pane closed. Cleanup owner:
  orchestrator.
- `gb10_final_review` (Codex, pane `wY:p12`, tab `wY:t4`): independent
  read-only review across the package, Omarchy, and ISO branches. Initial
  verdict: NO-GO. Confirmed blockers were the Node manifest parser, x86-only
  installed Limine deployment, late online-install rejection, spoofable GB10
  fixtures, unsafe partial update path, mutable privileged ARM image,
  overridable unsupported-AArch64 guard, and unpinned NVIDIA pair/firmware.
  All eight findings were remediated locally. Later bounded passes found and
  verified fixes for atomic ISO publication, complete lifecycle-route guards,
  early detector-loss rejection, cleanup propagation, source-contract ordering,
  AUR sync durability, and sudo-policy ownership. Final bounded verdict: GO
  for committing and pushing all three current trees. State: complete; cleanup
  owner: orchestrator.
- `gb10_existing_ports` (Codex, pane `wY:p13`, tab `wY:t6`): bounded writer
  for native AArch64 support in the existing `asdcontrol`,
  `hyprland-preview-share-picker`, `pinta`, and `tzupdate` recipes. Worktree:
  `/home/sbull/omarchy-repos/omarchy-pkgs-gb10-existing-ports`; branch:
  `gb10-existing-package-ports`; commit `2f4842f`, cherry-picked as `897fcc9`;
  state: complete and pane closed. Cleanup owner: orchestrator.
- `gb10_missing_ports` (Codex, pane `wY:p14`, tab `wY:t6`): bounded writer
  for feasible native AArch64 recipes for `dotnet-runtime-9.0`, `mise`, `nvim`,
  `obs-studio`, `obsidian`, and `qemu-user-static-binfmt`. Worktree:
  `/home/sbull/omarchy-repos/omarchy-pkgs-gb10-missing-ports`; branch:
  `gb10-missing-package-ports`; commit `20eecab`, cherry-picked as `74764b3`
  for the completed `mise` and `nvim` recipes; state: complete and pane closed.
  The remaining four packages need dedicated implementation/build streams.
  Cleanup owner: orchestrator.
- `gb10_runtime_ports` (Codex, pane `wY:p1J`, tab `wY:t6`): bounded writer for
  native `dotnet-host`/`dotnet-runtime-9.0` and
  `qemu-user-static-binfmt`. Worktree:
  `/home/sbull/omarchy-repos/omarchy-pkgs-gb10-runtime-ports`; branch:
  `gb10-runtime-ports`; commit `e6190f5`, independently reviewed GO and
  cherry-picked as `1cda213`. Coleman-native artifacts and runtime probes are
  retained under `runtime-ports-0c9ff227a2f1`; state: complete and pane closed.
  Cleanup owner: orchestrator.
- `gb10_desktop_ports` (Codex, pane `wY:p1K`, tab `wY:t6`): bounded writer and
  runtime investigator for native `obsidian` and `obs-studio`. Worktree:
  `/home/sbull/omarchy-repos/omarchy-pkgs-gb10-desktop-ports`; branch:
  `gb10-desktop-ports`; initial commits `849cb5f` (Obsidian) and `9f34cd3`
  (OBS), plus remediation commit `99ec3ba`. Obsidian now supersedes Arch's
  pkgrel, its patch passes `git diff --check`, and OBS uses the virtual JACK
  contract compatible with `pipewire-jack`. Coleman-native package/runtime
  probes and real H.264, HEVC, and AV1 NVENC recordings all passed. The three
  commits were independently reviewed GO and cherry-picked as `bc5dd55`,
  `411c4b4`, and `b6d2c35`. State: complete. Cleanup owner: orchestrator.
- `gb10_ports_review` (Codex, pane `wY:p1M`, tab `wY:t6`): independent reviewer
  for runtime and desktop package ports. Runtime verdict: GO. Desktop verdict:
  NO-GO on the package-contract findings recorded above; capability enumeration
  alone was also insufficient for an end-to-end NVENC claim. The bounded
  remediation re-review found no actionable issues and returned GO after
  authenticating all 24 saved evidence-manifest entries. State: complete.
  Cleanup owner: orchestrator.
- `gb10isoreview` (Codex, pane `wY:p1R`, tab `wY:tD`): direct Herdr-session,
  read-only reviewer. Returned GO for ISO commits `2059c35..16217a1` (exact
  Limine hook pin) and `16217a1..07f1875` (pinned Archiso v87 execution on
  AArch64 and EFI-stubbed ARM64 Image validation), and GO for package commit
  `615383b..01f0e73` (`yay`/`yay-debug` lifecycle). Its first review of the
  AArch64 Archiso adaptations found two strict-drift gaps: patch fuzz/context
  and boundary/duplicate initramfs hooks. Commit `9a2ed8c` closed the hook
  finding but the reviewer reproduced an `at_keyboard` context bypass. Final
  commit `7b5e92a` widened the hunk over the complete module assignment and
  changed the negative fixture to the exact bypass; the final direct re-review
  returned GO after all three focused suites and independent dry runs passed.
  No delegated/native-agent evidence is accepted. State: complete and pane
  closed by the orchestrator.

## Remote builds

- Finn kernel rebuild: `/home/dell/omarchy-repos/omarchy-pkgs-linux-gb10` at
  `1506367ddf1933492c678e6683204bbec108e174`, completed successfully with
  `./bin/build --arch aarch64 --package linux-gb10`; log:
  `finn-linux-gb10-build-1506367.log`. Runtime and headers are matching
  `6.17.13.nvidia1029-2` AArch64 packages; the embedded kernel is a Linux ARM64
  bootable `Image` with `ARMd` magic. The validated pair, log, and checksums were
  atomically published without overwrite to
  `/mnt/Batuu/omarchy-pkgs/linux-gb10/1506367`.
- Coleman package-closure build:
  `/home/dell/omarchy-gb10-builds/omarchy-pkgs-linux-gb10` at the same commit,
  building the 19 already-AArch64-capable Omarchy/Limine packages required by
  the offline image; log: `coleman-aarch64-omarchy-packages-1506367.log`.
  Complete: 16 recipes built successfully; `omarchy-walker` lacked its local
  Walker/Elephant dependency stack and both Limine helpers lacked Gradle.
- Coleman Walker dependency build: same checkout and commit, building Walker,
  all Elephant providers, and `omarchy-walker`; log:
  `coleman-aarch64-walker-stack-1506367.log`; complete, 15 of 15 recipes built.
- Coleman Limine helper build: Gradle 9.7.0 failed because of upstream's
  `gradle-public-api-legacy` regression. A signed Arch Archive Gradle 9.6.1
  package was verified and pinned in the isolated build repository; both
  helpers then built successfully in
  `coleman-aarch64-limine-helpers-1506367-v3.log`.
- Durable Coleman harvest:
  `/home/dell/omarchy-gb10-builds/gb10-package-bundle-1506367`. The two Limine
  helper artifacts and all completed closure builds are retained there. The
  bundle must be refreshed with the final Limine pkgrel, new native ports, and
  a rebuilt package database and `SHA256SUMS` before ISO construction.
- Final Coleman recipe build: clean clone
  `/home/dell/omarchy-gb10-builds/omarchy-pkgs-final-b6d2c356` at exact pushed
  head `b6d2c356`, running the repository wrapper for the seven changed existing
  recipes plus a native `linux-gb10` redundancy build. Log:
  `/home/dell/omarchy-gb10-builds/final-packages-b6d2c356-build.log`.
- Final Coleman seed bundle:
  `/home/dell/omarchy-gb10-builds/gb10-package-bundle-0b3786f`. It contains
  114 current AArch64/`any` package archives, including the exact kernel/header
  pair, NVIDIA 610.57.04 user-space/DKMS pair, firmware, native desktop/runtime
  ports, Spotify wrapper, Limine hook 1.37.1-4, and `yay` plus `yay-debug`
  13.0.1-1.1. `SHA256SUMS` contains 173 entries with manifest SHA-256
  `3f822bbdce0ccfcb20e886d8a88a24e22ced79169d1341f7454dfcb0484c3503`.
- Final Coleman ISO checkout:
  `/home/dell/omarchy-gb10-builds/omarchy-iso-gb10-16217a1`, clean at pushed
  ISO head `7b5e92a82f0fd624913b855832cc3fdf42f8763c`. Final build log:
  `/home/dell/omarchy-gb10-builds/omarchy-iso-gb10-7b5e92a-build.log`.
  The build completed successfully and published, without overwrite,
  `release/omarchy-2026.08.25-aarch64-gb10-gb10-installer-kernel.iso`
  (5,193,361,408 bytes; SHA-256
  `936a79f72b96bdfb3b35e2d89a04d4832903ebff76767b4b03cc18b1c7bbed99`).
  Inspection evidence is retained at
  `/home/dell/omarchy-gb10-builds/omarchy-iso-gb10-7b5e92a-inspection`.
  The ISO is bootable AArch64 UEFI media with a PE32+ AArch64
  `/EFI/BOOT/BOOTAA64.EFI`; GRUB and loopback entries load
  `vmlinuz-linux-gb10` plus `initramfs-linux-gb10.img`; the kernel is an ARM64
  `Image` with `ARMd` magic at offset 56; the SquashFS embeds installer commit
  `88e57e27`, the narrow SoC/PCI GB10 detector, 1,161 AArch64/`any` offline
  archives, and the exact kernel/header, NVIDIA 610.57.04, firmware, Limine,
  `yay`, and `yay-debug` packages. Earlier fail-closed runs exposed and drove
  fixes for Arch Linux ARM lacking an `archiso` binary package, EFI-stubbed
  ARM64 Images beginning with `MZ`, missing `yay-debug`, unavailable ARM64 GRUB
  modules, and x86-only initramfs hooks.

## Checkpoints

- [x] Fetch current `upstream/dev` and create an isolated branch/worktree.
- [x] Map ISO ownership, installer kernel selection, and GB10 detection seams.
- [x] Implement and fixture-test target GB10 detection, kernel selection, and
  NVIDIA package selection in the Omarchy worktree.
- [x] Implement complete package availability; ISO GB10 kernel selection and
  fail-closed closure validation are implemented, and the complete dependency
  transaction has resolved from AArch64/`any` archives.
- [x] Pass focused static and repository tests.
- [x] Build and inspect the aarch64 installer image.
- [x] Pass refreshed independent review after remediating the initial NO-GO.
- [x] Commit and push the reviewed Omarchy, ISO, and package branches to the
  user's forks.

## Open questions

- [Resolved] Omarchy owns target runtime setup; `omarchy-iso` owns the boot
  media, offline mirror, archinstall flow, and image build. A reproducible GB10
  image therefore requires coordinated branches in both repositories.
- [Resolved] The pinned Archiso supports AArch64 GRUB. The ISO branch now owns
  the AArch64 profile, ALARM mirrors/keyring, raw-kernel preset, AA64 Archinstall
  patch, exact platform guard, and complete offline-closure gate.
- [Resolved] The full dev manifest now has native AArch64 packages or explicit
  architecture-compatible implementations for every required package; the ISO
  closure remains fail-closed and does not silently omit unsupported entries.
- [Resolved] Native `dotnet-host`/`dotnet-runtime-9.0`,
  `qemu-user-static-binfmt`, Obsidian, and OBS recipes are integrated. Their
  artifacts passed native Coleman runtime tests; OBS additionally recorded and
  decoded H.264, HEVC, and AV1 through the packaged direct-NVENC path.
- [Resolved] Spotify is implemented as a native AArch64 Chromium application
  wrapper with desktop/icon/URI integration and hardened, pinned package
  sources; the package passed a native Coleman build and content audit.
- [Resolved] Boot gate: `linux-gb10@1506367` packages the raw AArch64 Linux
  `Image` required by Limine. The replacement build is running on Finn and the
  ISO validates the ARM64 image magic before use.
- [Resolved] Installed Limine maintenance: package branch `68aa73a` ports
  `limine-mkinitcpio-hook` to BOOTAA64.EFI and the Omarchy installer verifies
  both the dedicated and fallback loaders before removing Archinstall's NVRAM
  entry.
- [Resolved] Artifact gate: the validated ISO and inspection evidence are
  retained in the isolated Coleman build directory. No external publication or
  NAS destination has been authorized for the ISO.
- Human gate: boot the finished image on physical GB10 hardware and execute a
  complete install. Automatic boot/install, EFI mutation, and disk writes are
  intentionally out of scope for this loop.
