#!/usr/bin/env bash
# Debloat engine: category screens generated from data files, removal with
# denylist enforcement, DM-safe disabling, and removal logging.

# Echo entries from FILE whose package is currently installed.
debloat_installed_from() {
  local line name
  while IFS= read -r line; do
    name=${line%%|*}
    if pacman -Qq "$name" >/dev/null 2>&1; then
      echo "$line"
    fi
  done < <(list_entries "$1")
}

# Show a checklist for CATEGORY from FILE; store results in SELECTIONS.
debloat_screen() {
  local category="$1" file="$2"
  local -a args=()
  local line name desc state cur
  while IFS='|' read -r name desc state; do
    cur=$(state_get "debloat/$name")
    # SELECTIONS wins over file default once user has visited any screen
    [ -n "${SELECTIONS[debloat/$name]:-}" ] && state="$cur"
    args+=("$name" "$desc" "$state")
  done < <(debloat_installed_from "$file")
  if [ ${#args[@]} -eq 0 ]; then
    tui_msgbox "$category" "Nothing from this category is installed."
    return 0
  fi
  local chosen; chosen=$(tui_checklist "$category" "Space toggles, Enter confirms" "${args[@]}") || return 0
  # reset every entry in this file to off, then re-mark chosen
  while IFS='|' read -r name desc state; do user_set "debloat/$name" off; done \
    < <(debloat_installed_from "$file")
  local tag; for tag in $chosen; do user_set "debloat/$tag" on; done
}

debloat_collect() {
  local key
  for key in "${!SELECTIONS[@]}"; do
    [[ "$key" == debloat/* ]] && [ "${SELECTIONS[$key]}" = on ] && echo "${key#debloat/}"
  done
}

debloat_apply() {
  local -a to_remove=()
  local pkg
  while IFS= read -r pkg; do
    if denylisted "$pkg"; then
      echo "REFUSED (denylist): $pkg"
      continue
    fi
    to_remove+=("$pkg")
  done < <(debloat_collect | sort)
  [ ${#to_remove[@]} -eq 0 ] && { echo "Nothing selected for removal."; return 0; }

  # Disable (never stop) any DM being removed — black-screen safety.
  local dm
  for dm in "${KNOWN_DISPLAY_MANAGERS[@]:-}"; do
    for pkg in "${to_remove[@]}"; do
      if [ "$pkg" = "$dm" ]; then
        echo "Disabling ${dm}.service (takes effect next boot)"
        run_mut sudo: systemctl disable "${dm}.service" || true
      fi
    done
  done

  local logf; logf="$(log_dir)/removed-$(date +%Y%m%d%H%M%S).log"
  if [ "$DRY_RUN" -eq 0 ]; then
    pacman -Q "${to_remove[@]}" > "$logf" 2>/dev/null || true
    echo "Removal list logged to $logf"
  fi

  # Mirrors lib/packages.sh's install path: ACCEPT_DEFAULTS=1 (non-interactive
  # -y/--apply runs) means no one is at the terminal to answer pacman's
  # confirmation prompt, so pass --noconfirm the same way installs do.
  local -a pacman_cmd=(pacman -Rns)
  [ "${ACCEPT_DEFAULTS:-0}" -eq 1 ] && pacman_cmd+=(--noconfirm)
  pacman_cmd+=("${to_remove[@]}")
  run_mut sudo: "${pacman_cmd[@]}"
}
