#!/usr/bin/env bash
# System tweaks: systemd unit enable/disable driven by data/tweaks-services.list.

tweaks_screen() {
  local -a args=()
  local action_unit desc state cur
  while IFS='|' read -r action_unit desc state; do
    cur=$(state_get "tweak/$action_unit")
    [ -n "${SELECTIONS[tweak/$action_unit]:-}" ] && state="$cur"
    args+=("$action_unit" "$desc" "$state")
  done < <(list_entries "$REPO_ROOT/data/tweaks-services.list")
  local chosen; chosen=$(tui_checklist "System Tweaks" "Space toggles, Enter confirms" "${args[@]}") || return 0
  while IFS='|' read -r action_unit desc state; do
    user_set "tweak/$action_unit" off
  done < <(list_entries "$REPO_ROOT/data/tweaks-services.list")
  local tag; for tag in $chosen; do user_set "tweak/$tag" on; done
}

tweaks_apply() {
  local key action unit
  for key in "${!SELECTIONS[@]}"; do
    [[ "$key" == tweak/* ]] && [ "${SELECTIONS[$key]}" = on ] || continue
    action=${key#tweak/}; unit=${action#*:}; action=${action%%:*}
    if [ "$action" = "enable" ] && [ "$unit" = "ufw.service" ]; then
      if ! command -v ufw >/dev/null 2>&1; then
        echo "Warning: ufw not installed; skipping firewall setup." >&2
        continue
      fi
      run_mut sudo: ufw default deny incoming
      run_mut sudo: ufw enable
    fi
    run_mut sudo: systemctl "$action" "$unit"
  done
}
