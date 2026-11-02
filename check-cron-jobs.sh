#!/usr/bin/env bash
# check-cron-jobs.sh — Nagios/CLI health check over run-job.sh state files.
#
# Usage:
#   check-cron-jobs.sh --state-dir /var/lib/cron-monitor [--json] [--to ops@example.com]
#
# Statuses (Nagios exit codes):
#   OK (0)       every job succeeded and ran within its max_age (when set).
#   WARNING (1)  a job's last run failed, or a state file is unreadable.
#   CRITICAL (2) a job is stale (older than max_age, or never ran and a
#                .expected file exists), or no state files were found.
#   UNKNOWN (3)  bad arguments / missing state directory.
set -u

STATE_DIR=""; JSON=0; TO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --state-dir) STATE_DIR="$2"; shift 2 ;;
    --json)      JSON=1; shift ;;
    --to)        TO="$2"; shift 2 ;;
    -h|--help)   sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "check-cron-jobs.sh: unknown option: $1" >&2; exit 3 ;;
  esac
done

[ -n "$STATE_DIR" ] || { echo "UNKNOWN: --state-dir is required" >&2; exit 3; }
[ -d "$STATE_DIR" ] || { echo "UNKNOWN: state dir not found: $STATE_DIR" >&2; exit 3; }

NOW=$(date +%s)
OVERALL=0; OK=0; WARN=0; CRIT=0; DETAILS=""

# A .expected file (created by `touch`) marks a job that must exist:
# a job that never ran is CRITICAL, not silently absent.
for expected in "$STATE_DIR"/*.expected; do
  [ -e "$expected" ] || continue
  name=$(basename "$expected" .expected)
  [ -f "$STATE_DIR/$name.state" ] || { CRIT=$((CRIT+1)); DETAILS="$DETAILS CRITICAL: $name never ran;"; }
done

FOUND=0
for state in "$STATE_DIR"/*.state; do
  [ -e "$state" ] || continue
  FOUND=$((FOUND+1))
  name=$(basename "$state" .state)
  last_run=0; last_exit=""; max_age=0
  # Only the four keys we wrote are honoured; anything else is ignored.
  while IFS='=' read -r key value; do
    case "$key" in
      last_run) last_run="$value" ;;
      last_exit) last_exit="$value" ;;
      max_age) max_age="$value" ;;
    esac
  done < "$state"
  case "$last_run$last_exit" in *[!0-9]*) WARN=$((WARN+1)); DETAILS="$DETAILS WARNING: $name has unreadable state;"; continue ;; esac
  if [ "$max_age" -gt 0 ] && [ $((NOW - last_run)) -gt "$max_age" ]; then
    CRIT=$((CRIT+1)); DETAILS="$DETAILS CRITICAL: $name stale ($(( (NOW - last_run) / 3600 ))h since last run);"
  elif [ "$last_exit" -ne 0 ]; then
    WARN=$((WARN+1)); DETAILS="$DETAILS WARNING: $name last exit $last_exit;"
  else
    OK=$((OK+1))
  fi
done

if [ "$FOUND" -eq 0 ] && [ "$CRIT" -eq 0 ]; then
  CRIT=1; DETAILS=" CRITICAL: no state files in $STATE_DIR;"
fi

if [ "$CRIT" -gt 0 ]; then OVERALL=2; LABEL="CRITICAL";
elif [ "$WARN" -gt 0 ]; then OVERALL=1; LABEL="WARNING";
else OVERALL=0; LABEL="OK"; fi

SUMMARY="$LABEL: $OK ok, $WARN warning, $CRIT critical.$DETAILS"
if [ "$JSON" -eq 1 ]; then
  printf '{"status":"%s","exit":%d,"ok":%d,"warning":%d,"critical":%d,"details":%s}\n' \
    "$LABEL" "$OVERALL" "$OK" "$WARN" "$CRIT" \
    "$(printf '%s' "$DETAILS" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""')"
else
  echo "$SUMMARY"
fi
if [ "$OVERALL" -ne 0 ] && [ -n "$TO" ] && command -v mail >/dev/null 2>&1; then
  echo "$SUMMARY" | mail -s "[cron-monitor] $LABEL: $WARN warning, $CRIT critical" "$TO"
fi
exit "$OVERALL"
