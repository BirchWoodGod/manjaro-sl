# Desktop Setup — Detected Interface & Preset Color Pickers

**Date:** 2026-07-19
**Status:** Approved by user (brainstorming session)

## Problem

Two legacy interactive pickers — network-interface auto-detection
(`ip -o link` numbered menu) and the 15-color theme menu
(Solarized/Nord/Gruvbox) in `lib/configure.sh` — are gated behind
`ACCEPT_DEFAULTS=0`, a path no current entry point reaches. The TUI offers
bare text boxes instead, and the interface box's "blank = auto-detect" hint
is false (blank keeps the current config value).

## Change

### Shared data/helpers in `lib/configure.sh`

- `detect_net_interfaces` — echoes non-lo interface names one per line
  (existing `ip -o link` awk pipeline; ifconfig fallback; empty output when
  neither tool exists). The legacy prompt and the TUI both call it.
- `BAR_PRESETS` — array of `name|hex` pairs (the existing 15 entries,
  verbatim). Legacy prompt and TUI both read it (legacy echo/case blocks
  rewritten to loop over the array so the lists cannot drift).

### Desktop Setup → Network interface (TUI)

Radiolist: one entry per detected interface (current selection pre-marked
when it matches), plus `custom` "Custom…" (tui_input) and `keep`
"Keep current (<value read from slstatus config via the existing sed>)".
Selection → `state_set dwm/interface X`; keep → leave state untouched.
When detection returns nothing, fall back to the tui_input box (without the
false auto-detect claim).

### Desktop Setup → Bar color (TUI)

Radiolist: 15 preset entries labeled `<Name> — <hex>` (current value
pre-selected when it matches a preset hex), plus `custom` "Custom hex…"
(tui_input validated `^#[0-9a-fA-F]{6}$` — invalid input → msgbox + no
state change) and `keep` "Keep current (<hex from dwm config>)".
Selection → `state_set dwm/barcolor "#…"`; keep → untouched.

## Non-changes

State keys, CLI flags, `apply_configuration`, legacy functions' behavior on
their (unreachable) interactive path — all unchanged; legacy blocks now read
the shared array/helper instead of inline literals.

## Testing

- `detect_net_interfaces` unit test with a mocked `ip` function.
- TUI radiolist tests (fallback driving): interface pick lands in
  `dwm/interface`; bar preset pick lands the exact hex in `dwm/barcolor`;
  custom hex `red` rejected (state unchanged), `#a1b2c3` accepted; keep
  leaves state untouched.
- Legacy/TUI preset-list equivalence: assert the legacy function's output
  and the TUI list derive from `BAR_PRESETS` (source-level or behavioral).
- Suite green; README Desktop Setup section updated (detected list +
  presets).
