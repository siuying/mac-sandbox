#!/bin/bash
# Manage sandbox VMs on this host. Each VM runs under a launchd agent so it survives
# SSH disconnects and restarts if it crashes.
#
# Usage: host/vm.sh create|start|stop|reset|delete|wait|status VM
#        host/vm.sh exec [-i] [-t] VM COMMAND...
#        host/vm.sh nc VM      (SSH ProxyCommand: connect stdio to the VM's port 22)
set -euo pipefail
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

label() { echo "com.mac-sandbox.vm.$1"; }
plist() { echo "$HOME/Library/LaunchAgents/$(label "$1").plist"; }
domain="gui/$(id -u)"

write_plist() {
  local vm=$1 log_file="$HOME/Library/Logs/mac-sandbox/$1.log"
  mkdir -p "$(dirname "$log_file")" "$HOME/Library/LaunchAgents"
  cat >"$(plist "$vm")" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$(label "$vm")</string>
  <key>ProgramArguments</key>
  <array><string>$(command -v tart)</string><string>run</string><string>--no-graphics</string><string>$vm</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>StandardOutPath</key><string>$log_file</string>
  <key>StandardErrorPath</key><string>$log_file</string>
</dict>
</plist>
EOF
}

start() {
  write_plist "$1"
  launchctl bootout "$domain/$(label "$1")" 2>/dev/null || true
  launchctl bootstrap "$domain" "$(plist "$1")" ||
    die "launchctl bootstrap failed; is $(id -un) logged in to the GUI on this Mac? (enable automatic login)"
}

stop() {
  if vm_running "$1"; then
    tart stop --timeout 120 "$1" || true
  fi
  launchctl bootout "$domain/$(label "$1")" 2>/dev/null || true
}

create() {
  local vm=$1
  if ! vm_exists "$vm"; then
    vm_exists "$TEMPLATE" || die "template $TEMPLATE does not exist; run host/bootstrap.sh"
    log "Creating $vm from $TEMPLATE"
    tart clone "$TEMPLATE" "$vm"
    tart set "$vm" --random-mac --random-serial
    if [[ -n "$VM_CPU" && -n "$VM_MEMORY_MB" ]]; then
      tart set "$vm" --cpu "$VM_CPU" --memory "$VM_MEMORY_MB"
    fi
  fi
  start "$vm"
  wait_for_agent "$vm"
}

cmd=${1:-}
shift || true
case "$cmd" in
  create) create "${1:?VM name}" ;;
  start) start "${1:?VM name}"; wait_for_agent "$1" ;;
  stop) stop "${1:?VM name}" ;;
  delete) stop "${1:?VM name}"; rm -f "$(plist "$1")"; tart delete "$1" ;;
  reset)
    vm=${1:?VM name}
    stop "$vm"
    vm_exists "$vm" && tart delete "$vm"
    create "$vm"
    ;;
  wait) wait_for_agent "${1:?VM name}" ;;
  exec) exec tart exec "$@" ;;
  nc) exec nc "$(tart ip --wait 120 "${1:?VM name}")" 22 ;;
  status)
    tart list --source local
    for vm in $VMS; do
      printf '%s: ' "$vm"
      launchctl print "$domain/$(label "$vm")" 2>/dev/null | awk '/^\tstate =/ {print $3; f=1} END {if (!f) print "not loaded"}'
    done
    ;;
  *) sed -n '2,9p' "$0"; exit 1 ;;
esac
