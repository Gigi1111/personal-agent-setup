#!/usr/bin/env bash
# Estimates the OpenAI credit left: the last balance read from OpenAI's billing
# page, minus what OpenClaw has recorded spending since then.
# Usage:  credits-left.sh                                   show the estimate
#         credits-left.sh --set 25.00 2026-01-15            record a new balance from the billing page
#         credits-left.sh --set 25.00 2026-01-15 2026-12-31 same, plus the date the credit expires
set -euo pipefail

BASELINE="$HOME/.openclaw/credit-baseline"
DATE_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

if [[ "${1:-}" == "--set" ]]; then
  [[ ($# -eq 3 || $# -eq 4) && "$2" =~ ^[0-9]+(\.[0-9]{1,2})?$ && "$3" =~ $DATE_RE ]] \
    && [[ $# -eq 3 || "$4" =~ $DATE_RE ]] \
    || die "Usage: $0 --set <balance> <YYYY-MM-DD> [<expiry YYYY-MM-DD>]"
  printf '%s %s %s\n' "$2" "$3" "${4:-}" > "$BASELINE"
  chmod 600 "$BASELINE"
  echo "Recorded \$$2 on $3${4:+, expiring $4}."
  exit 0
fi

[[ -f "$BASELINE" ]] || die "No balance recorded. Run: $0 --set <balance> <YYYY-MM-DD> [<expiry YYYY-MM-DD>]"
read -r BALANCE SINCE EXPIRES < "$BASELINE"

# usage-cost counts whole days back from today, so include the baseline day.
DAYS=$(( ( $(date +%s) - $(date -d "$SINCE" +%s) ) / 86400 + 1 ))
SPENT="$(openclaw gateway usage-cost --days "$DAYS" --json 2>/dev/null | jq -r '.totals.totalCost // .total.totalCost // empty')"
[[ -n "$SPENT" ]] || die "Couldn't read usage from the gateway."

awk -v b="$BALANCE" -v s="$SPENT" -v d="$SINCE" -v e="${EXPIRES:-}" 'BEGIN {
  left = b - s
  printf "Credit left: about $%.2f\n", left
  printf "Spent since %s: $%.2f (OpenClaw estimate), from a balance of $%.2f\n", d, s, b
  if (e != "") printf "The credit expires on %s. ", e
  print "Check OpenAI billing for the exact balance."
}'
