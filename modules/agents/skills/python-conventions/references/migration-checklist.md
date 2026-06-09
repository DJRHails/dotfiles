# Migration Checklist

Comprehensive checklist for migrating Python projects to modern tooling.

## Before Migration

- [ ] **Determine layout**: `src/` or flat? Configure `[tool.uv.build-backend]` if flat
- [ ] **Decide uv.lock strategy**: app (commit) vs library (.gitignore)
- [ ] **Backup current state**: Create a branch or tag before starting

## Migration Recipes

### From requirements.txt + pip

**For standalone scripts**: Convert to PEP 723 inline metadata (see [pep723-scripts.md](./pep723-scripts.md))

**For projects**:

```bash
uv init --bare
# Add each dependency with uv (not by editing pyproject.toml)
uv add requests rich
uv sync
```

Then delete `requirements.txt`, `requirements-dev.txt`, and old virtualenvs.

### From setup.py / setup.cfg

1. `uv init --bare` to create pyproject.toml
2. `uv add` each dependency from `install_requires`
3. `uv add --group dev` for dev dependencies
4. Copy non-dependency metadata to `[project]`
5. Delete `setup.py`, `setup.cfg`, `MANIFEST.in`

### From flake8 + black + isort

1. Remove old tools, add ruff: `uv add --group dev ruff`
2. Delete `.flake8`, `[tool.black]`, `[tool.isort]` configs
3. Add ruff configuration (see [ruff-config.md](./ruff-config.md))
4. Run `uv run ruff check --fix . && uv run ruff format .`

### From mypy / pyright

1. Remove old tools, add ty: `uv add --group dev ty`
2. Delete `mypy.ini`, `pyrightconfig.json`, or `[tool.mypy]`/`[tool.pyright]` sections
3. Run `uv run ty check src/`

## Cleanup Old Artifacts

Find and remove legacy linter comments:

```bash
# Find files with old linter pragmas
rg "# pylint:|# noqa:|# type: ignore" --files-with-matches

# Find missing __init__.py files
uv run ruff check --select=INP001 .
```

Remove these files after migration:
- [ ] `requirements.txt`, `requirements-dev.txt`
- [ ] `setup.py`, `setup.cfg`, `MANIFEST.in`
- [ ] `.flake8`, `mypy.ini`, `pyrightconfig.json`
- [ ] `tox.ini` (if not needed)
- [ ] `Pipfile`, `Pipfile.lock`
- [ ] Old virtual environments (`venv/`, `.venv/`)

## .gitignore Updates

Add these entries:

```gitignore
# Python
__pycache__/
*.py[cod]
.venv/

# Tools
.ruff_cache/
.ty/

# uv (for libraries only - apps should commit uv.lock)
# uv.lock
```

## pyproject.toml Sections to Remove

- [ ] `[tool.black]`
- [ ] `[tool.isort]`
- [ ] `[tool.mypy]`
- [ ] `[tool.pyright]`
- [ ] `[tool.pylint]`
- [ ] `[tool.flake8]` (if present)

## Post-Migration Easy Wins

Run these to modernize code automatically:

```bash
# Pyupgrade modernization (typing, syntax)
uv run ruff check --select=UP --fix .

# Unnecessary variable assignments before return
uv run ruff check --select=RET504 --fix .

# Simplifications (conditionals, comprehensions)
uv run ruff check --select=SIM --fix .

# Remove commented-out code
uv run ruff check --select=ERA --fix .
```

## CI Cleanup

- [ ] Remove scheduled CI triggers (activity without progress is theater)
- [ ] Update CI to use `uv sync` and `uv run`
- [ ] Pin GitHub Actions to specific versions
- [ ] Set up security tooling (see [security-setup.md](./security-setup.md))

## Gradual ty Adoption

For legacy codebases with many type errors, start lenient:

```toml
[tool.ty.terminal]
error-on-warning = true

[tool.ty.environment]
python-version = "3.11"

[tool.ty.rules]
# Start with these ignored for legacy codebases
possibly-missing-attribute = "ignore"
unresolved-import = "ignore"
invalid-argument-type = "ignore"
not-subscriptable = "ignore"
unresolved-attribute = "ignore"
```

Remove rules as you fix errors. Track progress:

```bash
# Count remaining issues
uv run ty check src/ 2>&1 | grep -c "error"
```

## Supply Chain Security

- [ ] Add pip-audit to dependency groups
- [ ] Configure Dependabot with 7-day cooldown
- [ ] Pin exact versions in production (`==` not `>=`)

See [security-setup.md](./security-setup.md) for pip-audit and Dependabot configuration.

## Verification

After migration, verify everything works:

```bash
# Install all dependencies
uv sync --all-groups

# Run linting
uv run ruff check .
uv run ruff format --check .

# Run type checking
uv run ty check src/

# Run tests
uv run pytest

# Security audit
uv run pip-audit

# Build package (if distributable)
uv build
```
