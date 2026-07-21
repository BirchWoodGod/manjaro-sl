# CLAUDE.md

Guidance for working in this repo. See `readme.md` for the full user-facing docs.

## What this is

`manjaro-sl` is a whiptail TUI (plus a non-interactive flag/profile mode) that
**installs and customizes a dwm/suckless desktop with a Ly display manager** on
Manjaro / Arch-based systems. It installs packages from the official repos,
compiles the vendored suckless tools from source, sets up Ly, and wires up an
optional animated X11 root-window wallpaper.

It is **not** a debloater. The Manjaro-debloat and System-Tweaks features, the
interactive Presets menu, and the optional CDE/AUR component were removed — do
not reintroduce that surface. (Presets themselves still exist, CLI-only, via
`--preset`; NetworkManager enablement was folded into the install path.)

## Entry point & running

- `./manjaro-sl.sh` — interactive TUI. With flags, builds up the same selection
  state and (with `--apply`/`-y`) applies it non-interactively.
- `bash tests/run-tests.sh` — the whole test suite (sources `tests/*-tests.sh`).
  Run this after any change; it must stay green. Some tests are host-coupled and
  expect to run on the target Manjaro machine.
- `./manjaro-sl.sh --help` — authoritative flag list (kept in sync by tests).
- `./manjaro-sl.sh --preset recommended -y --dry-run` — safe end-to-end preview.

## Architecture

`manjaro-sl.sh` is the orchestrator (arg parsing, TUI menus, the apply
pipeline). Behavior lives in `lib/*.sh`, sourced in this order:
`exec state tui` (side-effect-free, sourced before `-h/--help` handling) then
`common packages suckless configure ly wallpaper`.

- `lib/exec.sh` — `run_mut` (the mutation gate: prints instead of executing
  under `DRY_RUN=1`), `run_step` (per-step logging + continue/abort on failure),
  `log_dir`.
- `lib/state.sh` — the `SELECTIONS` associative array is the single source of
  truth (`state_set/get/on`, `user_set` marks a key USER_TOUCHED so baseline
  presets skip it). `list_entries` parses `data/*.list`. `preset_apply`.
- `lib/tui.sh` — `tui_menu/radiolist/checklist/input/yesno/msgbox`, with
  plain-text fallbacks used when `TUI_ACTIVE=0` (all tests run this path).
- `lib/packages.sh` — package lists + `ensure_recommended_packages`,
  `ensure_multilib_repo_enabled`, `ensure_networkmanager_enabled`.
- `lib/suckless.sh` — component build (`build_components`, wallpaper/extra
  registries `KNOWN_WALLPAPERS`, `EXTRA_COMPONENTS`).
- `lib/configure.sh` — edits the vendored `config.h`s (modkey, bar color,
  slstatus interface + battery) via embedded python; interface auto-detect.
- `lib/ly.sh` — Ly config/enable, animation writing, DM-conflict disabling
  (`KNOWN_DISPLAY_MANAGERS`).
- `lib/wallpaper.sh` — generates `~/.config/manjaro-sl/wallpaper.sh` and wires a
  marked block into `~/.xinitrc`.

## Selection state & apply pipeline

Every TUI screen and every flag just writes keys into `SELECTIONS`, namespaced:
`component/*`, `install/*`, `dwm/*` (modkey, barcolor, interface, battery,
wallpaper), `ly/*` (enable, animation, match_wallpaper). Presets and
`detect_existing_setup` prefill it; `preview_text` renders it; `apply_all`
consumes it.

`apply_all` runs a fixed order, each step via `run_step`:
**Configure → Install packages → Enable networking → Build components → Ly →
Wallpaper → save profile**. Gating:
- `section_enabled` implements `--only install|dwm|ly` (Configure/Wallpaper are
  `dwm`; Install/networking/Build are `install`; Ly is `ly`).
- Install packages **and** Enable networking are additionally gated by
  `--skip-packages`.
- The Ly step is gated by `ly_step_should_run` so a bare per-component rebuild
  (e.g. `./manjaro-sl.sh st -y`) doesn't flip the system's display manager.
- Configure runs **before** Build on purpose — `config.h` edits are compiled in.

## Data files

- `data/install-core.list` — always installed (build toolchain + xorg/xinit/ly/
  python/libnewt).
- `data/install-recommended.list` — extras (feh, firefox, htop, nm-applet, …),
  on under `--preset recommended`, off under `minimal`, and the only targets of
  `--enable-SLUG` / `--disable-SLUG`.

Suckless sources are vendored top-level dirs (`dwm/`, `dmenu/`, `st/`,
`slstatus/`, the `x*`/`doomfire` wallpapers, `drv/`). `misc0/` holds the
`xinitrc-config.txt` template and `dwm.desktop`.

## Conventions

- Bash with `set -euo pipefail`. Route every mutating command through
  `run_mut sudo: …` so `--dry-run` stays safe. Build/Configure/Ly/Wallpaper
  write files directly, so their `*_maybe` wrappers skip entirely under
  `--dry-run` with a `[dry-run] skipping <step>` note (they are not simulated).
- Keep `usage()`, `readme.md`, and `tests/lib-tests.sh` in sync with any
  menu/flag/behavior change — several tests assert menu structure and `--help`
  contents statically.
- Prefer editing `config.h` via the existing python snippets in
  `lib/configure.sh` rather than sed/awk.

## Git

Repo history uses `birchwoodgod <birchwoodgod@gmail.com>` (set repo-locally).
Work on a branch; commit/push only when asked.
