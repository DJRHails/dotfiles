#!/usr/bin/env bash
# Behavior suite for modules/claude/hooks/response-gate.sh (Stop).
# Self-contained: `bash tests/response-gate.test.sh`. Exits non-zero on failure.
#
# The gate reopens finished turns, so both failure directions cost the user: a
# miss lets banned prose through, and a loop (no cap, no reset, code counted as
# prose, no off switch) burns turns until Claude Code's own continuation cap.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
hook="$repo_root/modules/claude/hooks/response-gate.sh"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
export XDG_STATE_HOME="$work/state"
# The LLM judge is off for the regex tests; the judge section turns it on
# against a stub `claude`, so the suite never makes a model call.
export CLAUDE_RESPONSE_GATE_JUDGE=0
gate_dir="$work/state/claude-response-gate"

fails=0
check() {
  if [[ $2 == "$3" ]]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s: expected [%s] got [%s]\n' "$1" "$2" "$3"
    ((fails++))
  fi
}
check_contains() {
  if [[ $3 == *"$2"* ]]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s: expected to contain [%s] got [%s]\n' "$1" "$2" "$3"
    ((fails++))
  fi
}

# gate <reply> <prompt_id> <stop_hook_active> — prints the exit code; stderr
# (what Claude would receive) lands in $work/err.
gate() {
  jq -cn --arg r "$1" --arg p "$2" --argjson a "$3" \
    '{session_id: "s1", prompt_id: $p, stop_hook_active: $a, last_assistant_message: $r, cwd: "/x"}' |
    bash "$hook" >"$work/out" 2>"$work/err"
  echo $?
}

clean='The rebase finished. Six commits sit on top of origin/main and the dirty files survived.'
dirty='Great question! It is worth noting that this robust solution leverages a tapestry of options.'

# -- clean prose passes without a word ---------------------------------------------
check clean-passes "0" "$(gate "$clean" p1 false)"
check clean-silent "" "$(cat "$work/err")"
check clean-no-state "1" "$([ -e "$gate_dir/s1.state" ] && echo 0 || echo 1)"

# -- banned prose is sent back with the rule, the text and the line ------------------
check dirty-blocks "2" "$(gate "$dirty" p1 false)"
check_contains dirty-names-rule "[sycophantic]" "$(cat "$work/err")"
check_contains dirty-names-vocab "[banned-vocab]" "$(cat "$work/err")"
check_contains dirty-gives-line "line 1" "$(cat "$work/err")"
check_contains dirty-asks-rewrite "Rewrite the whole reply" "$(cat "$work/err")"
check dirty-no-tmp-path "0" "$(grep -c '/reply.md' "$work/err")"
check dirty-state "p1 1" "$(cat "$gate_dir/s1.state")"
check_contains dirty-logged "rewrite 1" "$(cat "$gate_dir/gate.log")"

# -- one rewrite per prompt by default: the rewrite is not gated again, since a
#    reply that fails twice is usually a misfiring rule and every rewrite is a
#    full turn ---------------------------------------------------------------------
check cap-reached "0" "$(gate "$dirty" p1 true)"
check cap-silent "" "$(cat "$work/err")"
check cap-state-kept "p1 1" "$(cat "$gate_dir/s1.state")"
check_contains cap-logged "gave up after 1" "$(cat "$gate_dir/gate.log")"

# -- a new prompt starts the count over ---------------------------------------------
check new-prompt-gated "2" "$(gate "$dirty" p2 false)"
check new-prompt-state "p2 1" "$(cat "$gate_dir/s1.state")"
# A fresh reply resets even when the previous prompt hit the cap.
: >"$work/err"
check fresh-reply-resets "2" "$(gate "$dirty" p2 false)"
check fresh-reply-state "p2 1" "$(cat "$gate_dir/s1.state")"

# -- a higher cap re-checks the rewrite, then gives up ------------------------------
check cap-two-first "2" "$(CLAUDE_RESPONSE_GATE_MAX=2 gate "$dirty" p3 false)"
check cap-two-rewrite "2" "$(CLAUDE_RESPONSE_GATE_MAX=2 gate "$dirty" p3 true)"
check cap-two-state "p3 2" "$(cat "$gate_dir/s1.state")"
check cap-two-reached "0" "$(CLAUDE_RESPONSE_GATE_MAX=2 gate "$dirty" p3 true)"
check_contains cap-two-logged "gave up after 2" "$(cat "$gate_dir/gate.log")"

# -- without prompt_id the flag alone drives the count, and the cap still holds -------
no_pid() {
  jq -cn --arg r "$dirty" --argjson a "$1" \
    '{session_id: "s2", stop_hook_active: $a, last_assistant_message: $r}' |
    bash "$hook" >/dev/null 2>&1
  echo $?
}
check no-pid-first "2" "$(no_pid false)"
check no-pid-cap "0" "$(no_pid true)"
check no-pid-fresh-resets "2" "$(no_pid false)"

# -- code is exempt: fenced blocks and inline spans are stripped before linting -------
code=$'Run this:\n\n```bash\nrobust tapestry leverage  # great question\n```\n\nand the inline `great question` form too.'
check code-exempt "0" "$(gate "$code" p4 false)"
tilde=$'Output:\n\n~~~\nGreat question! robust tapestry\n~~~\n\nDone.'
check tilde-fence-exempt "0" "$(gate "$tilde" p5 false)"
prose_after_code=$'```\nclean block\n```\n\nGreat question! A robust tapestry.'
check prose-after-code-still-gated "2" "$(gate "$prose_after_code" p6 false)"

# -- long lines are cut so the feedback stays bounded -------------------------------
long="Great question! $(printf 'word %.0s' $(seq 1 120))"
gate "$long" p7 false >/dev/null
check long-lines-truncated "0" "$(awk 'length($0) > 240 {bad++} END {print bad + 0}' "$work/err")"

# -- shape heuristics are not enforced: the guide exempts concrete triads, and a
#    regex cannot tell them from abstract ones ---------------------------------------
lint="$repo_root/modules/agents/skills/prose-conventions/prose-lint.sh"
# No dots inside the items: prose-lint's triad regex stops at a full stop, so a
# filename like bunfig.toml would hide the match and make this test vacuous.
triad='The module links three files into place: the bun config, the uv config, and the pip config.'
printf '%s\n' "$triad" >"$work/triad.md"
# The sample must be a real lint hit, or the pass below proves nothing.
check triad-is-a-lint-hit "1" "$(bash "$lint" "$work/triad.md" 2>/dev/null | grep -c 'rule-of-three')"
check concrete-triad-passes "0" "$(gate "$triad" p11 false)"
check triad-silent "" "$(cat "$work/err")"
dirty_triad='Great question! It links the bun config, the uv config, and the pip config.'
check dirty-triad-still-blocks "2" "$(gate "$dirty_triad" p12 false)"
check dirty-triad-names-real-rule "1" "$(grep -c '\[sycophantic\]' "$work/err")"
check dirty-triad-omits-skipped "0" "$(grep -c 'rule-of-three' "$work/err")"
# Every skipped id is a category prose-lint actually emits, so a typo in the
# list cannot silently re-enable a rule.
while read -r id; do
  [[ -n "$id" ]] || continue
  check "skipped-id-is-a-lint-category-$id" "0" \
    "$([ "$(grep -cE "(\"|\\[|format_count )$id(\"|\\]| )" "$lint")" -ge 1 ] && echo 0 || echo 1)"
done < <(sed -n 's/^skipped_rules=(\(.*\))$/\1/p' "$hook" | tr ' ' '\n')
check skip-list-parsed "1" "$([ -n "$(sed -n 's/^skipped_rules=(\(.*\))$/\1/p' "$hook")" ] && echo 1 || echo 0)"

# -- the LLM judge keeps only the hits it calls real ---------------------------------
# A stub `claude` on PATH stands in for the model: it records its argv and env,
# then answers with $STUB_VERDICTS (or fails when STUB_FAIL is set).
mkdir -p "$work/bin"
cat >"$work/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$STUB_ARGS"
printf 'gate=%s\n' "${CLAUDE_RESPONSE_GATE:-unset}" >>"$STUB_ARGS"
[[ -n "${STUB_FAIL:-}" ]] && { echo "simulated outage" >&2; exit 1; }
printf '{"structured_output":{"verdicts":%s}}\n' "$STUB_VERDICTS"
STUB
chmod +x "$work/bin/claude"
judged() {
  PATH="$work/bin:$PATH" CLAUDE_RESPONSE_GATE_JUDGE=1 STUB_ARGS="$work/stub-args" "$@"
}
two_hits='Great question! This crucial design ships today.'
check judge-sample-has-two-hits "2" "$(gate "$two_hits" j0 false >/dev/null; grep -c '^  \[' "$work/err")"

drop_all='[{"hit":1,"real":false,"reason":"quoted"},{"hit":2,"real":false,"reason":"literal"}]'
check judge-drop-all-passes "0" "$(STUB_VERDICTS=$drop_all judged gate "$two_hits" j1 false)"
check judge-drop-all-silent "" "$(cat "$work/err")"
check_contains judge-logs-drop "dropped: [" "$(cat "$gate_dir/gate.log")"
check judge-runs-restricted "1" "$(grep -cx -- '--restricted' "$work/stub-args")"
check judge-disables-own-gate "1" "$(grep -cx 'gate=0' "$work/stub-args")"

keep_one='[{"hit":1,"real":true,"reason":"tic"},{"hit":2,"real":false,"reason":"literal"}]'
check judge-keep-one-blocks "2" "$(STUB_VERDICTS=$keep_one judged gate "$two_hits" j2 false)"
check judge-keep-one-count "1" "$(grep -c '^  \[' "$work/err")"

check judge-missing-verdict-keeps-hit "2" "$(STUB_VERDICTS='[{"hit":1,"real":false,"reason":"x"}]' \
  judged gate "$two_hits" j3 false)"
check judge-missing-verdict-count "1" "$(grep -c '^  \[' "$work/err")"

check judge-failure-keeps-all "2" "$(STUB_FAIL=1 judged gate "$two_hits" j4 false)"
check judge-failure-count "2" "$(grep -c '^  \[' "$work/err")"
check_contains judge-failure-logged "judge failed on 2" "$(cat "$gate_dir/gate.log")"
check judge-garbage-keeps-all "2" "$(STUB_VERDICTS='"nonsense"' judged gate "$two_hits" j5 false)"

# -- a contextual hit stands only on the judge's word -------------------------------
# "robust" names a property far more often than it intensifies in a technical
# reply; every gated "robust" on the fleet was a misfire. With no judge (gantry
# workers: Claude Code strips the credentials from hook env) the hit is dropped,
# never enforced, while a certain hit beside it still blocks.
tier='Keep the extractor in the robust tier, weighted low.'
check contextual-unjudged-passes "0" "$(gate "$tier" c1 false)"
check_contains contextual-unjudged-logged "unjudged, dropped: [banned-vocab]" \
  "$(cat "$gate_dir/gate.log")"
mixed='Great question! Keep the extractor in the robust tier.'
check contextual-judge-down-blocks "2" "$(STUB_FAIL=1 judged gate "$mixed" c2 false)"
check contextual-judge-down-keeps-certain "1" "$(grep -c '^  \[sycophantic\]' "$work/err")"
check contextual-judge-down-drops-contextual "0" "$(grep -c '"robust"' "$work/err")"
keep_both='[{"hit":1,"real":true,"reason":"tic"},{"hit":2,"real":true,"reason":"intensifier"}]'
check contextual-judged-real-blocks "2" "$(STUB_VERDICTS=$keep_both judged gate "$mixed" c3 false)"
check contextual-judged-real-kept "1" "$(grep -c '"robust"' "$work/err")"

# -- structured output is not prose -----------------------------------------------
# pr-reviewer ends on a JSON verdict; a rewrite of it can only break the parse.
verdict='{"verdict": "approve", "summary": "Great question! A robust tapestry, delivered."}'
check json-reply-passes "0" "$(gate "$verdict" s1 false)"
check json-reply-silent "" "$(cat "$work/err")"

# -- the hit quotes the matched text, so a long line still shows its culprit ---------
check dirty-quotes-span "1" "$(gate "$dirty" q1 false >/dev/null; grep -c '"tapestry"' "$work/err")"

# -- off switch and degenerate input ------------------------------------------------
check off-switch "0" "$(CLAUDE_RESPONSE_GATE=0 gate "$dirty" p8 false)"
check empty-reply "0" "$(gate "" p9 false)"
check whitespace-reply "0" "$(gate $'  \n\t' p10 false)"
check no-session "0" "$(
  jq -cn '{last_assistant_message: "Great question!"}' | bash "$hook" 2>/dev/null
  echo $?
)"

if ((fails == 0)); then
  printf 'all passed\n'
  exit 0
fi
printf '%s failed\n' "$fails"
exit 1
