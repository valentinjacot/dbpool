#!/usr/bin/env bash
# One-command orchestration for the whole demo environment: the Docker
# Compose stack (5 app services + Postgres + Prometheus/Grafana + DB
# Agent), plus the Machine Agent, which runs on the host, not in a
# container (see appd/machine-agent/run.sh for why).
#
# Usage: ./stack.sh [start|stop|restart|status] [--build]
#   start    docker compose up -d (add --build to rebuild images first),
#            then db-agent (compose profile appd), then the host Machine
#            Agent, then waits for all 5 app services to report healthy.
#   stop     stops everything (Machine Agent, DB Agent, app services,
#            Postgres, Prometheus/Grafana) but keeps containers/volumes
#            (docker compose stop, not down) so the next start is fast.
#   restart  stop, then start.
#   status   one combined view: containers, Machine Agent, 24h baseline.
#
# Does NOT touch the 24h baseline (loadtest/baseline-24h.sh) - start that
# separately once you've confirmed the stack is healthy, so a stack
# restart never silently resets or orphans a baseline run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_SERVICES=(orders:8081 inventory:8082 checkout:8083 reporting:8084)

wait_for_health() {
    echo "Waiting for app services to report healthy (Java Agent startup takes ~30-50s)..."
    local deadline=$(( $(date +%s) + 120 ))
    for entry in "${APP_SERVICES[@]}"; do
        local svc="${entry%:*}" port="${entry#*:}"
        until curl -sf "http://localhost:${port}/actuator/health" > /dev/null 2>&1; do
            if [ "$(date +%s)" -ge "$deadline" ]; then
                echo "  $svc: still not healthy after 120s, giving up on it - check 'docker compose logs $svc'"
                break
            fi
            sleep 3
        done
        curl -sf "http://localhost:${port}/actuator/health" > /dev/null 2>&1 \
            && echo "  $svc: UP" || echo "  $svc: NOT UP"
    done
    curl -sf http://localhost:8080/api/shop/health > /dev/null 2>&1 \
        && echo "  frontend: UP" || echo "  frontend: NOT UP"
}

cmd="${1:-start}"
build_flag=""
[ "${2:-}" = "--build" ] && build_flag="--build"

case "$cmd" in
    start)
        # shellcheck disable=SC2086
        docker compose up -d $build_flag
        docker compose --profile appd up -d db-agent
        ./appd/machine-agent/run.sh start
        wait_for_health
        echo
        echo "Grafana:    http://localhost:3001"
        echo "Prometheus: http://localhost:9091"
        echo "Frontend:   http://localhost:8080/api/shop/checkout"
        echo
        echo "Baseline load not started automatically - run when ready:"
        echo "  ./loadtest/baseline-24h.sh start"
        ;;
    stop)
        ./appd/machine-agent/run.sh stop
        docker compose --profile appd stop
        ;;
    restart)
        "$0" stop
        "$0" start "${2:-}"
        ;;
    status)
        echo "=== containers ==="
        docker compose ps --format '{{.Name}}\t{{.Status}}'
        echo
        echo "=== machine agent (host) ==="
        ./appd/machine-agent/run.sh status
        echo
        echo "=== 24h baseline ==="
        ./loadtest/baseline-24h.sh status
        ;;
    *)
        echo "Usage: $0 [start|stop|restart|status] [--build]" >&2
        exit 1
        ;;
esac
