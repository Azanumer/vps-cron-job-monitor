# VPS Cron Job Monitor

Cron jobs fail silently — a backup script that stopped running three
weeks ago looks exactly like one that ran fine last night. This pair of
scripts makes every wrapped job observable: exit codes, durations, and
staleness, with Nagios-style exit codes for monitoring systems.

## run-job.sh — the wrapper

```bash
# In crontab (runs daily at 02:00, must finish within 25h to stay fresh):
0 2 * * * /opt/cron-monitor/run-job.sh --name wp-backup \
  --state-dir /var/lib/cron-monitor --max-age 90000 \
  --to ops@example.com -- /opt/scripts/backup-wordpress.sh
```

- **One instance per job** (flock): an overlapping run exits 3 and logs
  `SKIPPED` instead of piling up parallel copies.
- **State file** per job (`last_run`, `last_exit`, `last_duration`,
  `max_age`), written atomically via temp-file + rename.
- **Failure email** with the last 50 log lines when `--to` is set.
- **Exit code passthrough** — the wrapper exits with the job's own code
  (3 = already running), so cron's own reporting still works.

## check-cron-jobs.sh — the health check

```bash
check-cron-jobs.sh --state-dir /var/lib/cron-monitor [--json]
```

- **OK (0)** — every job succeeded within its `max_age`.
- **WARNING (1)** — a job's last run failed, or its state is unreadable.
- **CRITICAL (2)** — a job is stale past `max_age`, a job marked with a
  `.expected` file never ran, or no state files exist at all.
- **UNKNOWN (3)** — bad arguments or a missing state directory.

Touch `/var/lib/cron-monitor/<name>.expected` for jobs that must exist,
so a job that never ran is reported as critical rather than silently
absent. Point your monitoring at this script, or run it from cron with
`--to` for a digest email on any non-OK result.

## License

MIT — see `LICENSE`.
