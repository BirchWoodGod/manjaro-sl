#!/usr/bin/env bash
# DEPRECATED: build_suckless.sh has been replaced by manjaro-sl.sh.
# This wrapper forwards all arguments unchanged. The old script's full flow
# (install + configure, no debloat/tweaks concept) is equivalent to the new
# full flow with empty debloat/tweak selections (both steps are no-ops when
# nothing is selected — see debloat_apply/tweaks_apply), so plain forwarding
# — rather than a narrower `--only install` — is what actually restores
# flags like --interface/--battery/--modkey/--remove-de working through this
# wrapper the way they did on the old script.
echo "build_suckless.sh is deprecated — use ./manjaro-sl.sh (forwarding to it now)." >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/manjaro-sl.sh" "$@"
