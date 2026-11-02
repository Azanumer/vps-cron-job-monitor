#!/usr/bin/env bash
# run-job.sh — wrap a cron job so failures and stalls become visible.
#
# Usage:
#   run-job.sh --name backup --state-dir /var/lib/cron-monitor [--to ops@example.com] [--max-age 90000] -- mysqldump ...
#
# Behaviour:
#   * One instance per --name (flock); a second overlapping run exits 3
#     without killing the first — overlapping cron jobs are a bug, not
#     something to paper over with parallel runs.
#   * Appends start/finish lines to <state-dir>/<name>.log.
#   * Writes <state-dir>/<name>.state (last_run, last_exit, last_duration,
#     max_age) for check-cron-jobs.sh to read.
#   * On non-zero exit, mails --to (if set) with the tail of the log.
#   * Exits with the wrapped command's exit code (3 = already running).
set -u

NAME=""; STATE_DIR=""; TO=""; MAX_AGE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --name)      NAME="$2"; shift 2 ;;
    --state-dir) STATE_DIR="$2"; shift 2 ;;
    --to)        TO="$2"; shift 2 ;;
    --max-age)   MAX_AGE="$2"; shift 2 ;;
    --)          shift; break ;;
    -h|--help)   sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "run-job.sh: unknown option: $1" >&2; exit 2 ;;
  esac
done

[ -n "$NAME" ] || { echo "run-job.sh: --name is required" >&2; exit 2; }
[ -n "$STATE_DIR" ] || { echo "run-job.sh: --state-dir is required" >&2; exit 2; }
[ $# -gt 0 ] || { echo "run-job.sh: no command given after --" >&2; exit 2; }
# Job names become filenames — reject path tricks outright.
case "$NAME" in *[!A-Za-z0-9._-]*|*..*) echo "run-job.sh: unsafe --name: $NAME" >&2; exit 2 ;; esac

mkdir -p "$STATE_DIR" || exit 2
LOG="$STATE_DIR/$NAME.log"
STATE="$STATE_DIR/$NAME.state"
LOCK="$STATE_DIR/$NAME.lock"

exec 9>"$LOCK"
if ! flock -n 9; then
  echo "$(date -Is) $NAME SKIPPED: already running" >> "$LOG"
  exit 3
fi

START=$(date +%s)
echo "$(date -Is) $NAME START: $*" >> "$LOG"
# Run the command with stdout+stderr appended to the log. The exit code
# is captured explicitly so `set -u` (not -e) never masks a failure.
"$@" >> "$LOG" 2>&1
CODE=$?
END=$(date +%s)
DURATION=$((END - START))
echo "$(date -Is) $NAME FINISH exit=$CODE duration=${DURATION}s" >> "$LOG"

# Atomic state write: temp file + rename, so the monitor never reads
# a half-written state file.
TMP="$STATE.tmp.$$"
{
  echo "last_run=$END"
  echo "last_exit=$CODE"
  echo "last_duration=$DURATION"
  echo "max_age=$MAX_AGE"
} > "$TMP" && mv "$TMP" "$STATE"

if [ "$CODE" -ne 0 ] && [ -n "$TO" ] && command -v mail >/dev/null 2>&1; then
  {
    echo "Cron job '$NAME' failed with exit code $CODE after ${DURATION}s."
    echo ""
    echo "Last 50 log lines:"
    tail -n 50 "$LOG"
  } | mail -s "[cron-monitor] $NAME FAILED (exit $CODE)" "$TO"
fi

exit "$CODE"
