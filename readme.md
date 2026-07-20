# manjaro-sl

A WinUtil-inspired whiptail TUI for Manjaro Linux that does two things in one
tool: **debloats a stock Manjaro install** (Manjaro-branded packages, unwanted
preinstalled apps, printing/bluetooth stacks, old desktop environments and
display managers) and **installs/configures a customized DWM suckless
desktop** — dwm, dmenu (with j4-dmenu-desktop), st, slstatus, a Ly display
manager, and from-scratch animated X11 wallpapers (Doom fire, Matrix rain,
color gradients, Game of Life, black hole).
It also doubles as a **reconfiguration tool**: re-run it on a machine it
already set up and it auto-detects the existing setup and preloads current
settings so you can change just the modkey, bar color, wallpaper, or
debloat selections.

> **Note**: This automation was developed with AI assistance to provide an
> interactive whiptail TUI, safety-railed debloat engine, and reproducible
> non-interactive/profile-based setup.

---

## Quick Start

```bash
git clone https://github.com/BirchWoodGod/manjaro-sl && cd manjaro-sl && ./manjaro-sl.sh
```

With no arguments, this launches the interactive TUI. If `whiptail` isn't
available, install it with `sudo pacman -S libnewt` when prompted.

<!-- TODO: screenshot after first release -->

---

## What It Does

Launching `./manjaro-sl.sh` with no flags always runs an auto-preload check
first (`detect_existing_setup`), then opens a whiptail main menu with these
seven sections (selections stack across screens into one in-memory state
until you apply them):

```
manjaro-sl        (banner: "existing setup detected — current settings loaded"
                   or "fresh setup")
1. Desktop Setup   components checklist + modkey + bar color + interface + battery
2. Appearance      one animation choice for login screen AND desktop
3. Debloat Manjaro (unchanged)
4. System Tweaks   (unchanged)
5. Presets         Recommended / Minimal
6. Preview & Apply (unchanged)
7. Quit
```

1. **Desktop Setup** — a single submenu fusing what used to be two separate
   entrances ("Install DWM & suckless tools" and "Configure DWM"): the
   components checklist (`dwm`, `dmenu`, `st`, `slstatus`, `doomfire`,
   `xmatrix`), modkey (Super/Alt), bar highlight color (radiolist of 15
   Solarized/Nord/Gruvbox presets, plus Custom hex… and Keep current),
   slstatus network interface (radiolist of interfaces detected via `ip`,
   plus Custom… and Keep current — falls back to a plain text box if
   detection finds nothing), and the battery widget. Wallpaper/animation is
   not here — it lives in Appearance.
2. **Appearance** — a screen for the Ly login-screen animation, an optional
   desktop wallpaper override, and the "Enable Ly on boot" checkbox (see
   [Appearance](#appearance) below for the full mapping and Custom…/override
   behavior).
3. **Debloat Manjaro** — submenu of category checklists: Manjaro-branded
   packages, preinstalled apps, printing stack, bluetooth stack, and old
   DE/DM removal.
4. **System Tweaks** — checklist of systemd service enable/disable toggles.
5. **Presets** — bulk-set every checklist to a curated **Recommended** or
   **Minimal** profile (see table below); you can still hand-edit any screen
   afterward.
6. **Preview & Apply** — shows every queued action, asks for final
   confirmation, then executes debloat → tweaks → install → build → configure
   → Ly → wallpaper in that order, logging each step to
   `~/.local/state/manjaro-sl/run-<timestamp>.log`.
7. **Quit**.

### Auto-preload

There is no separate "Reconfigure" menu item anymore. `detect_existing_setup`
runs once per launch, but only on the interactive path — after argv flags
have already been parsed, and only when the run is headed for the main menu
rather than straight to `--apply`/`-y`; non-interactive/flag-driven runs
(`--apply`, `-y`) skip it entirely, since nothing is around to look at a
pre-filled menu. It first loads a saved profile from
`~/.config/manjaro-sl/profile` (if one exists) into the in-memory selection
state, then separately checks for any of: a `dwm` binary on `PATH`, an
`/etc/ly/config.ini`, or a `~/.xinitrc` — the profile load itself is not one
of these signals, so a loaded profile alone does not flip the banner. If any
of those three checks fires, the main menu banner reads **"existing setup
detected — current settings loaded"** and every screen is pre-checked to
match what's already applied (modkey, bar color, slstatus interface/battery,
Ly animation + enabled state, wallpaper). Otherwise the banner reads **"fresh
setup"**, even if a profile was loaded. Either way, visit any menu to change
a value, then use **Preview & Apply** as normal — changed files are
overwritten with backups using the existing `copy_with_backup` pattern, so
nothing is silently lost.

A successful **Preview & Apply** run also saves your selections to
`~/.config/manjaro-sl/profile`, which you can copy to another machine and
load with `--profile FILE` to reproduce the same setup non-interactively.

### Presets

| Category | Recommended | Minimal |
|---|---|---|
| Recommended packages (feh, meson, fastfetch, htop, nano, NetworkManager, tldr, brightnessctl, alsa-utils, firefox, net-tools...) | all checked | all unchecked |
| Manjaro-branded debloat | checked, except `pamac*` and cosmetic packages (wallpapers, icons, grub theme) | all checked (except `manjaro-zsh-config`) |
| Preinstalled apps debloat | unchecked | checked (except `timeshift*`) |
| Printing stack debloat | unchecked | unchecked |
| Bluetooth stack debloat | unchecked | unchecked |
| Old DE/DM removal | prompted | checked |
| System tweaks | NetworkManager + fstrim on | NetworkManager + fstrim on |
| Wallpaper | doomfire (matching Ly) | none |

`pamac*` is never auto-checked in Recommended (you keep a GUI package
manager by default). `timeshift` and `manjaro-zsh-config` are **never**
auto-checked by either preset — the TUI shows a warning next to them
because removing them takes out your backup system or your zsh/
powerlevel10k setup, and you have to check them yourself if you want them
gone.

### Debloat safety rails

The removal engine (`lib/debloat.sh`) has hard rules that no data file or
flag can override:

- **Hardcoded denylist** checked before every removal batch — core system
  packages (`manjaro-system`, `manjaro-keyring`, `archlinux-keyring`,
  `manjaro-alsa`, `manjaro-gstreamer`, `manjaro-pipewire`, `mhwd*`,
  `pacman`, `pacman-mirrors`, `sudo`, `systemd`, `base`, `filesystem`,
  `linux*`, `networkmanager`) are refused even if a data file lists them.
- **`pacman -Rns` only, never `-Rdd`** — removal runs as a single batch, so
  if pacman reports a dependency conflict the whole batch fails safely and
  nothing in it is force-removed; resolve the conflict and re-run.
- **The currently running display manager is never stopped**, only
  disabled — it keeps running until next reboot so you're never dropped to
  a black screen mid-session.
- **Every removal batch is logged** with package versions to
  `~/.local/state/manjaro-sl/removed-<timestamp>.log`.

### Appearance

The **Appearance** menu is three items:

1. **Animation** — a radiolist — **doom / matrix / gameoflife / colormix /
   none / Custom…** — that drives BOTH the Ly login-screen animation and the
   dwm desktop wallpaper together (this sets `ly/match_wallpaper=on` under
   the hood, unless a desktop wallpaper override is active — see below):

   | Ly animation choice | Desktop wallpaper |
   |---|---|
   | `doom` | `doomfire` |
   | `matrix` | `xmatrix` |
   | `gameoflife` | `xgameoflife` |
   | `colormix` | `xcolormix` |
   | `none` | `none` |
   | Custom… `blackhole` | `xblackhole` (see below) |
   | Custom… (any other name) | `none` |

   Custom… opens a text prompt accepting **any** Ly animation name, written
   verbatim to `/etc/ly/config.ini`. This is the forward-compatibility path
   for animations `manjaro-sl` doesn't know about — Ly v1.4+ supports
   community `.dur` animation files (e.g. a black hole effect: Ly itself
   needs `animation = dur_file` plus `dur_file_path` pointing at the asset,
   which isn't expressible through this single-name prompt), which you can
   drop into your Ly config directory yourself. Typing `blackhole` here is a
   `manjaro-sl`-only convention layered on top: it doesn't configure Ly's
   side (you still set up the real `dur_file`/`dur_file_path` yourself for
   the login screen), but it now gets you the matching `xblackhole` desktop
   wallpaper. See [Ly's community animations](https://github.com/JBongars/ly-animation)
   for examples. There is no validation against the installed Ly version —
   any other unknown name is trimmed and passed through as-is; Ly
   ignores/falls back on names it doesn't recognize.

2. **Desktop wallpaper** — a radiolist that overrides the desktop side
   independently of the login animation: **Match login animation
   (default)**, **None**, or any specific wallpaper whose program is built.
   Picking **Match login animation** (the default, and what a fresh install
   starts on) sets `ly/match_wallpaper=on` and re-derives the wallpaper from
   whatever Animation is currently set to — including wallpapers with no Ly
   counterpart, like `xstarfield`, only reachable this way. Picking any other
   entry decouples the two: it sets `ly/match_wallpaper=off` and pins
   `dwm/wallpaper` to that choice — for combos the unified mapping can't
   express, like a `matrix` login screen with a `doomfire` desktop. Once
   decoupled, changing Animation no longer touches the desktop wallpaper;
   re-picking **Match login animation** here re-couples them.

3. **Enable Ly on boot** — the on/off checkbox.

### Wallpaper

Ly's built-in animations are procedural TUI effects with no image-background
support, so `manjaro-sl` recreates them natively as small suckless-style C
programs (`config.def.h`, `Makefile`, MIT license) that link only against
`libX11`, render into a pixmap, and set it as the X root window background
(setting `_XROOTPMAP_ID`/`ESETROOT_PMAP_ID` so feh-style tools interoperate).
They need an active X server but no window manager or compositor.

- **`doomfire/`** (built) — Fabien Sanglard's PSX Doom fire algorithm,
  public domain, painted directly on the root window. Tunable in
  `doomfire/config.h` (copy from `config.def.h`): `FPS` (default 24, CPU
  cost scales roughly linearly with it) and fire buffer resolution
  `FIRE_W`/`FIRE_H` (default 320x168 — smaller buffers mean chunkier pixels
  but less CPU).
- **`xmatrix/`** (built) — classic green digital rain: per-column droplets
  with a bright head and fading tail, random speeds/lengths, random glyph
  cycling, drawn with X11 core fonts (no Xft/fontconfig dependency).
  Tunable in `xmatrix/config.h` (copy from `config.def.h`): `FPS` (default
  24), `CELL_W`/`CELL_H` (glyph cell size in pixels, default 10x16),
  `DENSITY`/`SPAWN_P` (active-column fraction and spawn probability),
  `FONTNAME` (X11 core font, default `"fixed"`), `CHARSET` (glyphs cycled
  at random), and the tail/head RGB shades.
- **`xcolormix/`** (built) — shifting HSV gradient blend: 3-4 anchor hues
  rotating slowly around the color wheel, blended left-to-right and
  rendered into a scaled buffer (doomfire technique) each frame. Tunable in
  `xcolormix/config.h` (copy from `config.def.h`): `FPS` (default 24),
  buffer resolution `BUF_W`/`BUF_H` (default 320x180), the `ANCHORS[]` hue
  array (degrees, default 4 hues), rotation period `CYCLE_SEC` (default
  60), and `SAT`/`VAL` (saturation/value, default 0.85/0.55).
- **`xgameoflife/`** (built) — Conway's Game of Life on a toroidal grid,
  standard B3/S23 rules, with auto-reseed when the population stagnates
  (dies out or locks into a still life/period-2 oscillator). Tunable in
  `xgameoflife/config.h` (copy from `config.def.h`): `FPS` (default 10 —
  generations/sec, not frames/sec), `CELL` (cell size in pixels, default
  8), `SEED_DENSITY` (fraction of cells alive on (re)seed, default 0.25),
  `STALE_GENS` (generations without population change before reseeding,
  default 120), and `ALIVE_COLOR`/`DEAD_COLOR`.
- **`xblackhole/`** (built) — accretion-disk swirl: particles on decaying
  spiral orbits around screen center, re-emitted at the outer rim to keep a
  steady state, brightening toward the inner edge; a pure-black event
  horizon at the center swallows and re-emits anything that crosses it.
  Tunable in `xblackhole/config.h` (copy from `config.def.h`): `FPS`
  (default 24), `NPARTICLES` (default 600), `HOLE_FRAC` (event-horizon
  radius as a fraction of `min(width,height)/2`, default 0.12), the swirl
  rotation constants `ROT_C`/`ROT_S` and radial `DECAY`, and the `RAMP[]`
  inner-to-outer color gradient (a blue alternative is commented in the
  file). Ly itself has no official black hole animation — this pairs with
  a community `.dur` animation on the login side via Appearance's Custom…
  entry (see [Appearance](#appearance) for the `blackhole` naming
  convention).

- **`xstarfield/`** (built) — flying starfield: stars spawn near the vanishing
  point and accelerate outward as their depth decreases, dim when far and
  brightening as they approach. Tunable in `xstarfield/config.h` (copy from
  `config.def.h`): `FPS` (default 30), `NSTARS` (default 400), `SPEED`
  (per-frame depth decrease, default 0.006), `STAR_COLOR` (default white
  `0xffffff`, green alternative `0x00ff46` noted in the file), and `NSHADES`
  (brightness levels, default 6).
- **`xplasma/`** (built) — demoscene plasma: overlapping sine waves in x, y,
  diagonal, and three independently-drifting time terms, mapped through a
  cycling HSV hue and rendered into a scaled buffer (doomfire technique) each
  frame. Tunable in `xplasma/config.h` (copy from `config.def.h`): `FPS`
  (default 24), buffer resolution `BUF_W`/`BUF_H` (default 320x180), wave
  frequencies `XFREQ`/`YFREQ`/`DFREQ` and time drifts
  `TDRIFT1`/`TDRIFT2`/`TDRIFT3`, and palette `SAT`/`VAL` (default 0.80/0.60).
- **`xrain/`** (built) — falling rain: per-column streaks fall at randomized
  speeds/lengths with a 2-frame splash on impact, colored by speed along a
  blue-grey ramp. Tunable in `xrain/config.h` (copy from `config.def.h`):
  `FPS` (default 30), `COL_W` (column spacing in pixels, default 6),
  `DENSITY`/`SPAWN_P` (active-column fraction and spawn probability, default
  0.35/0.05), `SPEED_MIN`/`SPEED_MAX` and `LEN_MIN`/`LEN_MAX` (px/frame and
  px ranges), `SPLASH` (0 to disable the impact tick), and the `RAMP[]`
  slow-to-fast color array (default 3 blue-grey shades).
- **`xfireflies/`** (built) — drifting fireflies: dots wander with a base
  drift plus sinusoidal wobble, pulsing through brightness levels. Tunable
  in `xfireflies/config.h` (copy from `config.def.h`): `FPS` (default 20),
  `NFLIES` (default 40), `DRIFT`/`WANDER` (base speed and wander amplitude,
  px/frame, default 0.6/0.8), `FLY_COLOR` (default warm yellow-green
  `0xd8e878`), `NSHADES` (pulse brightness levels, default 8), and `DOT`
  (dot size in pixels, default 3).

These four are desktop-only: none has a matching Ly login animation, so
they're only reachable via the Desktop wallpaper override (see
[Appearance](#appearance)), the `--wallpaper` flag, or as a build component
— never as a Ly `Animation` choice. The five above them stay reachable
through all of those plus the Ly-matched `Animation` picker.

Wallpapers are a registry (`KNOWN_WALLPAPERS` in `lib/wallpaper.sh`) gated on
the directory existing, so future wallpapers are one-directory additions —
drop in a `<name>/` with the same `config.def.h`/`Makefile`/binary shape and
register it; no other code changes needed.

---

## Non-Interactive Usage

Any flag switches `manjaro-sl.sh` out of the TUI-only path: flags are
processed **left to right** and build up the same selection state the TUI
edits, then `--apply` (or `-y`) executes it. Because parsing is strictly
sequential, `--preset NAME` bulk-sets selections at the point it's parsed —
`--enable-*`/`--disable-*` flags placed *after* a `--preset` override what
the preset chose; flags placed *before* it get overridden by the preset
instead. Bare component names (`dwm`, `dmenu`, `st`, `slstatus`, `doomfire`,
`xmatrix`) are applied last, after any preset, and restrict the build step
to just the named component(s).

```text
Options:
  -h, --help                Show this help message and exit
  -y, --accept-defaults     Non-interactive; implies --apply unless already
                            given
  --apply                   Skip the TUI and apply the selections built up by
                            the flags so far
  --dry-run                 Print mutating commands instead of running them
  --preset NAME             Bulk-apply a preset: 'recommended' or 'minimal'
  --only SECTION            Restrict --apply to one section (repeatable):
                            install|debloat|tweaks|dwm|ly
  --profile FILE            Load previously saved selections from FILE
  --wallpaper WP            Set dwm wallpaper animation: 'none' or any built
                            wallpaper (doomfire, xmatrix, xcolormix,
                            xgameoflife, xblackhole, xstarfield, xplasma,
                            xrain, xfireflies)
  --enable-SLUG             Turn on a debloat/install entry by package name
  --disable-SLUG            Turn off a debloat/install entry by package name
  --interface IFACE         Set slstatus network interface
  --battery                 Enable the slstatus battery widget
  --no-battery              Disable the slstatus battery widget
  --bar-color COLOR         Hex color for the dwm selected bar
  --modkey KEY              dwm modkey: 'super' or 'alt'
  --remove-de               Mark installed old DEs/DMs for removal
  --no-remove-de            Leave old DEs/DMs alone (default)
  --skip-packages           Skip the recommended/build package install step
  --copy-xinit              Copy the xinitrc helper to ~/.xinitrc
  --no-copy-xinit           Skip copying the xinitrc helper
  --copy-desktop            Copy the dwm.desktop session entry
  --no-copy-desktop         Skip copying the dwm.desktop session entry
```

Run `./manjaro-sl.sh --help` for the full, authoritative flag list.

### Examples

```bash
./manjaro-sl.sh --preset minimal --dry-run --apply
./manjaro-sl.sh -y
./manjaro-sl.sh --interface wlan0 --battery
./manjaro-sl.sh --only debloat --dry-run --apply
./manjaro-sl.sh --wallpaper xmatrix
./manjaro-sl.sh --profile ~/.config/manjaro-sl/profile --apply
```

### `--dry-run`, honestly

`--dry-run` makes the **debloat**, **tweaks**, and **install packages**
steps print the exact `pacman`/`systemctl` commands they would run instead
of executing them — safe to use for a preview on a real machine. The
**build**, **configure**, **Ly**, and **wallpaper** steps write files and
touch services directly rather than going through the same dry-run-aware
command wrapper, so under `--dry-run` they are **skipped entirely** with a
`[dry-run] skipping <step>` notice — they are not simulated. This is why
`--only debloat --dry-run --apply` (or `--preset ... --dry-run --apply`) is
the safe way to preview a run end-to-end: every step that would actually be
skipped-not-simulated is one you probably don't need a preview of anyway.

---

## Manual Setup Reference

> **Note**: The TUI/automation above is the recommended approach. This
> section is provided as a reference for those who prefer manual setup or
> need to understand the individual steps.

### Migrating from build_suckless.sh

The old `build_suckless.sh` entry point has been removed. Use
`manjaro-sl.sh` directly:

| Old | New |
|---|---|
| `./build_suckless.sh` | `./manjaro-sl.sh -y` |
| `./build_suckless.sh st dwm` | `./manjaro-sl.sh st dwm -y` |
| `./build_suckless.sh --interface wlan0 --battery -y` | `./manjaro-sl.sh --interface wlan0 --battery -y` |
| `./build_suckless.sh --skip-packages -y` | `./manjaro-sl.sh --skip-packages -y` |

### Minimal Manjaro install notes
- Enable the `multilib` repo before installing extras by editing
  `/etc/pacman.conf` and ensuring the block below is uncommented (the
  automation does this for you if needed):

  ```ini
  [multilib]
  Include = /etc/pacman.d/mirrorlist
  ```

### Recommended packages
If you prefer to handle packages manually, install the core + recommended
sets from `data/install-core.list` and `data/install-recommended.list`:

```bash
sudo pacman -Syu base-devel libx11 libxft libxinerama freetype2 fontconfig \
  pkgconf python libnewt xorg xorg-xinit ly \
  feh meson fastfetch htop nano networkmanager network-manager-applet \
  tldr brightnessctl alsa-utils firefox net-tools
```

**Build dependencies for j4-dmenu-desktop:**
j4-dmenu-desktop requires either Meson (preferred) or CMake to build. Install
one of them:

```bash
sudo pacman -S meson        # Preferred build system
# or
sudo pacman -S cmake         # Alternative build system
```

### Display manager: Ly
Ly is the preferred display manager purely for the aesthetics. The
automated TUI handles the complete setup, but if you prefer manual
configuration:

```bash
sudo systemctl enable ly
sudo systemctl start ly
```

Configuration lives at `/etc/ly/config.ini`. Available animations include:
- `doom` - Doom-style animation
- `matrix` - Matrix digital rain effect
- `colormix` - Color mixing animation
- `gameoflife` - Conway's Game of Life
- `none` - No animation (default)

You can also set any other animation name Ly's config accepts (e.g.
`animation = dur_file` with `dur_file_path` pointing at a community `.dur`
file you dropped in yourself). The TUI's Appearance screen (see above)
offers the same five built-ins plus a **Custom…** entry for this,
configures Ly with your chosen animation, and enables the service; it
never stops an already-running display manager.

### Xinitrc and desktop entry
The `misc0` directory contains helper files:

- `xinitrc-config.txt` – copy to `~/.xinitrc` if you start dwm manually.
- `dwm.desktop` – copy to `/usr/share/xsessions/dwm.desktop` if you want a
  proper entry in display managers.

```bash
cp ~/manjaro-sl/misc0/xinitrc-config.txt ~/.xinitrc
sudo cp ~/manjaro-sl/misc0/dwm.desktop /usr/share/xsessions/dwm.desktop
```

### Building the suckless components by hand
Change into each directory (`dwm`, `dmenu`, `st`, `slstatus`, `doomfire`,
`xmatrix`) and run:

```bash
sudo make clean install
```

Each project ships with a `config.h` you can tweak before building (copy it
from `config.def.h` first if it doesn't exist yet). `dwm` and `st` already
include the patches this setup relies on (fullscreen, systray, scrollback,
mouse scrolling).

### dmenu and Desktop Entry Support
The `dmenu` component includes **j4-dmenu-desktop** for desktop entry
support. When you build `dmenu` (via the TUI or `./manjaro-sl.sh dmenu`),
j4-dmenu-desktop is automatically built and installed as well. This enables
`dmenu_run` to show both:
- Executables from your `$PATH`
- Applications from `.desktop` files (including AppImage launcher entries)

j4-dmenu-desktop source code is included in `dmenu/j4-dmenu-desktop/` and is
licensed under **GPL-3.0-or-later** (see `dmenu/j4-dmenu-desktop/LICENSE`).
The build uses Meson (preferred) or CMake, so ensure one of these is
installed (see [Recommended packages](#recommended-packages) above).

**Note:** j4-dmenu-desktop is a separate work and remains in its own
subdirectory. The GPL license applies only to j4-dmenu-desktop, not to the
rest of this repository (which uses MIT/X Consortium licenses for the
suckless tools).

---

## Status
This is a living setup. Expect tweaks over time as the tool is refined.
