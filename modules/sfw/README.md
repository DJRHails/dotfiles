# sfw — Socket Firewall Free

[Socket Firewall Free](https://github.com/SocketDev/sfw-free) wraps a package
manager command in an ephemeral HTTP proxy and blocks known-malicious packages
(Socket's human-confirmed malware feed) before the artifact downloads, across
npm/pnpm/yarn, pip/uv, and cargo — transitive dependencies included. Chosen
over Datadog's supply-chain firewall because it covers uv and cargo (scfw
covers only the npm/PyPI ecosystems: npm, pip, poetry), needs zero config or
API key, and is a single static binary.

## What this module does

- `install.sh` downloads the prebuilt release binary to `~/.local/bin/sfw`
  (no brew formula or apt package exists). Idempotent: skips when `sfw` is
  already on PATH.
- `aliases.zsh` routes the *fetching* subcommands of npm/pnpm/yarn/pip/uv/cargo
  (and all of npx/uvx) through `sfw` in interactive shells. Hot non-fetching
  paths (`uv run`, `cargo build`) are left alone — sfw costs ~0.5s per
  invocation. Bypass a single call with `command npm …`.
- `ensure_sfw_fresh` in modules/dotfiles-autoupdate/update.sh re-downloads the
  binary daily on any version drift — Socket drops support for old versions,
  so a stale binary silently stops filtering. It manages only the
  `~/.local/bin/sfw` copy; an sfw resolved from anywhere else on PATH is not
  refreshed (install.sh warns when it sees one).

## Known limits (accepted)

- **Cache passthrough**: already-cached artifacts trigger no network request,
  so there is nothing to check. Fine — the cache was checked when it was
  filled (post-adoption).
- **Custom registries** (e.g. registry.tiptap.dev) pass through unchecked —
  Socket Free only filters public registries. Verified it does not break them.
- **Auto-fetch leak**: `cargo build` / `uv run` after a *manual* manifest edit
  fetch without sfw, because only install-ish subcommands are wrapped. An
  `add`/`sync`/`fetch` first stays covered.
- **Alternate entry points**: `python -m pip install` (and any tool invoked
  through an interpreter rather than its own name) bypasses the wrappers.
  Space-separated option values also confuse verb detection (`npm --prefix p
  install` falls through unwrapped); `--flag=value` forms are handled.
- **Non-interactive shells** (scripts, CI, agent Bash calls) invoke the real
  binaries directly. Wrapping those needs PATH shims — deliberately not done
  here until the fail-mode of a Socket API outage is understood.
- **Telemetry**: the free tier sends anonymous usage telemetry (package names,
  machine id) to Socket; not configurable.
