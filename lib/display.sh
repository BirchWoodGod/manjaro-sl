#!/usr/bin/env bash
# Display subsystem: wires an xrandr call into ~/.xinitrc inside a marked,
# idempotent block so resolution/refresh settings apply on every login.

DP_BLOCK_START="# >>> manjaro-sl display >>>"
DP_BLOCK_END="# <<< manjaro-sl display <<<"

# Connected outputs, one per line. Needs a running X session — with no
# DISPLAY (or no xrandr at all) this prints nothing and the TUI falls back
# to a raw-arguments text box, same shape as the interface picker's
# no-detection fallback.
detect_xrandr_outputs() {
  command -v xrandr >/dev/null 2>&1 || return 0
  [ -n "${DISPLAY:-}" ] || return 0
  xrandr --query 2>/dev/null | awk '$2 == "connected" { print $1 }'
}

# Mode names (e.g. 1920x1080) for one output, one per line, in xrandr's own
# preference order.
detect_xrandr_modes() {
  command -v xrandr >/dev/null 2>&1 || return 0
  [ -n "${DISPLAY:-}" ] || return 0
  xrandr --query 2>/dev/null | awk -v out="$1" '
    $2 == "connected" { grab = ($1 == out); next }
    /^[^ \t]/ { grab = 0 }
    grab && $1 ~ /^[0-9]+x[0-9]+/ { print $1 }'
}

display_strip_block() {
  local xi="$HOME/.xinitrc"
  [ -f "$xi" ] || return 0
  sed -i "\|^${DP_BLOCK_START}\$|,\|^${DP_BLOCK_END}\$|d" "$xi"
}

display_wire_xinitrc() {
  local args="$1" xi="$HOME/.xinitrc"
  display_strip_block
  touch "$xi"
  local block
  block=$(printf '%s\n%s\n%s' "$DP_BLOCK_START" "xrandr $args" "$DP_BLOCK_END")
  # Insert before the wallpaper block or an 'exec dwm' line, whichever comes
  # first — the wallpaper programs size themselves to the root window at
  # startup, so the resolution must already be set when they launch. Else
  # append.
  if grep -q "^${WP_BLOCK_START}\$" "$xi" || grep -q '^exec .*dwm' "$xi"; then
    # Keep the original mode: Ly executes ~/.xinitrc as a program, so losing
    # the +x bit locks the user out of their session (same rule as
    # wallpaper_wire_xinitrc).
    local mode; mode=$(stat -c '%a' "$xi")
    awk -v blk="$block" -v wp="$WP_BLOCK_START" \
      '!done && ($0 == wp || /^exec .*dwm/) { print blk; done=1 } { print }' \
      "$xi" > "$xi.tmp" && mv "$xi.tmp" "$xi"
    chmod "$mode" "$xi"
  else
    [ -s "$xi" ] && [ -n "$(tail -c1 "$xi")" ] && printf '\n' >> "$xi"
    printf '%s\n' "$block" >> "$xi"
  fi
}

# dwm/xrandr: unset/"off" = leave ~/.xinitrc alone (never strip a block the
# user didn't ask to change — unlike dwm/wallpaper, where "off" means none);
# "none" = remove the block; anything else = the xrandr argument string,
# written into the block verbatim after "xrandr ".
display_apply() {
  local args; args=$(state_get dwm/xrandr)
  case "$args" in
    off|"") return 0 ;;
    none)   display_strip_block; return 0 ;;
  esac
  display_wire_xinitrc "$args"
}
