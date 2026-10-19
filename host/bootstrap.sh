#!/bin/bash
# Set up this Mac as a sandbox host: Homebrew, Tart, the template image and the sandbox VMs.
# Idempotent: safe to re-run after a failure or to pick up config changes.
set -euo pipefail
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

[[ "$(uname -m)" == arm64 ]] || die "Apple silicon is required to run macOS VMs"

##########################################################
# Homebrew and Tart

if ! command -v brew >/dev/null; then
  log "Installing Homebrew (asks for your password)"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null ||
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >>"$HOME/.zprofile"
fi

# `tart exec` (used for provisioning) needs a recent Tart; older installs came from the cirruslabs tap.
if ! command -v tart >/dev/null || ! tart exec --help >/dev/null 2>&1; then
  log "Installing Tart"
  if brew list --formula cirruslabs/cli/tart >/dev/null 2>&1; then
    brew uninstall cirruslabs/cli/tart
  fi
  brew install openai/tools/tart
fi

##########################################################
# VM size: by default the sandboxes split the host, leaving 8 GB for macOS itself.

vm_count=$(wc -w <<<"$VMS")
host_cpus=$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || sysctl -n hw.physicalcpu)
host_mem_mb=$(($(sysctl -n hw.memsize) / 1024 / 1024))
share_mb=$(((host_mem_mb - 8192) / vm_count))
: "${VM_CPU:=$((host_cpus / vm_count > 4 ? host_cpus / vm_count : 4))}"
: "${VM_MEMORY_MB:=$((share_mb > 16384 ? 16384 : share_mb))}"
((VM_MEMORY_MB >= 8192)) || die "only $VM_MEMORY_MB MB RAM per sandbox; use fewer VMS (e.g. VMS=sbx-1) or set VM_MEMORY_MB"
export VM_CPU VM_MEMORY_MB
log "Sandbox size: $VM_CPU CPUs, $VM_MEMORY_MB MB RAM, $VM_DISK_GB GB disk"

##########################################################
# Template

if ! vm_exists "$TEMPLATE"; then
  if [[ -n "$TEMPLATE_SOURCE" ]]; then
    log "Pulling template $TEMPLATE_SOURCE"
    caffeinate -i tart clone "$TEMPLATE_SOURCE" "$TEMPLATE"
  else
    "$ROOT/host/build-image.sh"
  fi
fi

##########################################################
# Sandboxes

for vm in $VMS; do
  "$ROOT/host/vm.sh" create "$vm"
done

##########################################################
# Host power and login. VMs run in the GUI session, so the host must stay logged in and awake.

if [[ "$(pmset -g custom | awk '/^AC Power/ {f=1} f && $1 == "sleep" {print $2; exit}')" != 0 ]]; then
  log "Disabling sleep on AC power (asks for your password)"
  sudo pmset -c sleep 0 disksleep 0
fi

if ! defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser >/dev/null 2>&1; then
  log "Automatic login is off. Enable it in System Settings > Users & Groups so sandboxes come back after a reboot."
fi

"$ROOT/host/vm.sh" status
