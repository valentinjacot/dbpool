#!/usr/bin/env bash
# Long-running baseline load generator for AppDynamics Anomaly Detection
# training (and Grafana/Prometheus baselining). Runs unattended in the
# background for a configurable duration (default 24h).
#
# Traffic profile matches loadtest/normal.js: 2 concurrent checkouts,
# each ~5s (pg_sleep in orders/slow) + 1s pause -> roughly one cycle every
# 6s, well within the orders pool (max 5), so the pool stays calm the
# whole run - that's the point, it's what "normal" should look like to
# Anomaly Detection.
#
# Also runs the always-on low-rate reporting scenario (Phase 3, CLAUDE.md)
# for the same duration - reporting's own baseline needs training too. Rate
# via REPORTING_RATE_PER_MIN env var (default 3/min); target via
# REPORTING_URL env var (default http://localhost:8084).
#
# Usage: ./loadtest/baseline-24h.sh [start|stop|status|logs] [duration_seconds] [base_url]
#   start defaults: duration 86400 (24h), base_url http://localhost:8080
#
# Examples:
#   ./loadtest/baseline-24h.sh start                # 24h against localhost:8080
#   ./loadtest/baseline-24h.sh start 3600            # 1h smoke test
#   ./loadtest/baseline-24h.sh status
#   ./loadtest/baseline-24h.sh logs                  # tail the periodic summary
#   ./loadtest/baseline-24h.sh stop
set -uo pipefail
# Deliberately no `set -e`: this loop must survive individual curl
# hiccups over many hours without the whole script dying on one blip.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$SCRIPT_DIR/.baseline-run"
PIDFILE="$STATE_DIR/baseline.pid"
LOGFILE="$STATE_DIR/baseline.log"
SUMMARY_FILE="$STATE_DIR/baseline.summary.log"
RESULTS_FILE="$STATE_DIR/baseline.results"

REPORTING_URL="${REPORTING_URL:-http://localhost:8084}"
REPORTING_RATE_PER_MIN="${REPORTING_RATE_PER_MIN:-3}"
REPORTING_INTERVAL=$(awk "BEGIN { print 60 / ${REPORTING_RATE_PER_MIN} }")

mkdir -p "$STATE_DIR"

is_running() {
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

run_loop() {
    local base_url="$1"
    local duration="$2"
    local end_time=$(( $(date +%s) + duration ))
    local last_summary
    last_summary=$(date +%s)

    : > "$RESULTS_FILE"
    echo "$(date -Iseconds) baseline started, target ${base_url}, duration ${duration}s" >> "$SUMMARY_FILE"
    echo "$(date -Iseconds) reporting control load: ${REPORTING_RATE_PER_MIN}/min against ${REPORTING_URL}/api/reporting/summary" >> "$SUMMARY_FILE"

    (
        while true; do
            curl -s -o /dev/null --max-time 5 "${REPORTING_URL}/api/reporting/summary" 2>/dev/null || true
            sleep "$REPORTING_INTERVAL"
        done
    ) &
    reporting_pid=$!
    trap 'kill "$reporting_pid" 2>/dev/null || true' EXIT

    while [ "$(date +%s)" -lt "$end_time" ]; do
        (curl -s -o /dev/null -w "%{http_code}\n" --max-time 15 "${base_url}/api/shop/checkout" >> "$RESULTS_FILE" 2>/dev/null) &
        pid1=$!
        (curl -s -o /dev/null -w "%{http_code}\n" --max-time 15 "${base_url}/api/shop/checkout" >> "$RESULTS_FILE" 2>/dev/null) &
        pid2=$!
        # Wait on these two specific PIDs, NOT a bare `wait` - the
        # reporting subshell above is an intentionally infinite background
        # job, and a bare `wait` blocks until ALL jobs finish, which would
        # hang here forever.
        wait "$pid1" "$pid2" 2>/dev/null
        sleep 1

        now=$(date +%s)
        if [ $(( now - last_summary )) -ge 300 ]; then
            total=$(wc -l < "$RESULTS_FILE" 2>/dev/null || echo 0)
            errors=$(grep -vc "^200$" "$RESULTS_FILE" 2>/dev/null || echo 0)
            remaining=$(( end_time - now ))
            echo "$(date -Iseconds) requests=${total} errors=${errors} remaining=${remaining}s" >> "$SUMMARY_FILE"
            last_summary=$now
        fi
    done

    total=$(wc -l < "$RESULTS_FILE" 2>/dev/null || echo 0)
    errors=$(grep -vc "^200$" "$RESULTS_FILE" 2>/dev/null || echo 0)
    echo "$(date -Iseconds) baseline finished, requests=${total} errors=${errors}" >> "$SUMMARY_FILE"
    rm -f "$PIDFILE"
}

cmd="${1:-start}"
DURATION_SECONDS="${2:-86400}"
BASE_URL="${3:-http://localhost:8080}"

case "$cmd" in
    start)
        if is_running; then
            echo "Already running, PID $(cat "$PIDFILE")"
            exit 0
        fi
        nohup "$0" _run "$DURATION_SECONDS" "$BASE_URL" >> "$LOGFILE" 2>&1 &
        echo $! > "$PIDFILE"
        echo "Baseline started in background, PID $(cat "$PIDFILE")"
        echo "Target: ${BASE_URL}/api/shop/checkout, duration: ${DURATION_SECONDS}s ($(( DURATION_SECONDS / 3600 ))h)"
        echo "Summary: $SUMMARY_FILE (updated every 5 min)"
        ;;
    _run)
        run_loop "$BASE_URL" "$DURATION_SECONDS"
        ;;
    stop)
        if is_running; then
            kill "$(cat "$PIDFILE")"
            rm -f "$PIDFILE"
            echo "Baseline stopped"
        else
            echo "Not running (no live pidfile at $PIDFILE)"
        fi
        ;;
    status)
        if is_running; then
            echo "Running, PID $(cat "$PIDFILE")"
            tail -3 "$SUMMARY_FILE" 2>/dev/null
        else
            echo "Not running"
            [ -f "$SUMMARY_FILE" ] && tail -3 "$SUMMARY_FILE"
        fi
        ;;
    logs)
        tail -f "$SUMMARY_FILE"
        ;;
    *)
        echo "Usage: $0 [start|stop|status|logs] [duration_seconds] [base_url]" >&2
        exit 1
        ;;
esac
