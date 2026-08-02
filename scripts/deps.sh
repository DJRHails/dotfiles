#!/usr/bin/env bash
. "$DOTFILES/scripts/core/main.sh"

# Module dependency resolution. A module declares what it needs in its own
# `deps.conf` (one module name per line); this walks those declarations,
# pulls in anything required but not selected, and orders the install so a
# module always runs after everything it depends on.
#
# Resolution failures are fatal rather than best-effort: installing in the
# wrong order (or skipping a dependency) leaves a half-configured machine that
# looks successful — the go module missing means `ant` is silently absent, the
# git module missing means python writes hook config nowhere. Better to stop.

# Emit the module names listed in a module's deps.conf, one per line.
# Blank lines and `#` comments are ignored, as in symlinks.conf.
deps::declared() {
  local -r conf="$1/deps.conf"
  [ -f "$conf" ] || return 0

  local line
  while read -r line || [[ -n "$line" ]]
  do
    line="${line%%#*}"
    line="${line//[[:space:]]/}"  # module names never contain spaces
    if [[ -n "$line" ]]; then
      printf '%s\n' "$line"
    fi
  done < "$conf"
}

# Name a concrete cycle, starting from a module that could not be ordered.
# Every such module has at least one unplaced dependency, so following those
# edges always closes a loop; the first repeated module marks where it starts.
# Reads `deps_of` and `placed` from deps::resolve_order via dynamic scoping.
deps::describe_cycle() {
  local module="$1"
  local -a path=()
  local -A on_path=()

  while [ -z "${on_path[$module]:-}" ]
  do
    on_path[$module]=1
    path+=("$module")
    local dep next=""
    for dep in ${deps_of[$module]}
    do
      [ -n "${placed[$dep]:-}" ] || { next="$dep"; break; }
    done
    module="$next"
  done

  # Drop the leading tail that runs into the cycle but is not part of it.
  local start=0 i
  for i in "${!path[@]}"
  do
    [ "${path[$i]}" = "$module" ] && { start=$i; break; }
  done

  local rendered="${path[$start]}"
  for ((i = start + 1; i < ${#path[@]}; i++))
  do
    rendered+=" -> ${path[$i]}"
  done
  printf '%s -> %s\n' "$rendered" "$module"
}

# Expand and reorder the global scanned_valid_modules (absolute module paths)
# so every module follows its dependencies. Returns 1 — aborting the bootstrap
# — on an unknown dependency name or a cycle.
deps::resolve_order() {
  [ "${#scanned_valid_modules[@]}" -gt 0 ] || return 0

  local -A deps_of=() discovered=()
  local -a graph=()

  # Breadth-first walk from the selected modules. `graph` grows as
  # dependencies are found, and doubles as the queue — indexing it with a
  # cursor rather than shifting keeps the discovery order for the tie-break
  # below.
  local -a frontier=("${scanned_valid_modules[@]}")
  local cursor=0
  while [ "$cursor" -lt "${#frontier[@]}" ]
  do
    local module_dir="${frontier[$cursor]}"
    local module="${module_dir##*/}"
    cursor=$((cursor + 1))

    [ -n "${discovered[$module]:-}" ] && continue
    discovered[$module]=1
    graph+=("$module")

    local -a module_deps=()
    local dep
    while read -r dep
    do
      # A dependency naming a directory that doesn't exist is a typo, and
      # would otherwise resolve to a module that never installs anything.
      if [ ! -d "$DOTFILES/modules/$dep" ]; then
        log::error "module '$module' depends on '$dep', which is not a module in $DOTFILES/modules/"
        return 1
      fi
      module_deps+=("$dep")
      [ -n "${discovered[$dep]:-}" ] || frontier+=("$DOTFILES/modules/$dep")
    done < <(deps::declared "$module_dir")
    deps_of[$module]="${module_deps[*]}"
  done

  # Report what the dependency walk added on top of what was asked for.
  local -A selected=()
  local module
  for module_dir in "${scanned_valid_modules[@]}"
  do
    selected[${module_dir##*/}]=1
  done
  local -a pulled=()
  for module in "${graph[@]}"
  do
    [ -n "${selected[$module]:-}" ] || pulled+=("$module")
  done
  if [ "${#pulled[@]}" -gt 0 ]; then
    log::info "Added $(log::bold "${#pulled[@]} required module(s)"): ${pulled[*]}"
  fi

  # Kahn's algorithm over `graph`, which also supplies the tie-break: among
  # modules whose dependencies are all placed, the earliest-discovered one
  # goes first, so `bootstrap.sh a b c` keeps that order wherever
  # dependencies don't force otherwise.
  local -A placed=()
  local -a ordered=()
  local progress=1
  while [ "$progress" -eq 1 ]
  do
    progress=0
    for module in "${graph[@]}"
    do
      [ -n "${placed[$module]:-}" ] && continue

      local ready=1 dep
      for dep in ${deps_of[$module]}
      do
        [ -n "${placed[$dep]:-}" ] || { ready=0; break; }
      done
      [ "$ready" -eq 1 ] || continue

      placed[$module]=1
      ordered+=("$module")
      progress=1
    done
  done

  if [ "${#ordered[@]}" -ne "${#graph[@]}" ]; then
    log::error "module dependencies cannot be resolved (cycle detected)"
    for module in "${graph[@]}"
    do
      [ -n "${placed[$module]:-}" ] && continue
      log::error "  $(deps::describe_cycle "$module")"
      break
    done
    local -a unresolved=()
    for module in "${graph[@]}"
    do
      [ -n "${placed[$module]:-}" ] || unresolved+=("$module")
    done
    log::error "  unresolvable modules: ${unresolved[*]}"
    return 1
  fi

  scanned_valid_modules=()
  for module in "${ordered[@]}"
  do
    scanned_valid_modules+=("$DOTFILES/modules/$module")
  done
}
