#!/usr/bin/env bash
# Runs the AppDynamics Machine Agent directly on the host (not in a
# container). A containerized Machine Agent just gets another ephemeral
# per-container hostname, no more correlated with the app tiers' hosts
# than before; running on the host gives the whole demo environment one
# stable identity instead.
#
# Usage: ./appd/machine-agent/run.sh [start|stop|status|logs]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENT_DIR="$REPO_ROOT/agents/machine-agent"
PIDFILE="$AGENT_DIR/machine-agent.pid"

# Pull controller settings from .env (same values used by the other
# services in docker-compose.yml).
set -a
# shellcheck disable=SC1091
[ -f "$REPO_ROOT/.env" ] && . "$REPO_ROOT/.env"
set +a

export APPDYNAMICS_CONTROLLER_HOST_NAME="${CONTROLLER_HOST:-}"
export APPDYNAMICS_CONTROLLER_PORT="${CONTROLLER_PORT:-443}"
export APPDYNAMICS_CONTROLLER_SSL_ENABLED="${SSL_ENABLED:-true}"
export APPDYNAMICS_AGENT_ACCOUNT_NAME="${ACCOUNT_NAME:-}"
export APPDYNAMICS_AGENT_ACCOUNT_ACCESS_KEY="${ACCOUNT_ACCESS_KEY:-}"
# Enables Server Visibility (hardware metrics + Host node on the flow map).
export APPDYNAMICS_SIM_ENABLED=true
# One stable identity for the whole demo host, instead of a random
# per-container hostname.
export APPDYNAMICS_AGENT_UNIQUE_HOST_ID=afi-demo-host

cmd="${1:-start}"

case "$cmd" in
    start)
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            echo "Already running, PID $(cat "$PIDFILE")"
            exit 0
        fi
        "$AGENT_DIR/bin/machine-agent" -d -p "$PIDFILE"
        sleep 1
        echo "Machine Agent starting (uniqueHostId=afi-demo-host), pidfile: $PIDFILE"
        echo "Logs: $AGENT_DIR/logs/machine-agent.log"
        ;;
    stop)
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            kill "$(cat "$PIDFILE")"
            rm -f "$PIDFILE"
            echo "Machine Agent stopped"
        else
            echo "Not running (no live pidfile at $PIDFILE)"
        fi
        ;;
    status)
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            echo "Running, PID $(cat "$PIDFILE")"
        else
            echo "Not running"
        fi
        ;;
    logs)
        tail -f "$AGENT_DIR/logs/machine-agent.log"
        ;;
    *)
        echo "Usage: $0 [start|stop|status|logs]" >&2
        exit 1
        ;;
esac
