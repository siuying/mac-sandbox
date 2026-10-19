#!/bin/zsh -l
# Claude Code settings for unattended use (install it via mise.toml).
set -euxo pipefail

# Skip the first-run onboarding; auth comes from CLAUDE_CODE_OAUTH_TOKEN.
if [[ ! -f ~/.claude.json ]]; then
  echo '{"hasCompletedOnboarding": true}' > ~/.claude.json
fi
