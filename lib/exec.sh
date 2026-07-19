#!/usr/bin/env bash
# Mutation gate, step harness, and logging for manjaro-sl.
# Every command that changes system state goes through run_mut so that
# --dry-run can print instead of execute.

DRY_RUN=${DRY_RUN:-0}
# M3: normalize any inherited/exported DRY_RUN value that isn't a clean 0/1
# (e.g. `DRY_RUN=true`, garbage from a caller's environment) — treat unknown
# truthy strings as dry (1), never as live (0). This is the conservative
# direction: an unrecognized value must never accidentally let mutating
# commands execute for real.
case "$DRY_RUN" in
  0|1) ;;
  ""|0*) DRY_RUN=0 ;;
  *) DRY_RUN=1 ;;
esac

log_dir() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/manjaro-sl"
  mkdir -p "$d"
  echo "$d"
}

# run_mut CMD ARGS...
# Prefix "sudo:" as $1 to request privilege (uses run_with_privilege if the
# caller has defined it, else sudo).
run_mut() {
  local priv=0
  if [ "${1:-}" = "sudo:" ]; then priv=1; shift; fi
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$priv" -eq 1 ]; then echo "+ sudo $*"; else echo "+ $*"; fi
    return 0
  fi
  if [ "$priv" -eq 1 ]; then
    if declare -F run_with_privilege >/dev/null; then
      run_with_privilege "$@"
    else
      sudo "$@"
    fi
  else
    "$@"
  fi
}

# run_step "Title" fn — run fn, tee output to the run log; on failure offer
# View log / Continue / Abort (falls back to plain prompt without whiptail).
RUN_LOG=""
run_step() {
  local title="$1" fn="$2"
  if [ -z "$RUN_LOG" ]; then
    RUN_LOG="$(log_dir)/run-$(date +%Y%m%d%H%M%S).log"
  fi
  echo "==> ${title}" | tee -a "$RUN_LOG"
  "$fn" 2>&1 | tee -a "$RUN_LOG"
  local rc=${PIPESTATUS[0]}
  if [ "$rc" -eq 0 ]; then
    return 0
  fi
  echo "Step '${title}' failed (exit $rc). Log: $RUN_LOG" >&2
  if declare -F tui_yesno >/dev/null && [ "${TUI_ACTIVE:-0}" -eq 1 ]; then
    if tui_yesno "Step failed" "Step '${title}' failed.\nLog: ${RUN_LOG}\n\nContinue with remaining steps?"; then
      return 0
    fi
    return "$rc"
  fi
  local ans
  read -r -p "Continue with remaining steps? [y/N] " ans || ans=""
  [[ "$ans" =~ ^[Yy] ]] && return 0
  return "$rc"
}
