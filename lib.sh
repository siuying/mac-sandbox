# Shared helpers for host-side scripts. Source, don't execute.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$ROOT/config.local.env" ]]; then
  # shellcheck source=/dev/null
  . "$ROOT/config.local.env"
fi
# shellcheck source=config.env
. "$ROOT/config.env"

# Non-login SSH sessions don't have Homebrew on PATH.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"

log() { printf '\033[1m==> %s\033[0m\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

vm_exists() { tart list --quiet | grep -qx "$1"; }

vm_running() {
  tart list --format json | /usr/bin/python3 -c '
import json, sys
name = sys.argv[1]
sys.exit(0 if any(v["Name"] == name and v["Running"] for v in json.load(sys.stdin)) else 1)
' "$1"
}

# Wait until the Tart guest agent answers, i.e. the VM has booted and `tart exec` works.
wait_for_agent() {
  local vm=$1 deadline=$((SECONDS + ${2:-300}))
  until tart exec "$vm" /usr/bin/true >/dev/null 2>&1; do
    ((SECONDS < deadline)) || die "timed out waiting for $vm to boot"
    sleep 3
  done
}
