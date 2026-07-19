# manjaro-sl

A WinUtil-inspired whiptail TUI for Manjaro Linux that does two things in one
tool: **debloats a stock Manjaro install** (Manjaro-branded packages, unwanted
preinstalled apps, printing/bluetooth stacks, old desktop environments and
display managers) and **installs/configures a customized DWM suckless
desktop** — dwm, dmenu (with j4-dmenu-desktop), st, slstatus, a Ly display
manager, and a from-scratch animated Doom-fire wallpaper. It also doubles as
a **reconfiguration tool**: re-run it on a machine it already set up to
change the modkey, bar color, wallpaper, or debloat selections.

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

Launching `./manjaro-sl.sh` with no flags opens a whiptail main menu with
these sections (selections stack across screens into one in-memory state
until you apply them):

1. **Reconfigure existing setup** — reads current values from `dwm/config.h`,
   `slstatus/config.h`, `/etc/ly/config.ini`, and `~/.xinitrc` (or a saved
   profile) and pre-checks every screen to match, so you can tweak just what
   you want to change.
2. **Install DWM & suckless tools** — checklist: `dwm`, `dmenu`, `st`,
   `slstatus`, `doomfire`.
3. **Debloat Manjaro** — submenu of category checklists: Manjaro-branded
   packages, preinstalled apps, printing stack, bluetooth stack, and old
   DE/DM removal.
4. **Configure DWM** — modkey (Super/Alt), bar highlight color (theme presets
   or custom hex), wallpaper animation, battery widget, network interface
   (auto-detected).
5. **System tweaks** — checklist of systemd service enable/disable toggles.
6. **Ly display manager** — enable on boot, animation choice, and a "match
   dwm wallpaper" checkbox that mirrors the Ly animation to the dwm
   wallpaper.
7. **Apply preset** — bulk-set every checklist to a curated **Recommended**
   or **Minimal** profile (see table below); you can still hand-edit any
   screen afterward.
8. **Preview & apply** — shows every queued action, asks for final
   confirmation, then executes debloat → tweaks → install → build → configure
   → Ly → wallpaper in that order, logging each step to
   `~/.local/state/manjaro-sl/run-<timestamp>.log`.

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

### Wallpaper

Ly's built-in animations are procedural TUI effects with no image-background
support, so `manjaro-sl` recreates them natively as small suckless-style C
programs (`config.def.h`, `Makefile`, MIT license) that link only against
`libX11`, render into a pixmap, and set it as the X root window background
(setting `_XROOTPMAP_ID`/`ESETROOT_PMAP_ID` so feh-style tools interoperate).
They need an active X server but no window manager or compositor.

- **`doomfire/`** (available now) — Fabien Sanglard's PSX Doom fire
  algorithm, public domain, painted directly on the root window.
- **`xmatrix`, `colormix`** — phase-2 stubs; the TUI marks them "coming
  soon" until implemented.

Frame rate is configurable in `doomfire/config.h` (copy from
`config.def.h`) via the `FPS` constant — CPU cost scales roughly linearly
with FPS, so lower it on older hardware. Fire buffer resolution (`FIRE_W`/
`FIRE_H`) is also tunable: smaller buffers mean chunkier pixels but less
CPU.

---

## Non-Interactive Usage

Any flag switches `manjaro-sl.sh` out of the TUI-only path: flags are
processed **left to right** and build up the same selection state the TUI
edits, then `--apply` (or `-y`) executes it. Because parsing is strictly
sequential, `--preset NAME` bulk-sets selections at the point it's parsed —
`--enable-*`/`--disable-*` flags placed *after* a `--preset` override what
the preset chose; flags placed *before* it get overridden by the preset
instead. Bare component names (`dwm`, `dmenu`, `st`, `slstatus`, `doomfire`)
are applied last, after any preset, and restrict the build step to just the
named component(s).

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
  --wallpaper WP            Set dwm wallpaper animation: 'none' or 'doomfire'
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
./manjaro-sl.sh --wallpaper doomfire
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

## Reconfigure Mode

If you already ran `manjaro-sl.sh` on a machine, run it again — main menu
option **1, "Reconfigure existing setup"**, reads your live configuration
(`dwm/config.h`, `slstatus/config.h`, `/etc/ly/config.ini`, `~/.xinitrc`) or
a saved profile at `~/.config/manjaro-sl/profile`, and pre-checks every
screen to match what's already applied. Visit any menu to change a value
(modkey, bar color, wallpaper animation, debloat selections, etc.), then use
**Preview & apply** as normal — changed files are overwritten with backups
using the existing `copy_with_backup` pattern, so nothing is silently lost.

A successful **Preview & apply** run also saves your selections to
`~/.config/manjaro-sl/profile`, which you can copy to another machine and
load with `--profile FILE` to reproduce the same setup non-interactively.

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
- `none` - No animation (default)

The TUI's Ly screen configures Ly with your chosen animation and enables the
service; it never stops an already-running display manager.

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
Change into each directory (`dwm`, `dmenu`, `st`, `slstatus`, `doomfire`)
and run:

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
