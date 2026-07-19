#!/usr/bin/env bash
# DEPRECATED: build_suckless.sh has been replaced by manjaro-sl.sh.
# This wrapper forwards to the new entry point's install-only mode.
echo "build_suckless.sh is deprecated — use ./manjaro-sl.sh (forwarding to it now)." >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/manjaro-sl.sh" --only install "$@"
