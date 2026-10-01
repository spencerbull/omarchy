# Directs user to Omarchy Discord
QR_CODE='
█▀▀▀▀▀█ ▄ ▄ ▀▄▄▄█ █▀▀▀▀▀█
█ ███ █ ▄▄▄▄▀▄▀▄▀ █ ███ █
█ ▀▀▀ █ ▄█  ▄█▄▄▀ █ ▀▀▀ █
▀▀▀▀▀▀▀ ▀▄█ █ █ █ ▀▀▀▀▀▀▀
▀▀█▀▀▄▀▀▀▀▄█▀▀█  ▀ █ ▀ █
█▄█ ▄▄▀▄▄ ▀ ▄ ▀█▄▄▄▄ ▀ ▀█
▄ ▄▀█ ▀▄▀▀▀▄ ▄█▀▄█▀▄▀▄▀█▀
█ ▄▄█▄▀▄█ ▄▄▄  ▀ ▄▀██▀ ▀█
▀ ▀   ▀ █ ▀▄  ▀▀█▀▀▀█▄▀
█▀▀▀▀▀█ ▀█  ▄▀▀ █ ▀ █▄▀██
█ ███ █ █▀▄▄▀ █▀███▀█▄██▄
█ ▀▀▀ █ ██  ▀ █▄█ ▄▄▄█▀ █
▀▀▀▀▀▀▀ ▀ ▀ ▀▀▀  ▀ ▀▀▀▀▀▀'

# Track if we're already handling an error to prevent double-trapping
ERROR_HANDLING=false

# Cursor is usually hidden while we install
show_cursor() {
  printf "\033[?25h"
}

# Display truncated log lines from the install log
show_log_tail() {
  if [[ -f $OMARCHY_INSTALL_LOG_FILE ]]; then
    local log_lines=$((TERM_HEIGHT - LOGO_HEIGHT - 35))
    local max_line_width=$((LOGO_WIDTH - 4))

    # Small consoles and large logos can leave this calculation at zero or
    # below, hiding the only useful failure evidence.
    if (( log_lines < 8 )); then
      log_lines=8
    fi

    tail -n $log_lines "$OMARCHY_INSTALL_LOG_FILE" | while IFS= read -r line; do
      if ((${#line} > max_line_width)); then
        local truncated_line="${line:0:$max_line_width}..."
      else
        local truncated_line="$line"
      fi

      gum style "$truncated_line"
    done

    echo
  fi
}

# In explicitly enabled diagnostic images, open the complete log at the
# failure point. The normal installer keeps its existing compact error UI.
show_debug_log() {
  if [[ ${OMARCHY_INSTALL_DEBUG_LOGS:-} != 1 ]]; then
    return
  fi

  echo
  gum style --foreground 3 "AArch64 image debug mode: showing $OMARCHY_INSTALL_LOG_FILE"

  if [[ ! -s $OMARCHY_INSTALL_LOG_FILE ]]; then
    gum style --foreground 1 "No installer log is available at that path."
  elif command -v less &>/dev/null; then
    gum style "Use arrows or Page Up to inspect the failure; press q to return."
    less -R +G -- "$OMARCHY_INSTALL_LOG_FILE" || true
  else
    tail -n 200 -- "$OMARCHY_INSTALL_LOG_FILE" || true
  fi

  echo
}

# Display the failed command or script name
show_failed_script_or_command() {
  if [[ -n ${CURRENT_SCRIPT:-} ]]; then
    gum style "Failed script: $CURRENT_SCRIPT"
  else
    # Truncate long command lines to fit the display
    local cmd="$BASH_COMMAND"
    local max_cmd_width=$((LOGO_WIDTH - 4))

    if ((${#cmd} > max_cmd_width)); then
      cmd="${cmd:0:$max_cmd_width}..."
    fi

    gum style "$cmd"
  fi
}

# Save original stdout and stderr for trap to use
save_original_outputs() {
  exec 3>&1 4>&2
}

# Restore stdout and stderr to original (saved in FD 3 and 4)
# This ensures output goes to screen, not log file
restore_outputs() {
  if [[ -e /proc/self/fd/3 ]] && [[ -e /proc/self/fd/4 ]]; then
    exec 1>&3 2>&4
  fi
}

# Error handler
catch_errors() {
  # Capture the triggering status before any guard or assignment overwrites it.
  local trap_exit_code=$?
  local exit_code=${1:-$trap_exit_code}

  # Prevent recursive error handling
  if [[ $ERROR_HANDLING == "true" ]]; then
    return
  else
    ERROR_HANDLING=true
  fi

  # Remove the temporary installer policy immediately on errors and signals;
  # the EXIT handler repeats this as defense in depth.
  cleanup_chroot_installer_sudoers || true

  stop_log_output
  restore_outputs

  clear_logo
  show_cursor

  gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Omarchy installation stopped!"
  show_log_tail

  gum style "This command halted with exit code $exit_code:"
  show_failed_script_or_command
  show_debug_log

  gum style "$QR_CODE"
  echo
  gum style "Get help from the community via QR code or at https://discord.gg/tXFUdasqhY"

  # Offer options menu
  while true; do
    options=()

    # If online install, show retry first
    if [[ -n ${OMARCHY_ONLINE_INSTALL:-} ]]; then
      options+=("Retry installation")
    fi

    # Add upload option if internet is available
    if ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
      options+=("Upload log for support")
    fi

    # Add remaining options
    options+=("View full log")
    options+=("Exit")

    choice=$(gum choose "${options[@]}" --header "What would you like to do?" --height 6 --padding "1 $PADDING_LEFT")

    case "$choice" in
    "Retry installation")
      bash ~/.local/share/omarchy/install.sh
      break
      ;;
    "View full log")
      if command -v less &>/dev/null; then
        less "$OMARCHY_INSTALL_LOG_FILE"
      else
        tail "$OMARCHY_INSTALL_LOG_FILE"
      fi
      ;;
    "Upload log for support")
      omarchy-upload-log
      ;;
    "Exit" | "")
      exit 1
      ;;
    esac
  done
}

cleanup_installer_sudoers_path() {
  local policy_path=$1

  rm -f -- "$policy_path" || return 1
  [[ ! -e $policy_path ]]
}

# Never leave the ISO's temporary unrestricted sudo policy in the installed
# target, including before the target-side install starts or when a late stage
# fails. The ISO marker is exported before the live helper traps are sourced.
cleanup_chroot_installer_sudoers() {
  local cleanup_failed=0

  if [[ ${OMARCHY_CHROOT_INSTALL:-} == 1 ]]; then
    if [[ -e /etc/sudoers.d/99-omarchy-installer ]]; then
      if ! sudo -n rm -f /etc/sudoers.d/99-omarchy-installer >/dev/null 2>&1 ||
        [[ -e /etc/sudoers.d/99-omarchy-installer ]]; then
        echo "Failed to remove /etc/sudoers.d/99-omarchy-installer" >&2
        cleanup_failed=1
      fi
    fi
  fi

  if [[ ${OMARCHY_ISO_INSTALL:-} == 1 ]]; then
    if ! cleanup_installer_sudoers_path /mnt/etc/sudoers.d/99-omarchy-installer; then
      echo "Failed to remove /mnt/etc/sudoers.d/99-omarchy-installer" >&2
      cleanup_failed=1
    fi
  fi

  return "$cleanup_failed"
}

# Exit handler - ensures cleanup happens on any exit
exit_handler() {
  local exit_code=$?

  local cleanup_exit_code=0
  cleanup_chroot_installer_sudoers || cleanup_exit_code=$?
  if (( exit_code == 0 && cleanup_exit_code != 0 )); then
    exit_code=$cleanup_exit_code
  fi

  # Only run if we're exiting with an error and haven't already handled it
  if (( exit_code != 0 )) && [[ $ERROR_HANDLING != "true" ]]; then
    catch_errors "$exit_code"
  else
    stop_log_output
    show_cursor
  fi

  return "$exit_code"
}

# Set up traps
trap catch_errors ERR INT TERM
trap exit_handler EXIT

# Save original outputs in case we trap
save_original_outputs
