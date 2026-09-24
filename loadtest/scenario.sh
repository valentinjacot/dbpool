#!/usr/bin/env bash
# Full demo scenario, no k6 required: quiet baseline first, then the pool
# overload kicks in automatically. Bash equivalent of loadtest/scenario.js.
#
# Also runs the always-on low-rate reporting scenario (Phase 3, CLAUDE.md)
# for the whole run, spanning both phases - reporting must stay calm
# whether the rest of the system is calm or on fire. Rate via
# REPORTING_RATE_PER_MIN env var (default 3/min); target via REPORTING_URL.
#
# Usage: ./scenario.sh [base_url] [baseline_seconds] [overload_seconds] [overload_concurrency]
set -euo pipefail

BASE_URL="${1:-http://localhost:8080}"
BASELINE_SECONDS="${2:-300}"
OVERLOAD_SECONDS="${3:-120}"
OVERLOAD_CONCURRENCY="${4:-30}"
JITTER=2
WAVE_SIZE=20

REPORTING_URL="${REPORTING_URL:-http://localhost:8084}"
REPORTING_RATE_PER_MIN="${REPORTING_RATE_PER_MIN:-3}"
REPORTING_INTERVAL=$(awk "BEGIN { print 60 / ${REPORTING_RATE_PER_MIN} }")

echo "Reporting control load: ${REPORTING_RATE_PER_MIN}/min against ${REPORTING_URL}/api/reporting/summary (runs through both phases)"

(
    while true; do
        curl -s -o /dev/null --max-time 5 "${REPORTING_URL}/api/reporting/summary" || true
        sleep "$REPORTING_INTERVAL"
    done
) &
reporting_pid=$!
trap 'kill "$reporting_pid" 2>/dev/null || true' EXIT

echo "=== Phase 1: baseline for ${BASELINE_SECONDS}s (~2 req/s, pool stays calm) ==="
baseline_end=$(( $(date +%s) + BASELINE_SECONDS ))
while [ "$(date +%s)" -lt "$baseline_end" ]; do
    curl -s -o /dev/null --max-time 15 "${BASE_URL}/api/shop/checkout" &
    curl -s -o /dev/null --max-time 15 "${BASE_URL}/api/shop/checkout" &
    wait
    sleep 1
done

echo
echo "=== Phase 2: overload for ${OVERLOAD_SECONDS}s (concurrency jittering around ${OVERLOAD_CONCURRENCY} +/-${JITTER}) ==="

results_file=$(mktemp)
trap 'kill "$reporting_pid" 2>/dev/null || true; rm -f "$results_file"' EXIT

overload_end=$(( $(date +%s) + OVERLOAD_SECONDS ))
while [ "$(date +%s)" -lt "$overload_end" ]; do
    offset=$(( (RANDOM % (2 * JITTER + 1)) - JITTER ))
    this_concurrency=$(( OVERLOAD_CONCURRENCY + offset ))
    [ "$this_concurrency" -lt 1 ] && this_concurrency=1

    echo "  wave: concurrency ${this_concurrency}"
    seq "$WAVE_SIZE" | xargs -P "$this_concurrency" -I{} \
        curl -s -o /dev/null -w "%{http_code}\n" --max-time 15 "${BASE_URL}/api/shop/checkout" \
        >> "$results_file" || true

    sleep "0.$((RANDOM % 5))"
done

echo
echo "--- summary (overload phase) ---"
sort "$results_file" | uniq -c | sort -rn
