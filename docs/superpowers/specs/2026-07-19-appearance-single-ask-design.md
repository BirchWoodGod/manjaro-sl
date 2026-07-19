# Appearance Menu — Single-Ask Wallpaper Selection

**Date:** 2026-07-19
**Status:** Approved by user (brainstorming session)
**Builds on:** v2 design (Appearance screen), wallpapers phase 3 (registry).

## Problem

The Appearance → Advanced flow asks two back-to-back questions (Ly animation,
then desktop wallpaper). Users hitting it to tweak one thing feel asked for
the same choice twice. Confirmed by the user as the pain point.

## Change

`appearance_menu` items become: **Animation / Desktop wallpaper / Enable Ly
on boot / Back**. The `advanced` case (and its stale Ly-animation radiolist,
which was missing gameoflife) is deleted.

### Desktop wallpaper item (new)

One radiolist:
- `match` — "Match login animation (default)"
- `none` — "None"
- one entry per `available_wallpapers` member, labels from `WALLPAPER_DESCS`.

Pre-selection: `match` when `ly/match_wallpaper` is on or unset; otherwise
the current `dwm/wallpaper` value (`none` when unset/off).

On choose:
- `match` → `state_set ly/match_wallpaper on`, then immediately
  `select_wallpaper "$(ly_animation_to_wallpaper "$(state_get ly/animation)")"`
  so preview/profile stay truthful.
- `none` or a wallpaper name → `select_wallpaper` that value +
  `state_set ly/match_wallpaper off`.

### Animation item (refined)

Unchanged UI. Behavior refinement: when `ly/match_wallpaper` is explicitly
`off`, picking an animation sets ONLY `ly/animation` — it no longer stomps
the user's desktop override. When match is on/unset, it derives the desktop
wallpaper via the mapping as today (both fixed and Custom… branches).

## Non-changes

State keys, CLI flags, `apply_all`, `sync_ly_wallpaper` (already
match-gated), presets, profiles: untouched.

## Testing

- Update appearance herestring tests for the new tag set (`wallpaper`
  replaces `advanced`).
- New: override to doomfire while animation=matrix → dwm/wallpaper=doomfire,
  match=off, component/doomfire implied; re-pick `match` → wallpaper
  re-derives (xmatrix) and match=on; Animation pick with match=off leaves
  the override untouched; menu-integrity assertions drop `Advanced`, gain
  `Desktop wallpaper`.
- README Appearance section rewritten to the three-item screen; suite green.
