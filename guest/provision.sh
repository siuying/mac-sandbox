#!/bin/zsh -l
# Runs inside the template VM (as admin) while building the image:
# base sandbox setup, then guest/setup/<name>.sh for each name in $SETUP, in order.
set -euxo pipefail

SANDBOX_DIR="$HOME/.mac-sandbox"
mkdir -p "$SANDBOX_DIR" "$HOME/.config/mac-sandbox" "$HOME/work" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

# Setup scripts append "name: version" lines here.
export SANDBOX_INFO="$SANDBOX_DIR/image-info.txt"
{
  echo "built_at_utc: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "base_image: ${BASE_IMAGE:-unknown}"
  echo "macos: $(sw_vers -productVersion)"
  echo "setup: ${SETUP:-}"
} > "$SANDBOX_INFO"

##########################################################
# Never sleep; sandboxes are reached over the network.

sudo pmset -a sleep 0 displaysleep 0 disksleep 0

##########################################################
# Secrets are never baked into the image. `sbx auth` writes them to
# ~/.config/mac-sandbox/env after a VM is created; load them in every shell.

if ! grep -q 'mac-sandbox/env' "$HOME/.zshenv" 2>/dev/null; then
  cat >> "$HOME/.zshenv" <<'EOF'
[[ -f ~/.config/mac-sandbox/env ]] && source ~/.config/mac-sandbox/env
EOF
fi

##########################################################
# Git: let the laptop `git push` straight into ~/work/<repo> checkouts.

git config --global init.defaultBranch main
git config --global receive.denyCurrentBranch updateInstead
git config --global user.name "Sandbox Agent"
git config --global user.email "agent@mac-sandbox.invalid"

##########################################################
# SSH: key-only. Keys are added per VM by `sbx enroll`; `tart exec` still works without them.

sudo systemsetup -setremotelogin on >/dev/null 2>&1 || true
# sshd uses the first value it reads, so sort before Apple's 100-macos.conf.
sudo tee /etc/ssh/sshd_config.d/000-mac-sandbox.conf >/dev/null <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF

##########################################################
# Setup steps

export HOMEBREW_NO_AUTO_UPDATE=1
brew update

for step in ${=SETUP:-}; do
  zsh -l "${0:A:h}/setup/$step.sh"
done

cat "$SANDBOX_INFO"
