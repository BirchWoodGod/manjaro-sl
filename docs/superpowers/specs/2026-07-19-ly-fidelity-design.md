# Ly-Fidelity Rework — xcolormix & xblackhole

**Date:** 2026-07-19
**Status:** Approved by user (brainstorming session)

## Problem

User feedback after live use: xcolormix and xblackhole "are not at all what
the Ly versions are like." Both were designed from prose descriptions.
Ground truth has now been obtained:

- **ColorMix** (`src/animations/ColorMix.zig` in fairyglade/ly): a
  shader-style 3-iteration UV feedback warp rendered through a 12-entry
  palette cycling three color pairs (col1↔col2, col2↔col3, col3↔col1) at
  four density levels (█▓▒░). Ly defaults: col1 red `0xFF0000`, col2 blue
  `0x0000FF`, col3 black.
- **Black hole** (`animations/dur/blackhole-smooth-240x67.dur` in
  fairyglade/ly-community, ISC-style license): a hand-crafted 40-frame,
  12 fps, 240×67 durdraw loop using density chars ` .·░▒▓█` with xterm-256
  foreground colors (deep indigo/violet: 17, 23, 53, 54, 55, 60 …). It is
  recorded art, not procedural.

Both programs are REPLACED in place — directory names, registry entries,
menus, mapping, and tests' component plumbing all stay untouched.

## 1. xcolormix rewrite — faithful port

Pixel port of the exact Zig math:

- UV init (pixel adaptation of the terminal-cell version, square pixels):
  `uv = ((2x − W) / (2H), (2y − H) / H)` over the scaled render buffer.
- Per frame, per cell, verbatim transformation:

```
time = frame * 0.01
uv2 = (0,0)
repeat 3 times:
    uv2 += uv + splat(length(uv))
    uv  += 0.5 * ( cos(cos_mod + uv2.y*0.2 + time*0.1),
                   sin(sin_mod + uv2.x     - time*0.1) )
    uv  -= splat( 1.0 * cos(uv.x + uv.y) − sin(uv.x*0.7 − uv.y) )
index = floor(length(uv) * 5.0) mod 12
```

- 12-entry pixel palette: pairs (col1,col2), (col2,col3), (col3,col1), four
  density levels each; density d ∈ {1.0, 0.75, 0.5, 0.25} (█▓▒░ analogue)
  → `pixel = mix(colB, colA, d)` (block char = fg over bg: full block shows
  colA; light shade mostly colB).
- `cos_mod`/`sin_mod`: randomized once at startup (0..2π), matching Ly's
  per-run variation.
- Math helpers, keeping libX11-only/no-libm: 1024-entry sine table via
  incremental rotation (established pattern; cos(x)=sin(x+π/2)), radians →
  table index by scaling; sqrt via the bit-hack initial guess + 2 Newton
  iterations (banded output is tolerant of both approximations).
- `config.def.h` knobs: `FPS` (24), `BUF_W/BUF_H` (240/135 — warp math is
  heavier per pixel than the old gradient), `COL1/COL2/COL3` (0xRRGGBB,
  defaults red/blue/black per Ly), `TIME_SCALE` (0.01).

## 2. xblackhole rewrite — embedded loop player

- **Vendor** `xblackhole/blackhole-smooth-240x67.dur` (the gzipped original,
  ~470 KB) plus `xblackhole/ATTRIBUTION` (source URL, artist field from the
  file, ly-community ISC license text).
- **Build-time converter** `xblackhole/dur2c.py` (python3 — already a
  project dependency): gunzip + JSON-parse the .dur → emit `frames.h`
  containing, per frame, RLE runs of (density 0-6, color-index) cells plus
  a small xterm-256→RGB table for the colors actually used. Deterministic
  output; Makefile rule regenerates `frames.h` only when the .dur or the
  script changes; `frames.h` is git-ignored (generated).
- **Player** `main.c`: decode RLE into a 240×67 cell grid per frame; render
  scaled to screen (nearest-neighbor cells); density maps to brightness of
  the cell's RGB — seven levels, ` `=0 (off), then `.` `·` `░` `▒` `▓` `█`
  ascending; loop at the .dur's native
  12 fps (`FPS` knob defaults 12; changing it just replays faster/slower).
  Same template contract: `-n N`, no-display exit 1, root pixmap + atoms,
  warning-free, libX11 only.
- Old particle-swirl code is deleted.

## Non-changes

Registry, menus, mapping (`blackhole→xblackhole`), CLI, state keys, tests'
component/positional plumbing: untouched. Only the two programs' internals
(and xblackhole's new vendored/generated files + Makefile rule) change.

## Testing

- Existing per-component tests keep passing unchanged (positional, help
  coverage, registry).
- `dur2c.py` unit test (run under the shell suite): convert a tiny
  hand-written .dur fixture (2 frames, 2×2 cells, gzipped in the test) and
  assert the emitted header contains the expected runs/colors.
- Both programs: build warning-free; `-n 3` no-display exit 1; `make test`
  Xvfb skip. xblackhole's build must work from a clean checkout (converter
  runs before cc).
- Manual checkpoint: user compares desktop vs Ly login side-by-side.
