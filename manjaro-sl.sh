#!/usr/bin/env bash
# manjaro-sl — Manjaro debloater + DWM/suckless setup TUI.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for m in exec tui state; do
  [ -f "$REPO_ROOT/lib/$m.sh" ] && source "$REPO_ROOT/lib/$m.sh"  # shellcheck source=/dev/null
done

main() {
  echo "manjaro-sl: scaffold (menus arrive in later tasks)"
}
main "$@"
