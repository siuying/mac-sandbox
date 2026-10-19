#!/bin/bash
# Run on your laptop. Turns a Mac on your network into a sandbox host and configures
# this laptop to reach its VMs. Safe to re-run.
#
# Usage: ./install.sh [USER@]HOST [VAR=value ...]
#   e.g. ./install.sh me@mini.local
#        ./install.sh me@mini.local VMS="agent-1" VM_MEMORY_MB=24576
#        ./install.sh me@studio.local TEMPLATE_SOURCE=ghcr.io/me/agent-xcode27:latest
#
# The host needs: Apple silicon, Remote Login on (System Settings > General > Sharing),
# and its user logged in to the desktop.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
target=${1:-}
[[ -n "$target" ]] || { sed -n '2,11p' "$0"; exit 1; }
shift

overrides=""
for arg in "$@"; do
  [[ "$arg" =~ ^[A-Z_]+= ]] || { echo "error: expected VAR=value, got '$arg'" >&2; exit 1; }
  overrides+=$(printf '%s=%q' "${arg%%=*}" "${arg#*=}")$'\n'
done

# shellcheck source=config.env
. "$ROOT/config.env"
log() { printf '\033[1m==> %s\033[0m\n' "$*" >&2; }

##########################################################
# SSH access to the host

if ! ls "$HOME"/.ssh/id_{ed25519,ecdsa,rsa}.pub >/dev/null 2>&1; then
  log "Creating an SSH key for this laptop"
  ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "$(id -un)@$(hostname -s)"
fi

if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$target" true 2>/dev/null; then
  log "Copying your SSH key to $target (asks for its password once)"
  ssh-copy-id "$target"
fi

##########################################################
# Copy this repo to the host and run its bootstrap

log "Copying mac-sandbox to $target:~/$HOST_DIR"
COPYFILE_DISABLE=1 tar -C "$ROOT" --exclude .git --exclude config.local.env -cf - . |
  ssh "$target" "mkdir -p $HOST_DIR && tar -C $HOST_DIR -xf -"
if [[ -n "$overrides" ]]; then
  printf '%s' "$overrides" | ssh "$target" "cat > $HOST_DIR/config.local.env"
fi

log "Bootstrapping $target (the first run downloads and provisions the Xcode image; expect an hour or more)"
ssh -t "$target" "/bin/bash $HOST_DIR/host/bootstrap.sh"

##########################################################
# Configure this laptop

mkdir -p "$HOME/.local/bin"
ln -sf "$ROOT/bin/sbx" "$HOME/.local/bin/sbx"
sbx="$ROOT/bin/sbx"

# shellcheck disable=SC2016
read -r -a vms <<<"$(ssh "$target" "/bin/bash -c '. $HOST_DIR/lib.sh && echo \$VMS'")"
"$sbx" add-host "$target" "${vms[@]}"
for vm in "${vms[@]}"; do
  "$sbx" enroll "$vm"
  "$sbx" auth "$vm"
done

cat <<EOF

Done. Sandboxes on $target: ${vms[*]}

  sbx shell ${vms[0]}            # SSH in
  cd your-repo && sbx push ${vms[0]}   # send code to ~/work/<repo> in the VM
  sbx fetch ${vms[0]}            # bring the agents' branches back

Paseo Desktop: Settings > Add host > Remote SSH, one per VM:
$(printf '  ssh://%s\n' "${vms[@]}")
Make sure ~/.local/bin is on your PATH.
EOF

if ! security find-generic-password -s mac-sandbox -a CLAUDE_CODE_OAUTH_TOKEN >/dev/null 2>&1; then
  cat <<EOF

Claude isn't authorized in the sandboxes yet:
  claude setup-token                      # prints a long-lived token
  sbx secret CLAUDE_CODE_OAUTH_TOKEN      # paste it; stored in your Keychain
$(printf '  sbx auth %s\n' "${vms[@]}")
Optional: sbx secret GH_TOKEN / OPENAI_API_KEY the same way (Codex also picks up ~/.codex/auth.json).
EOF
fi
