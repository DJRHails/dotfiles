# release-age — a 7-day minimum release age for every package manager

A compromised package version does its damage in the first days after it is
published, before anyone has read it: the LiteLLM and Shai-Hulud releases were
caught within days, and everything that resolved `latest` in between ran them.
This module makes npm, pnpm, bun, uv, pip and cargo refuse any version
published less than 7 days ago, so a malicious release has to survive a week of
public scrutiny before it can install here. It is the counterpart of `sfw`,
which blocks versions already *known* to be malicious; the age gate covers the
ones nobody has looked at yet.

## What this module does

| tool  | setting                                        | unit     | needs       | applied by
| ----- | ---------------------------------------------- | -------- | ----------- | ---
| npm   | `min-release-age=7`                            | days     | npm 11.10   | `setup.sh`, `npm config set --location=user`
| pnpm  | `minimum-release-age=10080`                    | minutes  | pnpm 10.16  | `setup.sh`, `pnpm config set -g`
| bun   | `[install] minimumReleaseAge = 604800`         | seconds  | bun 1.3     | `bunfig.toml` → `~/.bunfig.toml`
| uv    | `exclude-newer = "7 days"`                     | duration | uv 0.9.17   | `uv.toml` → `~/.config/uv/uv.toml`
| pip   | `[global] uploaded-prior-to = P7D`             | ISO 8601 | pip 26.1    | `pip.conf` → `~/.config/pip/pip.conf`, plus `~/Library/Application Support/pip/` on macOS
| cargo | `[registry] global-min-publish-age = "7 days"` | duration | cargo 1.100 | `cargo-config.toml` → `~/.cargo/config.toml`

- **npm and pnpm are set in place, not symlinked.** `~/.npmrc` and pnpm's global
  rc also hold per-machine registry tokens that must not live in this repo.
  Each tool's own `config set` rewrites its file keeping every other line, and
  `setup.sh` reads the value back first, so re-running it writes nothing.
  Node 22 LTS bundles npm 10, which predates the key: on such a host `setup.sh`
  fails with the fix (`npm install -g npm`) rather than write a key that old
  npm would warn about on every call.
- **pip on macOS** prefers `~/Library/Application Support/pip/pip.conf` as soon
  as that directory exists and otherwise reads `~/.config/pip/pip.conf`, so
  `symlinks.macos.conf` links the same file into both.
- **The four symlinked files are user-level config.** A project's own `.npmrc`,
  `pnpm-workspace.yaml`, `bunfig.toml`, `[tool.uv]` / `uv.toml` or
  `.cargo/config.toml` overrides them, so a repo that needs a younger version
  can say so for itself.
- **Scripts and agents are covered**, unlike `sfw`'s interactive wrappers: these
  are config files, so a `uv add` inside a Claude Code Bash call is gated too.
- The daily autoupdate pulls but does not re-run setup; an existing host gets
  the gate from one `./bootstrap.sh -y release-age`.

Verified 2026-10-09 on npm 11.19, pnpm 10.32, bun 1.3.10, uv 0.11.8, pip 26.2.1
and cargo 1.97: each gate resolved an older version of a daily-published
package (`typescript@next`, `boto3`) than the ungated run, pnpm 10 and 12 both
accept the kebab-case key through `config set -g`, and cargo loads the file
without a warning.

## Bypassing it

| tool  | once                                                                    | standing exemption
| ----- | ----------------------------------------------------------------------- | ---
| npm   | `npm install --min-release-age=0 <pkg>`                                 | `min-release-age-exclude`
| pnpm  | `pnpm add --config.minimum-release-age=0 <pkg>`                         | `minimumReleaseAgeExclude`
| bun   | `bun add --minimum-release-age 0 <pkg>`                                 | `minimumReleaseAgeExcludes`
| uv    | `UV_EXCLUDE_NEWER="0 days" uv add <pkg>`                                | `exclude-newer-package = { <name> = false }`
| pip   | `pip install --uploaded-prior-to P0D <pkg>`                             | none
| cargo | `CARGO_RESOLVER_INCOMPATIBLE_PUBLISH_AGE=allow cargo update -p <crate>` | none

## Known limits (accepted)

- **Lockfiles win.** The gate runs at resolution time. `uv sync`, `npm ci`,
  `pnpm install --frozen-lockfile`, `bun install` against `bun.lock` and
  `cargo build` reuse whatever is pinned, including a version someone else
  pinned at one day old. Only `add`, `update`, `lock --upgrade` and unpinned
  installs are gated, which is also where the exposure is.
- **Security fixes wait a week too.** Use the bypass table when a patch matters
  more than the cooldown.
- **A brand-new package** whose only release is younger than 7 days cannot be
  installed without a bypass.
- **Fail direction differs.** npm, pnpm (strict mode is the default whenever
  the age is set explicitly) and uv error when nothing old enough satisfies
  the request. pip and cargo fail open on an index that publishes no upload
  times, which is most private mirrors.
- **cargo is inert until 1.100** (due 2026-11-12). rust-lang/cargo#17335
  stabilised the key; stable 1.99 and below ignore it silently, so the file
  starts working at the next `rustup update`. `cargo install` is never gated.
- **bun** layers a stability heuristic on the gate: it may skip a burst of
  rapid releases for an older one, up to a further 7 days, and an exact
  `pkg@x.y.z` request respects the gate but not the heuristic.
- **CI images** built from these dotfiles inherit the gate, so a build that
  must track `latest` has to opt out per project.
