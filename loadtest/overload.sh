#!/usr/bin/env bash
# Fallback overload generator (no k6 required): fires many concurrent
# requests at orders/slow via the frontend using curl + xargs.
#
# Load is sent in waves whose concurrency jitters randomly around the
# target value (+/- 2), with a small randomized pause between waves, so
# the pending-connections line on the dashboard looks like natural
# traffic instead of a flat step function.
#
# Also runs a separate, always-on, very low-rate loop against reporting
# (Phase 3, CLAUDE.md) - the healthy control consumer of the same
# PostgreSQL. It must stay calm throughout, proving the bottleneck is the
# orders pool, not the database. Rate via REPORTING_RATE_PER_MIN env var
# (default 3/min); target via REPORTING_URL env var.
#
# Usage: ./overload.sh [concurrency] [total_requests] [base_url] [wave_size]
set -euo pipefail

CONCURRENCY="${1:-30}"
TOTAL="${2:-300}"
BASE_URL="${3:-http://localhost:8080}"
WAVE_SIZE="${4:-20}"
JITTER=2

REPORTING_URL="${REPORTING_URL:-http://localhost:8084}"
REPORTING_RATE_PER_MIN="${REPORTING_RATE_PER_MIN:-3}"
REPORTING_INTERVAL=$(awk "BEGIN { print 60 / ${REPORTING_RATE_PER_MIN} }")

echo "Firing ~${TOTAL} requests at ${BASE_URL}/api/shop/checkout, concurrency jittering around ${CONCURRENCY} (+/-${JITTER}), in waves of ${WAVE_SIZE}"
echo "Reporting control load: ${REPORTING_RATE_PER_MIN}/min against ${REPORTING_URL}/api/reporting/summary"

results_file=$(mktemp)

(
    while true; do
        curl -s -o /dev/null --max-time 5 "${REPORTING_URL}/api/reporting/summary" || true
        sleep "$REPORTING_INTERVAL"
    done
) &
reporting_pid=$!
trap 'kill "$reporting_pid" 2>/dev/null || true; rm -f "$results_file"' EXIT

sent=0
while [ "$sent" -lt "$TOTAL" ]; do
    remaining=$((TOTAL - sent))
    this_wave=$(( remaining < WAVE_SIZE ? remaining : WAVE_SIZE ))

    # random concurrency in [CONCURRENCY-JITTER, CONCURRENCY+JITTER], floor 1
    offset=$(( (RANDOM % (2 * JITTER + 1)) - JITTER ))
    this_concurrency=$(( CONCURRENCY + offset ))
    [ "$this_concurrency" -lt 1 ] && this_concurrency=1

    echo "  wave: ${this_wave} requests at concurrency ${this_concurrency}"
    seq "$this_wave" | xargs -P "$this_concurrency" -I{} \
        curl -s -o /dev/null -w "%{http_code}\n" --max-time 15 "${BASE_URL}/api/shop/checkout" \
        >> "$results_file" || true

    sent=$((sent + this_wave))

    # short randomized pause between waves for a less mechanical rhythm
    sleep "0.$((RANDOM % 5))"
done

echo "--- summary ---"
sort "$results_file" | uniq -c | sort -rn
