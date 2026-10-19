# mac-sandbox

macOS VMs for running coding agents with `--dangerously-skip-permissions`, on a separate Mac on
your network. The tools inside the VMs are configurable (see [Tools](#tools)). Your laptop drives the
VMs over SSH and Paseo. Code goes in and out through git, so the VMs never get credentials to your
laptop, the host, or GitHub (unless you give them a `GH_TOKEN`).

```
laptop ── ssh ──> host Mac (Tart, launchd) ── ProxyCommand ──> sbx-1, sbx-2 (macOS + your tools)
```

Inspired by [vibe](https://github.com/lynaghk/vibe); built on [Tart](https://github.com/openai/tart)
and Cirrus Labs' `macos-*-xcode` images.

## Set up a host

On the host Mac (Apple silicon): turn on **Remote Login**, enable **automatic login**, and stay logged in.
Then, from your laptop:

    ./install.sh you@mini.local

That one command:

1. copies your SSH key to the host (asks for its password once),
2. copies this repo to `~/mac-sandbox` on the host and runs `host/bootstrap.sh` there, which installs
   Homebrew and Tart, builds the `agent-xcode27` template (`host/build-image.sh` + `guest/provision.sh`),
   creates `sbx-1` and `sbx-2` as launchd-managed VMs, and turns off sleep on AC power,
3. installs `sbx` to `~/.local/bin`, adds the VMs to `~/.ssh/config`, authorizes your key in them,
   and copies your stored secrets in.

Re-running it is safe: finished steps are skipped. Override settings from `config.env` on the command line:

    ./install.sh you@mini.local VMS="sbx-1" VM_MEMORY_MB=24576

### Faster setup for more hosts

Building the template downloads tens of GB and takes a while. Build once, push it to a private registry,
and let other hosts pull it:

    ssh you@mini.local 'mac-sandbox/host/build-image.sh --push ghcr.io/you/agent-xcode27:latest'   # after `tart login ghcr.io`
    ./install.sh you@studio.local TEMPLATE_SOURCE=ghcr.io/you/agent-xcode27:latest

The template contains no secrets; credentials are added per VM by `sbx auth`.
Xcode's license terms still apply to where you push it, so keep the registry private.

## Credentials

Stored in your laptop's login Keychain and copied into `~/.config/mac-sandbox/env` in each VM:

    claude setup-token                       # long-lived Claude token
    sbx secret CLAUDE_CODE_OAUTH_TOKEN
    sbx secret GH_TOKEN                      # optional: fine-grained, repo-scoped
    sbx secret OPENAI_API_KEY                # optional; or Codex uses a copy of ~/.codex/auth.json
    sbx auth sbx-1

Anything you put in a VM can be read by the agent running there.

## Daily use

    cd ~/src/myapp
    sbx push sbx-1             # current branch -> sbx-1:~/work/myapp
    sbx shell sbx-1            # or use Paseo, below
    sbx fetch sbx-1            # agents' branches -> sbx-1/* remote branches
    git diff main sbx-1/some-branch

**Paseo**: in Paseo Desktop, Settings > Add host > Remote SSH > `ssh://sbx-1`. The daemon in each VM
listens on `127.0.0.1:6767` and starts at login. Open `~/work/myapp` as a project and use worktrees
to run several agents in one VM.

**Reset** a VM to a fresh copy of the template (its disk is discarded):

    sbx reset sbx-1

## Tools

Tools are managed by [mise](https://mise.jdx.dev). `guest/mise.toml` lists them and becomes the VM's
global mise config:

```toml
[tools]
ruby = "latest"
node = "lts"
gh = "latest"
codex = "latest"
claude = "latest"
"npm:@getpaseo/cli" = "latest"
```

Add, remove or pin versions there. Anything in the [mise registry](https://mise.jdx.dev/registry.html)
works, as do `npm:`, `pipx:`, `cargo:`, `aqua:` and `github:` backends. Repos you push to `~/work` can
bring their own `mise.toml`; it's trusted automatically, so agents (or a Paseo `worktree.setup` of
`mise install`) get the project's versions.

### Setup steps

Things mise can't do are scripts in `guest/setup/<name>.sh`, run in the order given by `SETUP` in
`config.env`:

| Step | Does |
|---|---|
| `xcode` | first-launch setup and an iOS simulator runtime for the base image's Xcode |
| `mise` | installs mise and everything in `guest/mise.toml` |
| `claude` | skips Claude Code's first-run onboarding |
| `paseo` | runs the Paseo daemon at login |

Default: `SETUP="xcode mise claude paseo"`. A new step runs as `admin` in a login zsh inside the
template VM; it can append a `name: version` line to `$SANDBOX_INFO` (shown by `sbx info`).

### Rebuilding

Tools are baked into the template. After editing `guest/mise.toml` or `guest/setup/`:

    ./install.sh you@mini.local                                   # copies your changes to the host
    ssh you@mini.local 'mac-sandbox/host/build-image.sh' && sbx reset sbx-1

## Layout

| Path | Runs on | Purpose |
|---|---|---|
| `install.sh` | laptop | one-command setup of a host + this laptop |
| `bin/sbx` | laptop | day-to-day CLI |
| `host/bootstrap.sh` | host | Homebrew, Tart, template, VMs, power settings |
| `host/build-image.sh` | host | build (and optionally push) the template |
| `host/vm.sh` | host | create/start/stop/reset VMs; SSH ProxyCommand |
| `guest/provision.sh` | template VM | base setup (SSH, git, secrets loading), then runs `SETUP` |
| `guest/mise.toml` | template VM | tools and versions |
| `guest/setup/*.sh` | template VM | setup steps mise can't do |
| `config.env` | all | defaults, including `SETUP` |

## Limits

- macOS licensing allows two macOS VMs running per host; that's the default `VMS`.
- The guest macOS can't be newer than the host's. `macos-tahoe-xcode:27` (macOS 26) works on macOS 26+
  hosts; use `BASE_IMAGE=ghcr.io/cirruslabs/macos-golden-gate-xcode:27` on macOS 27 hosts.
- VMs have outbound internet access (agents need it). The sandbox protects your machines, not secrets you
  put inside the VM.
- Agents in the same VM can see each other's worktrees. Use separate VMs when that matters.
