#!/usr/bin/env zsh
# Behaviour suite for claude::resume (modules/claude/aliases.zsh): a session id
# or a unique prefix resolves to the transcript's recorded cwd and owning
# profile; an ambiguous prefix and a subagent-only id both refuse.
# Self-contained: `zsh -f tests/claude-resume.test.zsh`. Exits non-zero on failure.
set -u

script_dir="${0:A:h}"
aliases_zsh="$script_dir/../modules/claude/aliases.zsh"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
export HOME="$work/home"

ant_projects="$HOME/.claude-ant/projects"
default_projects="$HOME/.claude/projects"
mkdir -p "$work/proj-a" "$work/proj-b" "$work/proj-c"

# A transcript is one JSON record per line; only the cwd field matters here.
transcript() {
  local dir=$1 id=$2 cwd=$3
  mkdir -p "$dir"
  printf '{"type":"user","cwd":"%s","sessionId":"%s"}\n' "$cwd" "$id" > "$dir/$id.jsonl"
}

unique_id="aaaa1111-0000-4000-8000-000000000001"
sibling_id="aaaa2222-0000-4000-8000-000000000002"
default_id="bbbb3333-0000-4000-8000-000000000003"
subagent_id="cccc4444-0000-4000-8000-000000000004"
moved_id="dddd5555-0000-4000-8000-000000000005"

transcript "$ant_projects/-proj-a" "$unique_id" "$work/proj-a"
transcript "$ant_projects/-proj-b" "$sibling_id" "$work/proj-b"
transcript "$default_projects/-proj-c" "$default_id" "$work/proj-c"
transcript "$ant_projects/-proj-a/$unique_id/subagents" "$subagent_id" "$work/proj-a"
# The same session recorded under two project dirs after a cwd move: the newer
# transcript wins, so the older one is back-dated.
transcript "$ant_projects/-proj-a" "$moved_id" "$work/proj-a"
transcript "$ant_projects/-proj-b" "$moved_id" "$work/proj-b"
touch -t 202601010000 "$ant_projects/-proj-a/$moved_id.jsonl"

source "$aliases_zsh"
# The launchers print where they were called and with what, instead of
# starting claude.
claude::ant() { print "ANT $* in $PWD"; }
claude() { print "DEFAULT $* in $PWD"; }

fails=0
check() {
  if [[ $2 == "$3" ]]; then
    print "ok   $1"
  else
    print "FAIL $1: expected [$2] got [$3]"
    (( fails++ ))
  fi
}
check_rc() {
  if (( $2 == $3 )); then
    print "ok   $1"
  else
    print "FAIL $1: expected rc $2 got $3"
    (( fails++ ))
  fi
}

check "unique prefix resolves to the full id, cwd and ant profile" \
  "ANT --resume $unique_id in $work/proj-a" "$(claude::resume aaaa1111 2>&1)"
check "full id still resolves" \
  "ANT --resume $unique_id in $work/proj-a" "$(claude::resume "$unique_id" 2>&1)"
check "default-profile session routes through plain claude" \
  "DEFAULT --resume $default_id in $work/proj-c" "$(claude::resume bbbb3333 2>&1)"
check "same id under two project dirs follows the newest transcript" \
  "ANT --resume $moved_id in $work/proj-b" "$(claude::resume dddd5555 2>&1)"

ambiguous_out="$(claude::resume aaaa 2>&1)"
ambiguous_rc=$?
check_rc "ambiguous prefix refuses" 1 $ambiguous_rc
check "ambiguous prefix names both sessions" \
  "$unique_id $sibling_id" \
  "$(print -r -- "$ambiguous_out" | grep -o '[a-f0-9-]\{36\}' | sort | tr '\n' ' ' | sed 's/ $//')"

claude::resume cccc4444 >/dev/null 2>&1
check_rc "subagent-only id is not resumable" 1 $?
claude::resume zzzz >/dev/null 2>&1
check_rc "unknown id refuses" 1 $?
claude::resume >/dev/null 2>&1
check_rc "missing argument refuses" 1 $?

if (( fails > 0 )); then
  print "$fails failure(s)"
  exit 1
fi
print "all claude::resume checks passed"
