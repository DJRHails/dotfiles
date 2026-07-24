# Glassine migration runbook

On 2026-07-23 this repo's at-rest encryption moved from transcrypt to
[glassine](https://github.com/DJRHails/glassine) (sops envelopes, SSH-key
recipients in `.sops.yaml`). Same globs, same 188 files — see `.gitattributes`.
History was NOT rewritten: pre-migration blobs remain transcrypt ciphertext
(readable per docs/legacy-transcrypt.md).

## Per-clone cutover (every host with a checkout: trifle, bonbon, taffy, …)

After pulling the migration commit, run once per clone:

```bash
cd ~/.files \
  && { command -v sops >/dev/null || brew install sops 2>/dev/null \
      || { mkdir -p ~/.local/bin \
           && curl -fsSL "https://github.com/getsops/sops/releases/download/v3.13.3/sops-v3.13.3.linux.$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')" \
              -o ~/.local/bin/sops && chmod +x ~/.local/bin/sops; }; } \
  ; command -v glassine >/dev/null || { mkdir -p ~/.local/bin \
      && curl -fsSL https://raw.githubusercontent.com/DJRHails/glassine/main/glassine \
         -o ~/.local/bin/glassine && chmod +x ~/.local/bin/glassine; } \
  ; glassine init \
  && transcrypt --uninstall --yes 2>/dev/null \
  ; { glassine status || echo 'status-failed'; } \
      | awk '$1 !~ /^(encrypted|empty)$/' | grep . && echo 'CHECK FAILED' || echo OK
```

What it does: installs sops (≥3.10) + glassine if missing (brew where present,
else the GitHub release binary — bonbon and taffy have no brew), `glassine init`
configures the filters and re-smudges any still-ciphertext worktree files,
then transcrypt's config/hooks/cached-plaintext are removed. The last line
prints nothing but OK when every managed file is an envelope; any other
outcome — a plaintext blob, a missing tool, `glassine status` itself failing —
prints the offending lines and CHECK FAILED (never a false OK).

Notes:

- **Recipients.** `.sops.yaml` holds the six keys published at
  github.com/DJRHails.keys. A host whose key is not among them cannot decrypt
  — add it from an authorized host with `glassine allow <key.pub | github:user>`
  and push (glassine rotates the envelopes automatically). Passphrase-protected
  SSH keys are not supported by sops' SSH support.
- **Pre-commit hook.** transcrypt's vendored hook chain lived in
  `.git/hooks/pre-commit` (untracked). Replace it per clone with:

  ```bash
  printf '%s\n' '#!/usr/bin/env bash' 'set -e' \
    '"$(git rev-parse --show-toplevel)"/scripts/check-crypt-patterns.sh' \
    'glassine check' > .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
  ```

- **Old zshrc.** If shells error on sourcing encrypted `.zsh` modules right
  after pulling (before `glassine init`), the rendered `~/.zshrc` predates the
  envelope detection — re-run `./bootstrap.sh` (or just run `glassine init`,
  which decrypts the worktree and makes the question moot).
- **Crossing the boundary.** Any checkout/rebase that crosses the migration
  commit can leave managed files as raw envelopes in the worktree (the smudge
  runs while `.gitattributes` is mid-transition). Harmless — re-run
  `glassine init` to re-smudge them.
- **Docker.** `.dockerignore` must keep excluding every `.gitattributes`
  glassine path — the build context is the decrypted worktree.
