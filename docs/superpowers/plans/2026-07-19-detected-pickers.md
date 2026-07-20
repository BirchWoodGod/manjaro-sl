# Detected Interface & Preset Color Pickers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface the dead legacy interface-detection and theme-color pickers as Desktop Setup radiolists, per `docs/superpowers/specs/2026-07-19-detected-pickers-design.md`.

**Architecture:** Shared data/helpers in `lib/configure.sh` (`detect_net_interfaces`, `BAR_PRESETS`) consumed by both the legacy prompts (rewritten to loop the shared data — behavior identical) and two new TUI radiolists in `desktop_setup_menu`. State keys/CLI/apply untouched.

**Tech Stack:** bash 5, existing test runner (276 assertions).

## Global Constraints

- State keys unchanged (`dwm/interface`, `dwm/barcolor`); CLI unchanged; `apply_configuration` untouched.
- Legacy `configure_slstatus_interface` / `configure_dwm_bar_color` keep IDENTICAL behavior on their interactive path (same prompts, same numbering, same choices) — they just source the shared array/helper.
- bash -n clean; shellcheck absent; suite green; no sudo; sandboxed/mocked tests only.

---

### Task 1: Shared helpers + both TUI radiolists

**Files:**
- Modify: `lib/configure.sh`, `manjaro-sl.sh` (desktop_setup_menu: `interface)` and `barcolor)`-equivalent cases — grep the current case names first), `tests/lib-tests.sh`, `readme.md`

**Interfaces:**
- Produces in `lib/configure.sh`:
  - `detect_net_interfaces` — echoes non-lo interface names, one per line; `ip -o link show | awk -F': ' '{print $2}' | cut -d'@' -f1 | grep -v '^lo$'` when `ip` exists, the existing ifconfig pipeline as fallback, empty output otherwise (never errors).
  - `BAR_PRESETS` — indexed array of `Name|#hex` strings, the 15 existing entries verbatim in the legacy menu's order: `"Solarized Blue|#268bd2" "Solarized Cyan|#2aa198" "Solarized Green|#859900" "Solarized Yellow|#b58900" "Solarized Orange|#cb4b16" "Solarized Red|#dc322f" "Solarized Magenta|#d33682" "Solarized Violet|#6c71c4" "Nord Blue|#5e81ac" "Nord Red|#bf616a" "Nord Green|#a3be8c" "Nord Yellow|#ebcb8b" "Gruvbox Blue|#458588" "Gruvbox Red|#cc241d" "Gruvbox Green|#98971a"`.
  - `slstatus_current_interface` — echoes the current value via the existing sed over `slstatus/config.h` (fallback `config.def.h`); `dwm_current_barcolor` — likewise via the existing `col_accent` sed over `dwm/config.h`/`config.def.h`. (Extract these two reads from the legacy functions into the helpers and have the legacy functions call them — pure extraction.)

- [ ] **Step 1: Failing tests** (append to `tests/lib-tests.sh`):

```bash
# detect_net_interfaces with mocked ip
ip() { [ "$1" = "-o" ] && printf '1: lo: <LOOPBACK>\n2: enp14s0: <UP>\n3: wlan0: <UP>\n'; }
ifaces=$(detect_net_interfaces | tr '\n' ' ')
assert_eq "$ifaces" "enp14s0 wlan0 "
unset -f ip

# BAR_PRESETS: 15 entries, name|#hex shape
assert_eq "${#BAR_PRESETS[@]}" "15"
for p in "${BAR_PRESETS[@]}"; do
  case "$p" in *"|#"??????) ;; *) assert_eq "bad-preset:$p" "name|#RRGGBB" ;; esac
done
```

TUI tests (fallback-driven, model on the existing desktop_setup_menu test blocks — read them first; document the herestrings; mock `ip` inside the bash -c subshell for determinism):

```bash
# interface radiolist: picking the 2nd detected interface lands in state
# (menu: Desktop Setup item number for interface — verify against implementation)
# radiolist order: detected ifaces (enp14s0=1, wlan0=2), custom, keep
# → expect dwm/interface=wlan0
# bar color: picking preset 10 (Nord Red) → dwm/barcolor=#bf616a
# custom hex "red" → msgbox path, state unchanged; "#a1b2c3" → accepted
# keep → state untouched (key absent)
```

Write these as real assertions following the established `bash -c 'source …; declare -gA SELECTIONS=(); desktop_setup_menu <<EOF … EOF; echo "…state_get…"'` pattern.

- [ ] **Step 2: Run** — FAIL (helpers undefined).
- [ ] **Step 3: Implement `lib/configure.sh`:** add `BAR_PRESETS`, `detect_net_interfaces`, `slstatus_current_interface`, `dwm_current_barcolor` at top; rewrite the legacy interface-detection while-loops to `while read -r iface; do interfaces+=("$iface"); done < <(detect_net_interfaces)` (identical output); rewrite the legacy color menu's 15 echo lines + 15 case arms as a loop over `BAR_PRESETS` printing the same `N) Name    #hex` lines and resolving choices by index (verify the printed text matches the old format closely — column alignment may simplify to single-space; that's acceptable, prompts/numbering/choices must be identical).
- [ ] **Step 4: Implement the TUI cases** in `desktop_setup_menu`:

```bash
      interface)
        local cur sel
        cur=$(state_get dwm/interface); [ "$cur" = off ] && cur=""
        local shown_cur; shown_cur=$(slstatus_current_interface)
        local -a if_args=()
        local iface
        while IFS= read -r iface; do
          if_args+=("$iface" "detected" "$([ "$iface" = "$cur" ] && echo on || echo off)")
        done < <(detect_net_interfaces)
        if [ ${#if_args[@]} -eq 0 ]; then
          sel=$(tui_input "Network interface" "No interfaces detected; enter one" "$cur") || continue
          [ -n "$sel" ] && state_set dwm/interface "$sel"
          continue
        fi
        if_args+=(custom "Custom…" off keep "Keep current (${shown_cur:-unknown})" "$([ -z "$cur" ] && echo on || echo off)")
        sel=$(tui_radiolist "Network interface" "slstatus netspeed interface" "${if_args[@]}") || continue
        case "$sel" in
          keep|"") ;;
          custom)
            sel=$(tui_input "Network interface" "Interface name" "$cur") || continue
            [ -n "$sel" ] && state_set dwm/interface "$sel"
            ;;
          *) state_set dwm/interface "$sel" ;;
        esac
        ;;
```

```bash
      barcolor)   # ← use the actual existing case name for the color item
        local cur sel
        cur=$(state_get dwm/barcolor); [ "$cur" = off ] && cur=""
        local shown_cur; shown_cur=$(dwm_current_barcolor)
        local -a c_args=()
        local p name hex
        for p in "${BAR_PRESETS[@]}"; do
          name=${p%%|*}; hex=${p#*|}
          c_args+=("$hex" "$name — $hex" "$([ "$hex" = "$cur" ] && echo on || echo off)")
        done
        c_args+=(custom "Custom hex…" off keep "Keep current (${shown_cur:-unknown})" "$([ -z "$cur" ] && echo on || echo off)")
        sel=$(tui_radiolist "Bar color" "dwm selected-bar background" "${c_args[@]}") || continue
        case "$sel" in
          keep|"") ;;
          custom)
            sel=$(tui_input "Bar color" "Hex color (#RRGGBB)" "$cur") || continue
            if [[ "$sel" =~ ^#[0-9a-fA-F]{6}$ ]]; then
              state_set dwm/barcolor "$sel"
            elif [ -n "$sel" ]; then
              tui_msgbox "Bar color" "'$sel' is not a valid #RRGGBB hex color — keeping the previous setting."
            fi
            ;;
          *) state_set dwm/barcolor "$sel" ;;
        esac
        ;;
```

Adapt surrounding structure (the current cases may be inside the same tui_menu loop — replace their bodies, keep the case names/menu labels).

- [ ] **Step 5: GREEN** — full suite; `bash -n`; `--help` exit 0; sandboxed `--preset recommended --dry-run --apply` exit 0.
- [ ] **Step 6: README** — Desktop Setup section: interface entry now lists detected interfaces (via `ip`) with Custom/Keep; bar color offers the 15 Solarized/Nord/Gruvbox presets + custom hex + keep. Remove any "blank = auto-detect" claim if the README repeats it (grep).
- [ ] **Step 7: Commit** — `feat: detected-interface and preset-color radiolists in Desktop Setup`
