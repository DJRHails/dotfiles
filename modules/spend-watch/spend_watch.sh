#!/usr/bin/env bash
# Daily GitHub metered-spend digest to the (solo) hails-talk #spend channel.
#
# Born from a drift nobody was watching: the account sat at ~$1.02/day of
# GitHub-hosted Actions minutes for weeks while nominally "using self-hosted
# runners", and the only reason it surfaced was someone opening the billing page.
# A repo whose `runs-on` quietly points back at a billed runner is invisible
# otherwise — see the `github-actions` skill for the routing conventions this
# watches over.
#
#     15 9 * * * cd <dotfiles> && bash modules/spend-watch/spend_watch.sh \
#                  >> ~/.local/state/spend-watch/spend_watch.log 2>&1
#
# Reads the enhanced-billing REST API, which needs a token with the `user`
# scope — a plain `repo`-scoped token 404s with a scope hint. Override the token
# with GH_BILLING_TOKEN if gh's own is not the one you want to use.
#
# Idempotent per day: a marker file records the last date posted, so a re-run or
# a doubled cron entry cannot double-post. Pass a date (YYYY-MM-DD) to re-render
# a specific day, which ignores the marker and is how you test it.
set -euo pipefail

USER_LOGIN="${SPEND_WATCH_USER:-DJRHails}"
SLACK_CHANNEL="${SPEND_WATCH_CHANNEL:-C0BRE67340K}" # #spend in hails-talk
DAILY_TARGET="${SPEND_WATCH_TARGET:-0.50}"          # dollars/day we expect to stay under
TOP_REPOS=5

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/spend-watch"
MARKER="${STATE_DIR}/last_posted"

log() { echo "$(date -u +%FT%TZ) $*"; }
die() {
  log "FATAL: $*"
  exit 1
}

command -v gh >/dev/null || die "gh not found"
command -v jq >/dev/null || die "jq not found"

# The most recent COMPLETE UTC day. Billing lags a few hours, so this is only
# safe to run well into the following day (the cron above fires at 09:15 UTC).
if [ $# -gt 0 ]; then
  DAY="$1"
  FORCE=true
else
  DAY="$(date -u -d 'yesterday' +%F 2>/dev/null || date -u -v-1d +%F)"
  FORCE=false
fi
MONTH="${DAY%-*}" # YYYY-MM
YEAR="${MONTH%-*}"
MON="${MONTH#*-}"

if [ "$FORCE" != true ] && [ "$(cat "$MARKER" 2>/dev/null || true)" = "$DAY" ]; then
  log "already posted for ${DAY} — nothing to do"
  exit 0
fi

SLACK_BOT_TOKEN="${SLACK_BOT_TOKEN:-$(sed -n 's/^SLACK_BOT_TOKEN=//p' \
  "${SPEND_WATCH_ENV:-$HOME/projects/github.com/DJRHails/touchstone/.env}" 2>/dev/null || true)}"
[ -n "$SLACK_BOT_TOKEN" ] || die "SLACK_BOT_TOKEN is empty — export it or add it to the touchstone .env"

usage_json="$(mktemp)"
trap 'rm -f "$usage_json"' EXIT

# A 404 here is nearly always the missing `user` scope rather than a real
# absence, and gh prints that hint on stderr — surface it instead of swallowing.
if ! GH_TOKEN="${GH_BILLING_TOKEN:-${GH_TOKEN:-}}" \
  gh api "users/${USER_LOGIN}/settings/billing/usage?year=${YEAR}&month=${MON}" \
  >"$usage_json" 2>"${usage_json}.err"; then
  die "billing API failed: $(tr '\n' ' ' <"${usage_json}.err" | head -c 300)"
fi

read -r day_net mtd_net mtd_days < <(
  jq -r --arg day "$DAY" '
    [.usageItems[]] as $all
    | ([$all[] | select(.date[0:10] == $day) | .netAmount] | add // 0) as $day_net
    | ([$all[] | .netAmount] | add // 0) as $mtd_net
    | ([$all[] | .date[0:10]] | unique | length) as $mtd_days
    | "\($day_net) \($mtd_net) \($mtd_days)"
  ' "$usage_json"
)

# Per-repo for the day, biggest first, sub-cent rows folded away as noise.
#
# Repo names are left bare. Slack rewrites domain-shaped text into a link at post
# time (hails.info, tacit.page, api.hails.info), and it does so BEFORE markdown, so
# wrapping them in backticks does not prevent it — it just moves the raw
# `<http://…|…>` markup inside a code span where it renders literally. Bare text
# linkifies to a tidy anchor showing the repo name, which is harmless. Suppressing
# it properly would mean switching this post to rich_text blocks.
repo_lines="$(
  jq -r --arg day "$DAY" --argjson top "$TOP_REPOS" '
    [.usageItems[] | select(.date[0:10] == $day)]
    | group_by(.repositoryName)
    | map({repo: .[0].repositoryName, net: (map(.netAmount) | add)})
    | map(select(.net >= 0.005))
    | sort_by(-.net)
    | .[:$top]
    | .[] | "\(.repo)\t\(.net)"
  ' "$usage_json" | while IFS=$'\t' read -r repo net; do
    # shellcheck disable=SC2016  # the $ is a literal dollar sign in a printf
    # format string, so single quotes are exactly right here.
    printf '  %s  $%.2f\n' "$repo" "$net"
  done
)"
[ -n "$repo_lines" ] || repo_lines="  (nothing above a cent — all self-hosted)"

# printf, not jq rounding: jq drops a trailing zero, so $60.90 renders as $60.9.
avg="$(jq -rn --argjson n "$mtd_net" --argjson d "$mtd_days" \
  '($n / (if $d > 0 then $d else 1 end))')"
avg="$(printf '%.2f' "$avg")"
day_fmt="$(printf '%.2f' "$day_net")"
mtd_fmt="$(printf '%.2f' "$mtd_net")"

if jq -en --argjson n "$day_net" --argjson t "$DAILY_TARGET" '$n > $t' >/dev/null; then
  verdict=":red_circle: over the \$${DAILY_TARGET}/day target"
else
  verdict=":large_green_circle: under the \$${DAILY_TARGET}/day target"
fi

text="$(
  cat <<MSG
*GitHub metered spend — ${DAY}*
Billed that day: *\$${day_fmt}* — ${verdict}
Month to date: \$${mtd_fmt} over ${mtd_days} days (\$${avg}/day average)

By repo:
${repo_lines}
MSG
)"

response="$(curl -s -m 15 -X POST "https://slack.com/api/chat.postMessage" \
  -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
  --data-urlencode "channel=${SLACK_CHANNEL}" \
  --data-urlencode "text=${text}" 2>/dev/null || true)"

if [ "$(jq -r '.ok // false' <<<"$response")" != "true" ]; then
  die "slack post rejected: $(jq -r '.error // "no response"' <<<"$response")"
fi

# Marker only after a confirmed post, so a failed send retries next run rather
# than silently burning the day's one digest.
mkdir -p "$STATE_DIR"
[ "$FORCE" = true ] || echo "$DAY" >"$MARKER"
log "posted ${DAY}: \$${day_fmt} (MTD \$${mtd_fmt} over ${mtd_days}d)"
