#!/usr/bin/env bash
# Optional AUR builds — the project's single sanctioned AUR exception
# (see data/aur-optional.list). makepkg runs as the invoking user; sudo
# happens only inside makepkg's install step.
#
# Package-name note: the AUR package literally named "cde" is CDEpack (an
# unrelated portable-app packaging tool by pgbovine) — NOT the Common
# Desktop Environment. Verified 2026-07-19 by fetching
# https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=cde (pkgdesc
# "Automatically create portable Linux applications (formerly CDEpack)").
# The real CDE port is packaged as "cdesktopenv" (maintainer PlasticSoup,
# pkgdesc "The Common Desktop Environment, the classic UNIX desktop") —
# that PKGBUILD was also fetched and confirms the package installs its own
# /usr/share/xsessions/cde.desktop entry (Exec via a generated
# /usr/bin/startcdesession.sh) under an /usr/dt prefix, not /opt/dt. See
# aur_session_check below for how that shapes the fallback.

aur_screen() {
  local -a args=()
  local name desc state cur
  while IFS='|' read -r name desc state; do
    cur=$(state_get "aur/$name")
    [ -n "${SELECTIONS[aur/$name]:-}" ] && state="$cur"
    args+=("$name" "$desc" "$state")
  done < <(list_entries "$REPO_ROOT/data/aur-optional.list")
  local chosen; chosen=$(tui_checklist "Extra software (AUR)" \
    "Source builds from the AUR — slow, user-maintained" "${args[@]}") || return 0
  while IFS='|' read -r name desc state; do user_set "aur/$name" off; done \
    < <(list_entries "$REPO_ROOT/data/aur-optional.list")
  local tag; for tag in $chosen; do user_set "aur/$tag" on; done
}

aur_apply() {
  local key name any=0
  for key in "${!SELECTIONS[@]}"; do
    [[ "$key" == aur/* ]] && [ "${SELECTIONS[$key]}" = on ] || continue
    any=1
    name=${key#aur/}
    local dir="$HOME/.cache/manjaro-sl/aur/$name"
    run_mut mkdir -p "$dir"
    run_mut curl -fsSL "https://aur.archlinux.org/cgit/aur.git/snapshot/${name}.tar.gz" -o "$dir/${name}.tar.gz"
    run_mut tar -xzf "$dir/${name}.tar.gz" -C "$dir" --strip-components=1
    # DRY_RUN: $dir was never really created by the mkdir above, so `cd`
    # fails — the `|| [ "$DRY_RUN" -eq 1 ]` keeps this a non-error under
    # `set -e` (inherited into the subshell) so `run_mut makepkg` still
    # runs and prints its "+" line. Live run: $dir genuinely exists (mkdir
    # -p ran for real), so `cd` succeeds normally; if it doesn't (e.g. the
    # fetch/extract silently produced nothing), the whole statement fails
    # and `set -e` aborts the subshell before makepkg ever runs for real —
    # exactly the fail-closed behavior we want.
    ( cd "$dir" 2>/dev/null || [ "$DRY_RUN" -eq 1 ] ; run_mut makepkg -si --noconfirm --needed )
    aur_session_check "$name"
  done
  [ "$any" -eq 0 ] && echo "No AUR software selected."
  return 0
}

# apply_all wraps aur_apply in this: AUR builds need base-devel (installed
# by the Install-packages step, data/install-core.list), so if that step
# was skipped (--skip-packages) there's no guarantee a build toolchain is
# present — skip AUR builds too rather than let makepkg fail confusingly,
# mirroring the [dry-run]-skip note style used elsewhere (see
# manjaro-sl.sh's dry_run_note) for a different gating condition.
aur_apply_maybe() {
  if [ "${SKIP_PACKAGES:-0}" -eq 1 ]; then
    echo "[skip-packages] skipping AUR builds (base-devel install was skipped)"
    return 0
  fi
  aur_apply
}

# After installing NAME, make sure a login-session entry exists so Ly can
# offer it. Only cdesktopenv is special-cased today.
aur_session_check() {
  local name="$1"
  [ "$name" = cdesktopenv ] || return 0
  ls /usr/share/xsessions/*.desktop 2>/dev/null | grep -qi cde && return 0
  [ "$DRY_RUN" -eq 1 ] && { echo "+ install cde.desktop session entry"; return 0; }
  # Fallback only: cdesktopenv's own PKGBUILD already installs
  # /usr/share/xsessions/cde.desktop (Exec via the package's generated
  # /usr/bin/startcdesession.sh under its /usr/dt prefix), so this branch
  # should rarely run on a clean build. If it's missing anyway (partial or
  # broken build), point at that same real launcher rather than guessing —
  # this port does NOT use the traditional /opt/dt/bin/Xsession path.
  printf '[Desktop Entry]\nName=CDE\nComment=Common Desktop Environment\nExec=/usr/bin/startcdesession.sh\nType=Application\n' \
    | run_with_privilege tee /usr/share/xsessions/cde.desktop >/dev/null
}
