#!/bin/bash
# Build the template VM: clone $BASE_IMAGE, run guest/provision.sh inside it, save as $TEMPLATE.
# Usage: host/build-image.sh [--push OCI_REF]
set -euo pipefail
. "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

push_ref=""
if [[ "${1:-}" == "--push" ]]; then
  push_ref=${2:?--push needs an OCI reference}
fi

[[ -n "$VM_CPU" && -n "$VM_MEMORY_MB" ]] || die "VM_CPU and VM_MEMORY_MB must be set (host/bootstrap.sh derives them)"
for step in $SETUP; do
  [[ -f "$ROOT/guest/setup/$step.sh" ]] || die "unknown setup step '$step': no guest/setup/$step.sh"
done

vm="$TEMPLATE-build"
log_file="$HOME/Library/Logs/mac-sandbox/$vm.log"
mkdir -p "$(dirname "$log_file")"

if vm_exists "$vm"; then
  tart stop "$vm" >/dev/null 2>&1 || true
  tart delete "$vm"
fi

log "Cloning $BASE_IMAGE (the first pull downloads tens of GB)"
caffeinate -i tart clone "$BASE_IMAGE" "$vm"
tart set "$vm" --cpu "$VM_CPU" --memory "$VM_MEMORY_MB"
# Disks can only grow; keep the base image's size if it is already larger.
tart set "$vm" --disk-size "$VM_DISK_GB" 2>/dev/null || log "Keeping the base image's disk size"

log "Booting $vm (log: $log_file)"
tart run --no-graphics "$vm" >"$log_file" 2>&1 &
run_pid=$!
trap 'tart stop "$vm" >/dev/null 2>&1 || true' EXIT
wait_for_agent "$vm"

log "Provisioning"
tar -C "$ROOT/guest" -cf - . |
  tart exec -i "$vm" /bin/sh -c 'rm -rf /tmp/mac-sandbox && mkdir -p /tmp/mac-sandbox && tar -C /tmp/mac-sandbox -xf -'
caffeinate -i tart exec "$vm" /usr/bin/env BASE_IMAGE="$BASE_IMAGE" SETUP="$SETUP" /bin/zsh -l /tmp/mac-sandbox/provision.sh
tart exec "$vm" /bin/rm -rf /tmp/mac-sandbox

log "Shutting down $vm"
tart stop --timeout 120 "$vm"
wait "$run_pid" || true
trap - EXIT

if vm_exists "$TEMPLATE"; then
  tart delete "$TEMPLATE"
fi
tart rename "$vm" "$TEMPLATE"
log "Template $TEMPLATE is ready"

if [[ -n "$push_ref" ]]; then
  log "Pushing $TEMPLATE to $push_ref"
  tart push "$TEMPLATE" "$push_ref"
fi
