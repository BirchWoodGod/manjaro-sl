#!/usr/bin/env bash
# Shared helpers: privilege escalation, prompts, backups.

# Determine privilege escalation command if needed.
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  SUDO_CMD=()
else
  if command -v sudo >/dev/null 2>&1; then
    SUDO_CMD=(sudo)
  else
    echo "Error: sudo not found. Run this script as root or install sudo." >&2
    exit 1
  fi
fi

# Running the whole script under sudo makes $HOME point at /root, so per-user
# files like ~/.xinitrc would land in the wrong place.
if [ "${EUID:-$(id -u)}" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
  echo "Warning: running under sudo; files like ~/.xinitrc will be installed to /root." >&2
  echo "Run this script as your normal user instead (it uses sudo only where needed)." >&2
fi

run_with_privilege() {
  if [ ${#SUDO_CMD[@]} -gt 0 ]; then
    "${SUDO_CMD[@]}" "$@"
  else
    "$@"
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' not found. $2" >&2
    exit 1
  fi
}

prompt_yes_no() {
  local prompt="$1"
  local default_answer="$2"
  local response
  local suffix=""

  case "$default_answer" in
    y|Y)
      suffix="[Y/n]"
      ;;
    n|N)
      suffix="[y/N]"
      ;;
    *)
      suffix="[y/n]"
      ;;
  esac

  while true; do
    read -r -p "$prompt $suffix " response || response=""
    response=${response:-$default_answer}
    case "$response" in
      y|Y)
        return 0
        ;;
      n|N)
        return 1
        ;;
      *)
        echo "Please answer y or n." >&2
        ;;
    esac
  done
}

copy_with_backup() {
  local source="$1"
  local destination="$2"
  local use_privilege="$3"
  local mode="${4:-644}"

  if [ ! -e "$source" ]; then
    echo "Warning: source file '$source' not found, skipping copy." >&2
    return
  fi

  local timestamp
  timestamp=$(date +%Y%m%d%H%M%S)
  if [ -e "$destination" ]; then
    local backup="${destination}.${timestamp}.bak"
    if [ "$use_privilege" = "yes" ]; then
      run_with_privilege cp "$destination" "$backup"
    else
      cp "$destination" "$backup"
    fi
    echo "Existing $(basename "$destination") backed up to ${backup}."
  fi

  if [ "$use_privilege" = "yes" ]; then
    run_with_privilege install -Dm"$mode" "$source" "$destination"
  else
    install -Dm"$mode" "$source" "$destination"
  fi
  echo "Installed $(basename "$source") to ${destination}."
}
