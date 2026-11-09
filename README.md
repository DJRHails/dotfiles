<div align="center">
  
  ![Delta Logo](docs/delta.svg)
  
</div>

<h1 align="center">
  <strong>.files</strong>
</h1>

`.files` will sanely setup a machine, and provide quality of life improvements.

A bash bootstrapper (`bootstrap.sh`) installs and links a chosen set of **modules** (shell, git,
language toolchains, coding-agent config, package-install guards) on macOS or Ubuntu, so a new
laptop or server gets my working setup in one command. It is written for my own machines and
accounts, so treat it as something to borrow ideas from rather than install wholesale; see
[Before you borrow](#before-you-borrow).

## :gear: Installation
```bash
git clone --recurse-submodules https://github.com/DJRHails/dotfiles.git ~/.files
cd ~/.files
./bootstrap.sh --cli --yes

# Custom config
./bootstrap.sh
```

<div align="center">

![Installation Example](docs/dotfiles.gif)

</div>

| Flag          | Effect
| ------------- | ------
| `-c, --cli`   | Server profile: `zsh`, `ssh`, `git`, `python`, `node`, `piknik`, `tailscale`, `cloudflared`, `cloudflare`, `claude`, `agents`, `sfw`, `release-age`, `dotfiles-autoupdate`, plus whatever their `deps.conf` pulls in.
| `-y, --yes`   | Skip interactive questions (does not select every module).
| `-A, --all`   | Run every directory under `modules/`.
| `<modules>…`  | Install the named modules, e.g. `./bootstrap.sh git zsh`.

With no flags, `bootstrap.sh` asks module by module. For each selected module it creates the
links in `symlinks.conf` (and `symlinks.<os>.conf`), then runs `install.sh`, `install.<os>.sh`,
`setup.sh` and `setup.<os>.sh` where present.

## :package: Modules

| Module                  | Description
| ----------------------- | -----------
| :sparkle: `agents`      | Shared coding-agent config — AGENTS.md, skills, commands, and subagents, symlinked into each agent's config dir.
| `alwayson`              | Keep a macOS machine awake (pmset, with backup/restore).
| `askllm`                | Ask an LLM from the terminal (git submodule behind `bin/askllm`).
| `ci-runners`            | Self-hosted GitHub Actions runner pools, declared in `runners.conf` and reconciled by `provision.sh` (run by hand; no installer, so `bootstrap.sh` skips it).
| :sparkle: `claude`      | Claude Code setup — settings, guardrail hooks, MCP servers, statusline.
| `cloudflare`            | Cloudflare's unified `cf` CLI (DNS, zones, R2, …), authenticated by a long-lived API token in the module's gitignored `.env`.
| `cloudflared`           | Cloudflare Tunnel client via signed apt repo.
| `code`                  | VS Code settings.
| `codex`                 | Codex CLI configuration.
| `docker`                | Docker runtime via Colima (macOS) or Docker Engine (Linux).
| `dotfiles-autoupdate`   | Once-daily, fast-forward-only pull of `~/.files` (launchd, systemd timer or cron); carries local changes on a stash and never pushes.
| `execblock`             | Execute code blocks from markdown files (`bin/execblock`).
| `explaincron`           | Explain crontab entries (`bin/explaincron`).
| `gdrive`                | Google Drive mount via ocamlfuse.
| `ghostty`               | Ghostty terminal config.
| :sparkle: `git`         | Git aliases, user-level config, and GitHub ssh/gpg onboarding.
| `go`                    | Go toolchain: brew where available, else the go.dev tarball into `~/.local/go`.
| `gpu-vm`                | On-demand cloud GPU pods over ssh, with cron-based idle reaping.
| `keybase`               | Keybase client.
| `node`                  | Node.js via NodeSource signed repo.
| `onepassword`           | 1Password app + `op` CLI, and the SSH agent config naming which vaults offer keys.
| `pentest`               | Aliases useful in penetration tests / deobfuscation.
| `pi`                    | pi coding agent config.
| `piknik`                | Cross-machine clipboard.
| `python`                | python3, uv, and virtualenv quality-of-life aliases.
| `raycast`               | Raycast (macOS launcher).
| `release-age`           | 7-day minimum release age for npm/pnpm/bun/uv/pip/cargo — a compromised release gets a week to be caught before it can install here.
| `rust`                  | Rust toolchain via rustup, plus cargo tools.
| `session-resume`        | `claude::resume` / `codex::resume`: resume a Claude or Codex session from either tool's session ID.
| `sfw`                   | Socket Firewall — blocks known-malicious packages on npm/pnpm/yarn/pip/uv/cargo installs.
| `slurm`                 | Slurm helper aliases for GPU clusters.
| `spend-watch`           | Daily digest of GitHub metered spend, posted to Slack (no installer; added to cron by hand, see its README).
| :sparkle: `ssh`         | ssh config template for commonly used machines.
| `tailscale`             | Tailscale VPN (exit-node advertising is opt-in).
| `tesseract`             | OCR via tesseract + imagemagick (`bin/ocr`).
| `vim`                   | vim & vim config.
| `zellij`                | Zellij terminal multiplexer with durable remote sessions.
| :sparkle: `zsh`         | zsh, aliases, completion, and the glue that loads every module's `*.zsh`.

### Dependencies

A module declares what it needs in its own `deps.conf` — one module name per
line, `#` comments and blank lines ignored:

```bash
# modules/claude/deps.conf
# install.sh installs `ant` with install::go_tool, which needs the go toolchain.
go
```

`bootstrap.sh` resolves those declarations before installing anything:
dependencies are pulled in even when you didn't select them (`./bootstrap.sh
claude` also installs `go`), and the install order is topologically sorted so a
module always runs after everything it depends on. Modules with no dependency
relationship keep the order you asked for.

Resolution failures abort the run rather than degrade — a dependency naming a
module that doesn't exist, or a cycle:

```
   [✖] module dependencies cannot be resolved (cycle detected)
   [✖]   claude -> go -> claude
   [✖]   unresolvable modules: claude go
```

Current edges:

| Module          | Needs    | Why
| --------------- | -------- | ---
| `agents`        | `python` | `skills/` ships `uv run` and `python3` entrypoints.
| `claude`        | `go`     | `install.sh` installs `ant` with `install::go_tool`.
| `claude`        | `node`   | `mcp.json` launches playwriter and context7 with `npx`.
| `claude`        | `python` | `settings.json` registers `python3 .../hooks/*.py` hooks.
| `cloudflare`    | `node`   | `install.sh` installs the `cf` CLI with `npm install -g`.
| `execblock`     | `python` | `bin/execblock` runs `uv run`.
| `explaincron`   | `python` | `bin/explaincron` builds its venv with `python3 -m venv`.
| `git`           | `rust`   | `setup.sh` seeds `~/.git-template` with `prek`, a cargo tool.
| `git`           | `ssh`    | `setup.github.sh` appends to `~/.ssh/config`, a symlink the ssh module owns.
| `gpu-vm`        | `ssh`    | The `Host gpu*` stanzas live in `modules/ssh/config.tmpl`.
| `pi`            | `node`   | `install.sh` uses `npm install -g`.
| `python`        | `git`    | `install.sh` writes `init.templateDir` into `~/.gitconfig.local`.
| `release-age`   | `node`   | `setup.sh` writes the age into npm's and pnpm's user config with their own `config set`.
| `session-resume`| `node`   | The session converter runs with node/tsx and installs with npm.
| `zellij`        | `python` | `install.*.sh` installs `humane` with `uv tool install`.

Shipping a `*.zsh` fragment is deliberately **not** an edge: `zshrc` globs
`$DOTFILES/modules/*/*.zsh` over the repo tree at shell startup, so nothing is
resolved at install time, and a `→ zsh` edge on every module would bury the real
ordering constraints.

## Tests

The suites under `tests/` cover the parts that delete files, rewrite config unattended or gate
package installs: symlink pruning, the daily auto-update, the package firewall and release-age
gate, the dependency resolver, and several of the agent hooks. Most of them run as pre-commit
hooks (`.pre-commit-config.yaml`, mirrored in `lefthook.yml`), alongside the secret scanners and
the encryption checks. There is no test CI.

```bash
prek run --all-files                     # the hooked checks (or: pre-commit run --all-files)
bash tests/module-deps.test.sh           # any suite, by hand
docker build -t dotfiles .               # ./bootstrap.sh --cli --yes on a clean Ubuntu 24.04
```

## Before you borrow

- **It's personal config.** `ssh/config.tmpl` names my machines, `onepassword` names my vaults,
  and `claude`/`agents` install my agent guardrails and skills. Read a module before running
  it, and don't run `--all` on your own machine.
- **Some paths are encrypted.** Files matching the `filter=glassine` rules in `.gitattributes`
  are encrypted at rest with [glassine](https://github.com/DJRHails/glassine), so in a public
  clone they are ciphertext and the modules that use them won't work.
- **macOS and Ubuntu only.** Other Linux distributions fail the platform check, and some modules
  ship an installer for one OS only (`alwayson` and `raycast` are macOS-only); look for
  `install.<os>.sh`.
- **Not pinned.** Some modules fetch the latest release or a vendor install script (`go`,
  `python`, `zsh`, `sfw`, and `tailscale` on Ubuntu), so two runs a month apart can install
  different versions.

## :zap: Inspired by
- [@holman](https://github.com/holman/dotfiles)
- [@alrra](https://github.com/alrra/dotfiles)
- [@denisdoro](https://github.com/denisidoro/dotfiles)
