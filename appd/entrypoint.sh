#!/bin/sh
# Wraps the Spring Boot app start. Adds the AppDynamics Java Agent only when
# AGENT_ENABLED=true; otherwise starts the jar exactly as in Phase 1
# (agent-free). Additive, no application code changes (CLAUDE.md Phase 2).
set -eu

OPTS=""

if [ "${AGENT_ENABLED:-false}" = "true" ]; then
    OPTS="-javaagent:/opt/appdynamics/javaagent.jar"
    [ -n "${CONTROLLER_HOST:-}" ] && OPTS="$OPTS -Dappdynamics.controller.hostName=${CONTROLLER_HOST}"
    [ -n "${CONTROLLER_PORT:-}" ] && OPTS="$OPTS -Dappdynamics.controller.port=${CONTROLLER_PORT}"
    [ -n "${SSL_ENABLED:-}" ] && OPTS="$OPTS -Dappdynamics.controller.ssl.enabled=${SSL_ENABLED}"
    [ -n "${ACCOUNT_NAME:-}" ] && OPTS="$OPTS -Dappdynamics.agent.accountName=${ACCOUNT_NAME}"
    [ -n "${ACCOUNT_ACCESS_KEY:-}" ] && OPTS="$OPTS -Dappdynamics.agent.accountAccessKey=${ACCOUNT_ACCESS_KEY}"
    [ -n "${APPD_APPLICATION_NAME:-}" ] && OPTS="$OPTS -Dappdynamics.agent.applicationName=${APPD_APPLICATION_NAME}"
    [ -n "${APPD_TIER_NAME:-}" ] && OPTS="$OPTS -Dappdynamics.agent.tierName=${APPD_TIER_NAME}"
    [ -n "${APPD_NODE_NAME:-}" ] && OPTS="$OPTS -Dappdynamics.agent.nodeName=${APPD_NODE_NAME}"
    echo "[appd] agent enabled: $OPTS"
else
    echo "[appd] AGENT_ENABLED != true, starting agent-free"
fi

# shellcheck disable=SC2086
exec java $OPTS -jar /app/app.jar
