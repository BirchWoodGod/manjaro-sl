# manjaro-sl Wallpapers Phase 3+4 — Ly Trio & First Customs

**Date:** 2026-07-19
**Status:** Approved by user (brainstorming session)
**Builds on:** v1 (`2026-07-18-manjaro-sl-design.md`), v2 (`2026-07-19-manjaro-sl-v2-design.md`)

## Goal

Complete the Ly-animation ↔ desktop-wallpaper matching (xcolormix, xgameoflife,
xblackhole) and ship the first four custom desktop wallpapers (xstarfield,
xplasma, xrain, xfireflies), on the proven doomfire/xmatrix template.

**Delivery: one spec, two sequential plans.**
- Plan 1: registry refactor + the Ly trio → user test checkpoint.
- Plan 2: the four customs.

## 1. Wallpaper registry (plan 1, first task)

Single source of truth in `lib/wallpaper.sh`:

```bash
KNOWN_WALLPAPERS=(doomfire xmatrix xcolormix xgameoflife xblackhole
                  xstarfield xplasma xrain xfireflies)
WALLPAPER_DESCS=( [doomfire]="DOOM fire" [xmatrix]="Matrix rain" ... )
is_known_wallpaper NAME   # exit 0/1
```

Registry entries may exist before their program ships (plan 1 registers all
nine; plan-2 programs simply aren't built until plan 2 — selecting a
not-yet-shipped wallpaper is prevented by the Advanced radiolist only listing
entries whose directory exists in the repo: `[ -d "$REPO_ROOT/$name" ]`).

Derived from the registry (replacing today's hardcoded lists):
- `select_wallpaper`: implies `component/<wp>` for any registry member.
- `parse_args`: `valid_comps` = `dwm dmenu st slstatus` + registry;
  unknown-component error text lists them dynamically.
- `--wallpaper` validation + error text: `none` + registry members whose
  directory exists.
- Advanced desktop radiolist: `none` + registry members whose directory
  exists, with descriptions.
- Desktop Setup component checklist: `dwm dmenu st slstatus` + registry
  members whose directory exists.
- `clean_build_artifacts`: binaries/dirs derived from registry (guarded by
  dir existence).
- `detect_existing_setup` launcher check: known iff `is_known_wallpaper`.

Refactor is behavior-preserving at plan-1 start (tests prove the derived
lists equal the current hardcoded ones for doomfire/xmatrix).

## 2. Ly trio (plan 1)

All three: standalone top-level dirs mirroring doomfire (`main.c`,
`config.def.h`, `config.mk`, `Makefile`, MIT LICENSE `Copyright (c) 2026
BirchWoodGod`, `.gitignore` with binary + config.h, `-n N` frames flag,
`<name>: cannot open display` → exit 1, root pixmap + `_XROOTPMAP_ID`/
`ESETROOT_PMAP_ID`, `XSetWindowBackgroundPixmap` + `XClearWindow` per frame,
warning-free `-std=c99 -pedantic -Wall -Wextra -Os`, libX11 only, Xvfb
`make test` with clean skip).

### xcolormix
Full-screen HSV gradient blend: 3-4 anchor hues rotating slowly around the
color wheel; per-pixel gradient rendered into a scaled buffer (doomfire
technique) then nearest-neighbor scaled. `config.def.h`: `FPS` (24),
`BUF_W/BUF_H` (320/180), anchor hues array, `CYCLE_SEC` (full rotation
period, default 60).

### xgameoflife
Conway's Game of Life: toroidal grid, random initial seeding, standard
B3/S23 rules. Auto-reseed when stagnant: keep a short history of population
counts; if population is 0 or unchanged/period-2 for `STALE_GENS`
generations, reseed. `config.def.h`: `FPS` (default 10 — generations/sec),
`CELL` (px, 8), `SEED_DENSITY` (0.25), `STALE_GENS` (120), alive/dead
colors (green on near-black).

### xblackhole
Accretion-disk swirl: N particles on decaying spiral orbits around screen
center; radial re-emission at the outer rim keeps steady state; brightness
increases toward the inner edge; circle of radius `HOLE_FRAC * min(w,h)/2`
stays pure black (particles crossing it are re-emitted). Rendered as point/
short-streak primitives (xmatrix technique — no full-screen per-pixel pass).
`config.def.h`: `FPS` (24), `NPARTICLES` (600), `HOLE_FRAC` (0.12), swirl
angular speed, inner/outer colors (orange-white preset; blue alt in
comments).

### Mapping & menu (plan 1)
- `ly_animation_to_wallpaper` += `colormix→xcolormix`,
  `<gameoflife-token>→xgameoflife`, `blackhole→xblackhole`; default stays
  `none`.
- The gameoflife token: implementer verifies the exact animation value the
  installed Ly accepts (config comments / upstream docs) and uses that
  token in BOTH the unified radiolist entry and the mapping. If the
  installed Ly predates gameoflife, the unified entry still writes the
  token (Ly ignores unknown values; documented).
- Unified Appearance radiolist gains gameoflife. colormix loses its
  phase-3 msgbox (real now). Custom…-typed `blackhole` now maps to
  xblackhole (community `.dur` on the login side, matching desktop).
- README: wallpaper section, mapping table, Appearance docs updated.

## 3. Customs (plan 2)

Same conventions. Advanced-radiolist-only (no Ly counterpart; unified picker
stays Ly-driven).

### xstarfield
Center-origin radial starfield: stars with 3D position, projected; speed up
as they approach viewer; streak length ∝ velocity. `config.def.h`: `FPS`
(30), `NSTARS` (400), `SPEED`, color (white; green alt).

### xplasma
Classic demoscene plasma: sum of sin waves over x/y/t indexed into a cycling
palette; scaled buffer render. `config.def.h`: `FPS` (24), `BUF_W/BUF_H`
(320/180), wave scales, palette (rainbow default).

### xrain
Falling streaks: variable speed/length columns (xmatrix engine, primitives
instead of glyphs), optional 2-frame ground splash. Blue-grey palette.
`config.def.h`: `FPS` (30), `DENSITY`, speed range, `SPLASH` (1), colors.

### xfireflies
N dots with sinusoidal wander + slow brightness pulse (precomputed sine
offsets per firefly). `config.def.h`: `FPS` (20), `NFLIES` (40), drift
speed, `PULSE_SEC`, color (warm yellow-green).

## 4. Out of scope

- New Ly-side animations or `.dur` installation.
- Shared C library between wallpapers (standalone per suckless convention).
- Preset changes (Recommended keeps doomfire).
- Any CLI flag beyond `--wallpaper` accepting the new names via registry.

## 5. Testing

- Registry refactor: derived-list equivalence tests (valid components,
  --wallpaper acceptance, checklist entries) before/after; suite stays green.
- Per wallpaper: build warning-free; `env -u DISPLAY ./<n>/<n> -n 3` → exit 1
  with message; `make test` Xvfb skip; positional-component subprocess test
  (`./manjaro-sl.sh <n> --dry-run --apply --skip-packages` → selected: <n>);
  mapping assertions (plan 1) / Advanced-radiolist presence (plan 2,
  source-level assertion).
- Plan-1 end: user test checkpoint (unified picker colormix/gameoflife on
  the real machine) before plan 2 begins.
