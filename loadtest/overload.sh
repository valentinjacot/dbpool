#!/usr/bin/env bash
# Fallback overload generator (no k6 required): fires many concurrent
# requests at orders/slow via the frontend using curl + xargs.
#
# Usage: ./overload.sh [concurrency] [total_requests] [base_url]
set -euo pipefail

CONCURRENCY="${1:-30}"
TOTAL="${2:-300}"
BASE_URL="${3:-http://localhost:8080}"

echo "Firing ${TOTAL} requests at ${BASE_URL}/api/shop/checkout with concurrency ${CONCURRENCY}"

seq "$TOTAL" | xargs -P "$CONCURRENCY" -I{} \
    curl -s -o /dev/null -w "%{http_code}\n" --max-time 15 "${BASE_URL}/api/shop/checkout" \
    | sort | uniq -c | sort -rn
