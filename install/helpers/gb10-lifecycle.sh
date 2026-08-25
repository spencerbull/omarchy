omarchy-guard-gb10-lifecycle() {
  local operation=${1:-"This operation"}

  # Exact hardware detection classifies supported installation targets, but it
  # must never become permission to mutate an AArch64 system when sysfs evidence
  # is temporarily unavailable. No non-x86 lifecycle is supported yet.
  if [[ $(uname -m) != x86_64 ]]; then
    echo "$operation is disabled on AArch64 until a complete versioned package repository is available." >&2
    return 1
  fi

  return 0
}
