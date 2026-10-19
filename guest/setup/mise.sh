#!/bin/zsh -l
# mise and the tools in guest/mise.toml.
set -euxo pipefail

brew install mise

# Shims for non-interactive shells (ssh commands, launchd jobs like Paseo); full activation for interactive ones.
# Appended last so mise's tools win over the base image's rbenv and Homebrew node.
if ! grep -q 'mise/shims' ~/.zprofile 2>/dev/null; then
  echo 'export PATH="$HOME/.local/share/mise/shims:$PATH"' >> ~/.zprofile
fi
if ! grep -q 'mise activate' ~/.zshrc 2>/dev/null; then
  echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
fi

# The base image ships its own Codex and Claude Code; remove them so only mise's versions exist.
brew uninstall --ignore-dependencies codex 2>/dev/null || true
brew uninstall --cask claude-code 2>/dev/null || true

mkdir -p ~/.config/mise
cp "${0:A:h}/../mise.toml" ~/.config/mise/config.toml

# npm: tools need node first.
mise install --yes node
mise install --yes
mise reshim

mise ls --current >> "$SANDBOX_INFO"
