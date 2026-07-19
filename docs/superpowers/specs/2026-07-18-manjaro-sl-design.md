# manjaro-sl — Design Spec

**Date:** 2026-07-18
**Status:** Approved by user (brainstorming session)

## Purpose

Reposition the `sl` repository as **manjaro-sl**: a personal customized DWM
desktop setup **and** an opinionated Manjaro Linux debloating tool, driven by a
WinUtil-inspired (Chris Titus) terminal UI. The script must also serve as a
**reconfiguration tool** on machines that already ran it (change Ly animation,
bar color, modkey, wallpaper, etc. after the fact).

## Naming

- Repository: `BirchWoodGod/sl` → `BirchWoodGod/manjaro-sl` (renamed on GitHub
  first, then local remote updated).
- Entry point script: `manjaro-sl.sh`.
- `build_suckless.sh` becomes a thin deprecated wrapper:
  `exec ./manjaro-sl.sh --only install "$@"` (keeps old docs/muscle memory
  working; prints a deprecation notice).

## Scope decisions (from Q&A)

1. **Debloat scope:** all categories, user-selectable per run (Manjaro-branded
   bloat, preinstalled apps, printing stack, bluetooth stack, old DE/DM,
   optional service disabling).
2. **UI:** whiptail (`libnewt`) terminal TUI — works from a fresh TTY before X
   exists. No GUI dependency. Arrow keys + space to toggle, WinUtil-style
   categories as menu screens with checkbox lists.
3. **Presets:** two — **Recommended** and **Minimal** (see Presets section).
4. **Organization:** sourced modules in `lib/` + plain data files in `data/`.
5. **Wallpaper:** build Ly-style procedural animations **from scratch** as
   suckless-style C programs painting the X11 root window. Phase 1: `doomfire`.
   Phase 2: `xmatrix`, `colormix`.

## Repo layout

```
manjaro-sl/
├── manjaro-sl.sh            # entry point: arg parsing, sanity checks, main menu loop
├── build_suckless.sh        # deprecated wrapper → manjaro-sl.sh --only install
├── lib/
│   ├── tui.sh               # whiptail wrappers (menu, checklist, radiolist, msgbox, input)
│   ├── state.sh             # SELECTIONS assoc array, preset loading, profile save/load
│   ├── packages.sh          # install engine, multilib enable, pacman group handling
│   ├── debloat.sh           # removal engine, denylist check, DM/DE detection, logging
│   ├── suckless.sh          # clean/build/install dwm, dmenu, st, slstatus, j4, doomfire
│   ├── configure.sh         # config.h edits (modkey, colors, interface, battery)
│   ├── ly.sh                # Ly service/animation config (modularized from existing)
│   ├── wallpaper.sh         # wallpaper launcher generation + xinitrc wiring
│   └── tweaks.sh            # systemd service enable/disable
├── data/                    # package/category lists (see Data files)
├── dwm/ dmenu/ st/ slstatus/  # existing, unchanged
├── doomfire/                # new: main.c, config.def.h, config.mk, Makefile
├── misc0/                   # existing helper files
└── docs/superpowers/specs/  # this spec + future plans
```

Existing tested logic (multilib enabler, python config.h editors, Ly unit
detection, DE-removal safety dance) is **moved, not rewritten** — the
modularization is a cut-and-paste refactor keeping function names.

## TUI structure

Main menu (whiptail menu; re-entrant — selections stack across screens):

1. **Reconfigure existing setup** — detects prior state, pre-fills selections
2. **Install DWM & Suckless Tools** — checklist: dwm, dmenu, st, slstatus, doomfire
3. **Debloat Manjaro** — submenu of category checklists (see Data files)
4. **Configure DWM** — modkey (radiolist), bar color (themes + custom hex),
   wallpaper animation (radiolist: none / doomfire / [phase-2 stubs]),
   battery widget, network interface (auto-detected)
5. **System Tweaks** — checklist of systemd toggles
6. **Ly Display Manager** — enable on boot, animation (doom/matrix/colormix/none),
   "match dwm wallpaper" checkbox (mirrors Ly animation choice to dwm wallpaper)
7. **Apply Preset** — radiolist: Recommended / Minimal
8. **Preview & Apply** — summary of every queued action, final confirm, execute
9. **Quit**

Missing whiptail: offer `sudo pacman -S libnewt`, else fall back to the current
numbered-prompt style.

**State model:** one bash associative array `SELECTIONS` in `lib/state.sh`.
Presets pre-populate it; screens edit it; Preview reads it; Apply executes it.

**Reconfigure mode:** reads current values from `dwm/config.h`,
`slstatus/config.h`, `/etc/ly/config.ini`, `~/.xinitrc` and pre-checks the UI
to match. Changes overwrite with backups (existing `copy_with_backup` pattern).

**Profile save/load:** on Apply, selections are saved to
`~/.config/manjaro-sl/profile`; a later run can reload it (reproduce setup on
another machine by copying the file).

## Non-interactive mode

All existing flags preserved (`-y`, `--interface`, `--battery/--no-battery`,
`--bar-color`, `--modkey`, `--copy-xinit/--no-copy-xinit`,
`--copy-desktop/--no-copy-desktop`, `--remove-de/--no-remove-de`,
`--skip-packages`). New flags:

- `--preset recommended|minimal`
- `--only install|debloat|tweaks|dwm|ly` (repeatable)
- `--wallpaper none|doomfire`
- `--profile FILE` (load saved profile)
- `--dry-run` (print every pacman/systemctl command instead of executing)

Every checklist item gets a `--enable-<slug>` / `--disable-<slug>` pair
generated from the data files.

## Data files

Format: one entry per line — `name|TUI description|default_state` where
default_state (`on`/`off`) is the checkbox state when **no preset** is active;
applying a preset overrides it per the Presets table below. `#` comments
allowed. Screens
are generated from these files and **filtered against `pacman -Q`** (only
installed packages are offered for removal; only missing ones for install).

- `install-core.list` — always installed, not optional: `base-devel libx11
  libxft libxinerama freetype2 fontconfig pkgconf python libnewt xorg
  xorg-xinit ly`
- `install-recommended.list` — `feh meson fastfetch htop nano networkmanager
  network-manager-applet tldr brightnessctl alsa-utils firefox net-tools`
- `debloat-manjaro.list` — `manjaro-hello manjaro-application-utility
  manjaro-settings-manager manjaro-settings-manager-notifier
  manjaro-browser-settings manjaro-documentation-en pamac-gtk pamac-gtk3
  pamac-cli pamac-tray-icon-plasma libpamac libpamac-flatpak-plugin
  manjaro-wallpapers-* manjaro-icons grub-theme-manjaro (cosmetic ones
  unchecked by default) manjaro-zsh-config (UNCHECKED both presets + warning:
  strips zsh/powerlevel10k setup)`
- `debloat-apps.list` — `thunderbird hexchat pidgin gimp inkscape
  libreoffice-still libreoffice-fresh onlyoffice-desktopeditors steam
  steam-devices lollypop totem celluloid gnome-maps cheese kget konversation
  parole timeshift (UNCHECKED both + warning: backup system)
  timeshift-autosnap-manjaro (UNCHECKED both + warning)`
- `debloat-printing.list` — `cups cups-pdf cups-filters hplip
  system-config-printer simple-scan sane print-manager manjaro-printer`
- `debloat-bluetooth.list` — `bluez bluez-utils blueman bluedevil
  pulseaudio-bluetooth blueberry`
- `tweaks-services.list` — enable `NetworkManager.service` (on), enable
  `fstrim.timer` (on), disable `cups.service` (off), disable
  `bluetooth.service` (off), enable `ufw.service` + default deny (off)
- `dm.list` / `de.list` — known display managers / desktop environments
  (moved verbatim from the current script arrays)

### Presets

| Category | Recommended | Minimal |
|---|---|---|
| install-recommended | all checked | all unchecked |
| debloat-manjaro | checked, **except pamac\* unchecked**, cosmetics unchecked | all checked (except denylist-adjacent warnings) |
| debloat-apps | unchecked | checked (except timeshift*) |
| debloat-printing | unchecked | unchecked |
| debloat-bluetooth | unchecked | unchecked |
| old DE/DM removal | prompt | checked |
| tweaks | NetworkManager+fstrim on | NetworkManager+fstrim on |
| wallpaper | doomfire matching Ly | none |

### Hardcoded denylist (checked by the engine before every removal batch)

`manjaro-system manjaro-keyring archlinux-keyring manjaro-alsa
manjaro-gstreamer manjaro-pipewire mhwd mhwd-db mhwd-* pacman pacman-mirrors
sudo systemd base filesystem linux* networkmanager` — the engine refuses these
even if a data file lists them.

### Debloat safety rails

1. Denylist check (above) before every batch.
2. Running DM is never stopped — only disabled (existing black-screen-safe
   dance preserved).
3. `pacman -Rns` only, never `-Rdd`; dependency conflicts are shown and the
   batch item skipped.
4. Every removal batch logged with versions to
   `~/.local/state/manjaro-sl/removed-<timestamp>.log`.

## Wallpaper subsystem (Ly-style animations for dwm)

Ly (verified against v1.4.0, 2026-05-01) has **no image background support** —
its animations are procedural TUI effects. We recreate them natively:

- Small C programs following suckless conventions (`config.def.h`, `Makefile`,
  MIT license), linking **only libX11**.
- They render into a pixmap, set it as the root window background, and update
  it in a loop; they set `_XROOTPMAP_ID`/`ESETROOT_PMAP_ID` atoms so
  feh-style tools interoperate.
- FPS configurable in `config.h` (CPU tradeoff documented in README).
- **Phase 1 (this project): `doomfire/`** — Fabien Sanglard's PSX Doom fire
  algorithm (public domain, ~100 lines of logic).
- **Phase 2 (future): `xmatrix/`, `colormix/`** — TUI shows them as
  "coming soon" stubs until then.
- `lib/wallpaper.sh` writes `~/.config/manjaro-sl/wallpaper.sh` (launcher) and
  wires it into `~/.xinitrc`; "none" mode removes the hook or swaps to
  `feh --bg-fill` for a static image.
- Ly screen's "Match dwm wallpaper" checkbox mirrors the Ly animation choice
  to the corresponding dwm wallpaper (doom→doomfire; matrix/colormix→phase-2
  stub → falls back to none with a notice).

## Execution engine

Fixed apply order: **debloat → tweaks → install packages → build suckless
tools → configure (config.h edits) → Ly → wallpaper → summary**.

Each step runs via `run_step "name" fn`:

- stdout/stderr teed to `~/.local/state/manjaro-sl/run-<timestamp>.log`
- on failure: whiptail box "step failed — View log / Continue / Abort"
- service toggles happen last within each step so a mid-step failure never
  leaves boot behavior half-changed

## Testing

- `bash -n` and `shellcheck` across `manjaro-sl.sh` + `lib/*.sh` (CI-able).
- `--dry-run` prints every mutating command (pacman/systemctl/install/cp) —
  used as the CI smoke test path.
- `doomfire`: `make test` renders 10 frames against `Xvfb`.
- Manual matrix: fresh-install run, reconfigure run, `-y` non-interactive run,
  `--preset minimal --dry-run`.

## Out of scope (explicitly)

- AUR helper installation/usage (pacman repos only).
- Wayland support (dwm is X11).
- xmatrix/colormix implementations (phase 2).
- Theme engine / modular patch management (bug-report recommendations —
  possible future work).

## Migration / rename checklist

1. User renames repo on GitHub (`gh repo rename manjaro-sl` after
   `sudo pacman -S github-cli` + `gh auth login`, or via web UI).
2. `git remote set-url origin https://github.com/BirchWoodGod/manjaro-sl.git`
3. Update `bug_report_and_recommendations.md` reference `BirchWoodGod/sl`.
4. README rewritten for the new dual purpose (DWM setup + debloat), new name,
   new usage examples.
