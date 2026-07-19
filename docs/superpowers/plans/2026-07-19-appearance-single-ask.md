# Appearance Single-Ask Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Appearance's two-question Advanced flow with a single optional "Desktop wallpaper" override item, per `docs/superpowers/specs/2026-07-19-appearance-single-ask-design.md`.

**Architecture:** TUI-only change inside `appearance_menu` (manjaro-sl.sh); state keys, CLI, apply pipeline untouched. Animation gains one refinement: it no longer overwrites an explicit desktop override (`match_wallpaper=off`).

**Tech Stack:** bash 5, existing test runner (255 assertions).

## Global Constraints

- State keys unchanged (`ly/animation`, `dwm/wallpaper`, `ly/match_wallpaper`, `component/*`); CLI unchanged; `sync_ly_wallpaper`/`apply_all`/presets/profiles untouched.
- All wallpaper writes go through `select_wallpaper` (chokepoint).
- bash -n clean; shellcheck absent; suite green; no sudo; sandboxed tests only.

---

### Task 1: Desktop wallpaper override item

**Files:**
- Modify: `manjaro-sl.sh` (appearance_menu only), `tests/lib-tests.sh`, `readme.md`

**Interfaces:**
- Consumes: `select_wallpaper WP`, `ly_animation_to_wallpaper`, `available_wallpapers`, `WALLPAPER_DESCS`, `state_*`, `tui_menu`/`tui_radiolist`.
- Produces: `appearance_menu` with tags `animation wallpaper enable back` (the `advanced` tag/case gone).

- [ ] **Step 1: Failing tests.** In `tests/lib-tests.sh`: (a) update every appearance herestring test that navigates via the `advanced` tag/position — the menu fallback is numbered, so re-derive input sequences for the new 4-item menu (`animation`=1, `wallpaper`=2, `enable`=3, `back`=4) and keep existing assertion OUTCOMES identical; (b) add, using the established `bash -c 'source …/manjaro-sl.sh; …'` + TUI_ACTIVE=0 pattern (document each herestring in a comment):

```bash
# Desktop wallpaper override: animation matrix (match) then override to doomfire
#   → wallpaper=doomfire, match=off, component/doomfire implied
# Then re-pick "match" → wallpaper re-derives to xmatrix, match=on
# Then pick animation doom with match=off (override first) → wallpaper untouched
```

Concretely (adapt numbering to the implemented radiolist order — match is entry 1, none entry 2, then available_wallpapers in registry order, so doomfire=3, xmatrix=4, xcolormix=5, xgameoflife=6, xblackhole=7):

```bash
out=$(TUI_ACTIVE=0 bash -c '
  source "'"$REPO_ROOT"'/manjaro-sl.sh"
  declare -gA SELECTIONS=()
  appearance_menu <<EOF2
1
2
2
3
4
EOF2
  echo "anim=$(state_get ly/animation) wp=$(state_get dwm/wallpaper) match=$(state_get ly/match_wallpaper) comp=$(state_get component/doomfire)"
' 2>/dev/null | tail -1)
assert_contains "$out" "anim=matrix"
assert_contains "$out" "wp=doomfire"
assert_contains "$out" "match=off"
assert_contains "$out" "comp=on"
```

(Input walkthrough: menu 1=Animation → radiolist 2=matrix; menu 2=Desktop wallpaper → radiolist 3=doomfire; menu 4=Back. Adjust if your implemented orders differ — the OUTCOME assertions are normative.) Add the re-match and match-off-animation cases the same way. Update the menu-integrity source assertions: `grep -c 'Advanced'` on the appearance tui_menu call = 0; `Desktop wallpaper` present.

- [ ] **Step 2: Run** — FAIL (advanced still present / wallpaper tag missing).
- [ ] **Step 3: Implement** in `appearance_menu`:
  - Menu call: `animation "Animation"  wallpaper "Desktop wallpaper"  enable "Enable Ly on boot"  back "Back"`.
  - Delete the whole `advanced)` case.
  - New `wallpaper)` case:

```bash
      wallpaper)
        local curw selw effective
        # Pre-select: "match" when match_wallpaper is on or unset; else the
        # current override value.
        if [ -z "${SELECTIONS[ly/match_wallpaper]+x}" ] || state_on ly/match_wallpaper; then
          effective=match
        else
          effective=$(state_get dwm/wallpaper); [ "$effective" = off ] && effective=none
        fi
        local -a wp_args=(
          match "Match login animation (default)" "$([ "$effective" = match ] && echo on || echo off)"
          none  "None"                            "$([ "$effective" = none ] && echo on || echo off)"
        )
        local w
        while IFS= read -r w; do
          wp_args+=("$w" "${WALLPAPER_DESCS[$w]}" "$([ "$effective" = "$w" ] && echo on || echo off)")
        done < <(available_wallpapers)
        selw=$(tui_radiolist "Desktop wallpaper" "Override the desktop wallpaper, or keep it matched to the login animation" \
          "${wp_args[@]}") || continue
        if [ "$selw" = match ]; then
          state_set ly/match_wallpaper on
          select_wallpaper "$(ly_animation_to_wallpaper "$(state_get ly/animation)")"
        else
          select_wallpaper "$selw"
          state_set ly/match_wallpaper off
        fi
        ;;
```

  - Animation refinement — in BOTH the fixed and Custom… branches, wrap the wallpaper-derivation lines (`select_wallpaper …` + `state_set ly/match_wallpaper on` + the Custom… msgboxes) in:

```bash
        if [ -n "${SELECTIONS[ly/match_wallpaper]+x}" ] && ! state_on ly/match_wallpaper; then
          : # explicit desktop override active — leave dwm/wallpaper alone
        else
          <existing derivation lines>
        fi
```

    (`state_set ly/animation …` always runs, outside the guard.)
- [ ] **Step 4: GREEN** — full suite (`bash tests/run-tests.sh`), `bash -n manjaro-sl.sh`, `./manjaro-sl.sh --help` exit 0, sandboxed `--preset recommended --dry-run --apply` exit 0.
- [ ] **Step 5: README** — Appearance section: three-item screen, the override semantics ("Match login animation" default; picking a specific wallpaper decouples; re-picking Match re-couples), delete the Advanced two-step description and the "Advanced list doesn't include gameoflife" caveat (no longer applicable — the item is gone).
- [ ] **Step 6: Commit** — `feat: single-ask Appearance — desktop wallpaper override replaces Advanced`
