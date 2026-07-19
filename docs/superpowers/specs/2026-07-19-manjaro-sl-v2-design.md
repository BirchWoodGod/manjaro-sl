# manjaro-sl v2 — Repo Organization, Menu Simplification, xmatrix

**Date:** 2026-07-19
**Status:** Approved by user (brainstorming session)
**Builds on:** `2026-07-18-manjaro-sl-design.md` (v1, shipped on branch `manjaro-sl-rework`)

## Goals (from user feedback after real-world use)

1. **Organize the repo** — one entry script at root; deprecated wrapper gone.
2. **Simplify the TUI** — user found three overlapping menu pairs confusing
   (Reconfigure vs. other menus; Install vs. Configure DWM; Ly animation vs.
   dwm wallpaper).
3. **Ship the matrix desktop wallpaper** (`xmatrix`) — the user's chosen Ly
   animation should light up both login screen and desktop.
4. **Future-proof Ly animation selection** — Ly v1.4 added a custom animation
   framework (`.dur`) and community animations exist (e.g. a black hole);
   the TUI must be able to select animations we don't know about yet.

## 1. Repo organization

- **Delete `build_suckless.sh`** (currently a deprecation wrapper).
  `manjaro-sl.sh` accepts every legacy flag and positional component.
  - README gains a short "Migrating from build_suckless.sh" note with an
    old→new invocation table (`./build_suckless.sh st -y` →
    `./manjaro-sl.sh st -y`, etc.).
  - The wrapper-targeted regression tests (nosudo `--help`, positional
    forwarding) are retargeted to `manjaro-sl.sh` or deleted where they
    duplicate existing manjaro-sl tests.
- **Move `bug_report_and_recommendations.md` → `docs/`** (historical record).
- **Add `dmenu/j4-dmenu-desktop/subprojects/.wraplock` to `.gitignore`**
  (meson artifact).
- Root after cleanup: `manjaro-sl.sh`, `readme.md`, `.gitignore`, component
  dirs (`dwm/ dmenu/ st/ slstatus/ doomfire/ xmatrix/`), `lib/`, `data/`,
  `docs/`, `misc0/`, `tests/`.

## 2. Menu restructure + auto-preload

New main menu (9 items → 7):

```
manjaro-sl        (banner: "existing setup detected — current settings loaded"
                   or "fresh setup")
1. Desktop Setup   components checklist + modkey + bar color + interface + battery
2. Appearance      one animation choice for login screen AND desktop (see §3)
3. Debloat Manjaro (unchanged)
4. System Tweaks   (unchanged)
5. Presets         Recommended / Minimal
6. Preview & Apply (unchanged)
7. Quit
```

- **Auto-preload replaces the Reconfigure item.** `main()` always runs
  `detect_existing_setup` (the current `reconfigure_load`, renamed) before
  showing the menu. Detection signal: any of dwm binary installed, Ly config
  present, or `~/.xinitrc` exists → "existing setup detected" banner; else
  "fresh setup". Preloaded values fill SELECTIONS exactly as reconfigure_load
  does today (modkey, bar color, slstatus interface/battery, Ly animation +
  enabled state, wallpaper block presence).
- **Desktop Setup** = single submenu fusing the current "Install DWM &
  Suckless Tools" checklist and the "Configure DWM" items. Same screens,
  one entrance. Wallpaper moves OUT of this menu (to Appearance).
- **CLI flags unchanged.** This is TUI-only restructuring: `--only` sections,
  `--enable-*`, presets, positional components all keep current semantics.
  `reconfigure_load` keeps existing behavior under its new name; no flag is
  added or removed.

## 3. Appearance screen

- Primary control: one radiolist — **doom / matrix / colormix / none /
  Custom…** — driving BOTH surfaces:
  - `ly/animation` ← chosen value (Custom… opens a `tui_input` accepting any
    animation name, written verbatim to Ly's config; this is the
    forward-compatibility path for new/community animations such as a black
    hole `.dur`).
  - `dwm/wallpaper` ← via `ly_animation_to_wallpaper`, which gains
    `matrix→xmatrix`. Mapping table after this round:
    `doom→doomfire`, `matrix→xmatrix`, everything else→`none` (colormix and
    custom values fall back with the existing phase-2/unsupported notice).
- "Advanced: set login screen and desktop separately" toggle → the two
  individual radiolists (Ly animation; desktop wallpaper none/doomfire/
  xmatrix). Exists for combos like matrix login + doomfire desktop.
- The **Ly enable-on-boot checkbox** moves here from the old Ly menu.
- State keys unchanged (`ly/animation`, `dwm/wallpaper`, `ly/match_wallpaper`,
  `ly/enable`): apply_all, presets, profiles, and all existing tests keep
  working. The merge is purely screen-level. The unified choice sets
  `ly/match_wallpaper=on`; the Advanced path sets it off.
- No validation of custom animation names against the installed Ly version
  (Ly ignores/falls back on unknown values; we do not maintain a version
  matrix). The input is trimmed and written as-is.

## 4. xmatrix

New top-level `xmatrix/` mirroring `doomfire/` conventions:

- Files: `main.c`, `config.def.h`, `config.mk`, `Makefile`, `LICENSE` (MIT),
  `.gitignore` (binary + config.h).
- Classic green digital rain on the X11 root window: per-column droplets with
  a bright head and fading tail, random speeds and lengths, random glyph
  cycling. Glyphs drawn with X11 core fonts (`XLoadQueryFont "fixed"` with
  fallback to `*`), no Xft/fontconfig dependency — libX11 only, same
  root-pixmap + `_XROOTPMAP_ID`/`ESETROOT_PMAP_ID` technique as doomfire.
- `config.def.h` knobs: `FPS` (default 24), head/tail colors (greens),
  `DENSITY` (active-column fraction), `CELL_W`/`CELL_H` (glyph cell size),
  charset string.
- `-n N` flag renders N frames then exits; `make test` via Xvfb with clean
  skip when Xvfb is absent. Compiles warning-free under
  `-std=c99 -pedantic -Wall -Wextra`.
- Integration: accepted as a buildable component everywhere doomfire is
  (positional arg, component checklist, `clean_build_artifacts`); the
  Recommended preset keeps `doomfire` as its default wallpaper.

## 5. Out of scope (explicitly)

- `xcolormix` and `xblackhole` desktop wallpapers — **phase 3**, named here
  as the next two, in that order. (Black hole: swirling accretion-disk
  procedural effect; no official Ly counterpart yet — community `.dur`
  animations cover the login side via the Custom… entry.)
- Installing community `.dur` animation files for Ly (user can drop them in
  manually; Custom… selects them).
- Any CLI flag surface changes.

## 6. Testing

- Existing suite (178 assertions) stays green, except wrapper-specific tests
  which are retargeted/removed with the wrapper.
- New tests:
  - `detect_existing_setup` banner state (existing-setup vs. fresh fixtures).
  - Appearance unified choice writes BOTH `ly/animation` and `dwm/wallpaper`
    (doom→doomfire, matrix→xmatrix) and sets `ly/match_wallpaper=on`;
    Advanced path sets keys independently and `ly/match_wallpaper=off`;
    Custom… writes verbatim value and desktop falls back to none.
  - Menu integrity: main menu contains exactly the 7 new entries; deleted
    entrances (`Reconfigure`, `Install DWM`, `Ly Display Manager` as separate
    items) are gone.
  - xmatrix: builds warning-free; `-n 3` without DISPLAY exits 1 with the
    cannot-open-display message; `make test` skip path.
  - Repo org: `build_suckless.sh` absent; `.wraplock` ignored;
    `docs/bug_report_and_recommendations.md` exists.

## 7. Migration notes for the README

- "Migrating from build_suckless.sh" table (old→new commands).
- Appearance section replaces the separate Ly/wallpaper documentation;
  matrix now works on both surfaces; custom Ly animations documented with a
  pointer to the community animations repo.
