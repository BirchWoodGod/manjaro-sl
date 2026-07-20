# drv Vendoring & CDE Second Session

**Date:** 2026-07-19
**Status:** Approved by user (brainstorming session)

## Goals

1. Vendor the user's `drv` (Douay-Rheims Bible terminal reader,
   `~/github/drv`) as an optional build component.
2. Offer CDE (Common Desktop Environment) as an optional AUR source build
   that registers a second login session next to dwm in Ly.
3. (Bundled bug fix, previously promised) Old-DE detection misses pacman
   GROUPS: `plasma`/`gnome` in `data/de.list` are groups, not packages, so
   fresh Manjaro KDE/GNOME installs are never offered for removal.

## 1. drv component

- Copy `~/github/drv` (src/, data/, Makefile, LICENSE, README.md) into
  `manjaro-sl/drv/`; keep its LICENSE; note the vendoring (source repo URL)
  at the top of `drv/README.md`.
- New `EXTRA_COMPONENTS` registry in `lib/suckless.sh`:
  `EXTRA_COMPONENTS=(drv)` + `EXTRA_COMPONENT_DESCS[drv]="Douay-Rheims
  Bible terminal reader"`. Consumed by: Desktop Setup component checklist,
  `parse_args` valid_comps, `clean_build_artifacts` — mirroring how the
  wallpaper registry feeds the same sites (wallpapers and extras are
  separate registries; extras are not wallpapers).
- Builds through the existing component path (`make clean && make`,
  privileged `make install`). Implementer verifies drv's Makefile has
  compatible `clean`/`install` targets and documents any required minimal
  adaptation IN THE VENDORED COPY (upstream untouched).
- Not in DEFAULT_COMPONENTS; both presets leave it off; opt-in via
  checklist or positional `drv`.

## 2. CDE second session (first sanctioned AUR exception)

- New `data/aur-optional.list` (same `name|desc|state` format):
  `cde|Common Desktop Environment — second login session (AUR source build, slow)|off`.
- New `lib/aur.sh`:
  - `aur_screen` — checklist from the data file → `SELECTIONS[aur/<name>]`.
  - `aur_apply` — for each on entry: fetch
    `https://aur.archlinux.org/cgit/aur.git/snapshot/<name>.tar.gz` into
    `~/.cache/manjaro-sl/aur/<name>/`, extract, `makepkg -si --noconfirm
    --needed` AS THE USER (makepkg refuses root; sudo only happens inside
    makepkg's install step). All mutations behind `run_mut` where they are
    scriptable; under `--dry-run` the step prints the fetch/build commands
    and runs nothing (network included).
- TUI: Desktop Setup gains an "Extra software (AUR)" item opening
  `aur_screen`. Generated `--enable-<name>`/`--disable-<name>` flags extend
  to the aur list (same matcher used for debloat/install lists).
- apply_all: new `run_step "AUR builds" aur_apply` after "Install packages"
  (needs base-devel present), gated by `section_enabled install`.
- Session registration: after a successful cde build+install, verify a
  session entry exists in `/usr/share/xsessions/`; if the AUR package does
  not ship one, install a minimal `cde.desktop` (Exec pointing at the CDE
  session start script — implementer determines the correct path from the
  AUR PKGBUILD at implementation time and records it in the spec's
  implementation report). Ly then lists both dwm and CDE sessions natively.
- Documented honestly in README: AUR = user-maintained, source build takes
  a long time, may break; this is the project's single AUR exception.

## 3. Group-aware old-DE detection (bug fix)

- `debloat_installed_from` additionally treats a list entry as a pacman
  GROUP: if `pacman -Qq <name>` fails but `pacman -Qg <name>` succeeds
  (any installed member), the entry is "installed". Removal already works
  (`pacman -Rns <group>` resolves members).
- Tests with mocked pacman covering: group-installed (Qq fails, Qg
  succeeds) → offered; neither → not offered.
- `data/de.list` additionally gains `plasma-desktop` and `gnome-shell`
  package entries (belt-and-braces for partial installs).

## Non-changes

Wallpaper registry, mapping, presets' default selections, repos-only rule
for everything except the single sanctioned `data/aur-optional.list` path.

## Testing

- drv: component checklist/positional/valid_comps tests (mirroring
  wallpaper component tests); build+install-target verification; suite
  green.
- aur: aur_screen selection test; `aur_apply` DRY_RUN test asserting
  printed fetch/makepkg commands and zero execution; flag matcher test
  (`--enable-cde`).
- Group detection: mocked-pacman unit tests as above.
- Manual: user builds drv via the TUI; CDE end-to-end is user-run (hours);
  script-side dry-run + session-file logic covered by tests.
