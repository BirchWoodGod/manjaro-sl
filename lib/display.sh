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

# Refresh rates for one output+mode, one per line, in xrandr's listed order
# ("*" current / "+" preferred markers stripped).
detect_xrandr_rates() {
  command -v xrandr >/dev/null 2>&1 || return 0
  [ -n "${DISPLAY:-}" ] || return 0
  xrandr --query 2>/dev/null | awk -v out="$1" -v mode="$2" '
    $2 == "connected" { grab = ($1 == out); next }
    /^[^ \t]/ { grab = 0 }
    grab && $1 == mode {
      for (i = 2; i <= NF; i++) {
        r = $i; gsub(/[*+]/, "", r)
        if (r != "") print r
      }
    }'
}

# Currently active "MODE RATE" for one output (xrandr marks the running
# rate with "*"); empty when the output has no active mode.
detect_xrandr_current() {
  command -v xrandr >/dev/null 2>&1 || return 0
  [ -n "${DISPLAY:-}" ] || return 0
  xrandr --query 2>/dev/null | awk -v out="$1" '
    $2 == "connected" { grab = ($1 == out); next }
    /^[^ \t]/ { grab = 0 }
    grab { for (i = 2; i <= NF; i++) if ($i ~ /\*/) {
      r = $i; gsub(/[*+]/, "", r); print $1, r; exit
    } }'
}

# --- Per-output segment state (guided-TUI plumbing) ------------------------
# The guided display menu edits one SELECTIONS[xrandr/OUTPUT] entry per
# monitor and recomposes them into the single dwm/xrandr argument string
# that display_apply/--xrandr/profiles all speak. Segments are joined in
# sorted output-name order so the composed string is deterministic.

display_clear_segments() {
  local key
  for key in "${!SELECTIONS[@]}"; do
    [[ "$key" == xrandr/* ]] && unset "SELECTIONS[$key]"
  done
  return 0
}

display_rebuild_args() {
  local key out args=""
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    out=${key#xrandr/}
    args+="--output $out ${SELECTIONS[$key]} "
  done < <(printf '%s\n' "${!SELECTIONS[@]}" | grep '^xrandr/' | LC_ALL=C sort)
  args=${args% }
  [ -n "$args" ] && user_set dwm/xrandr "$args"
  return 0
}

# Parse an existing dwm/xrandr string (from a profile, the --xrandr flag, or
# detect_existing_setup's xinitrc read-back) into per-output segments so the
# guided menu can edit one monitor without losing the others. Existing
# xrandr/* keys win (mid-session edits already in progress); tokens before
# the first --output (raw Custom… prefixes) don't seed — the Custom… escape
# hatch owns those strings and any guided edit rebuilds without them.
display_seed_segments() {
  local args; args=$(state_get dwm/xrandr)
  case "$args" in off|none|"") return 0 ;; esac
  local key
  for key in "${!SELECTIONS[@]}"; do
    [[ "$key" == xrandr/* ]] && return 0
  done
  local tok out="" seg=""
  for tok in $args; do
    if [ "$tok" = "--output" ]; then
      if [ -n "$out" ] && [ "$out" != "__pending" ]; then
        state_set "xrandr/$out" "${seg# }"
      fi
      out="__pending"; seg=""
    elif [ "$out" = "__pending" ]; then
      out="$tok"
    elif [ -n "$out" ]; then
      seg+=" $tok"
    fi
  done
  if [ -n "$out" ] && [ "$out" != "__pending" ]; then
    state_set "xrandr/$out" "${seg# }"
  fi
  return 0
}

# One-line status for the per-monitor menu: the queued (not yet applied)
# segment when one exists, else what the output is running right now.
display_output_desc() {
  local queued="${SELECTIONS[xrandr/$1]:-}"
  if [ -n "$queued" ]; then
    echo "queued: $queued"
    return 0
  fi
  local cur
  cur=$(detect_xrandr_current "$1")
  if [ -n "$cur" ]; then
    echo "current: ${cur% *} @ ${cur##* }Hz"
  else
    echo "connected, no active mode"
  fi
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
