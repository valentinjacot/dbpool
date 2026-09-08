# AppDynamics Health Rule / Policy / Action setup

Status: agent binaries downloaded, extracted, wired into `docker-compose.yml`
and verified to build/boot correctly (see below). Still missing: controller
access (`CONTROLLER_HOST`, `ACCOUNT_NAME`, `ACCOUNT_ACCESS_KEY` in `.env`).
Everything in this file that depends on the controller UI is a placeholder
until then.

## What is already wired and tested

Agent binaries live under `./agents/` (gitignored, not committed):

- `agents/java-agent/` - AppDynamics Java Agent (extracted
  `AppServerAgent-*.zip`). Bind-mounted into `orders`, `inventory`,
  `frontend` at `/opt/appdynamics`. Injected via `appd/entrypoint.sh`, which
  only adds `-javaagent:...` and the `-Dappdynamics.*` system properties
  when `AGENT_ENABLED=true` in `.env`. Verified: with a dummy controller
  host, the agent logged `Started AppDynamics Java Agent Successfully.`,
  picked up the correct tier/node/application names, and the app kept
  serving traffic (agent registration failure is non-blocking).
- `agents/db-agent/` - AppDynamics Database Agent (extracted
  `db-agent-*.zip`, which ships its own `Dockerfile` and
  `README-to-run-dbagent-in-docker.md` - reused as-is). Built and started
  as the `db-agent` service (compose profile `appd`). Verified: agent
  starts, resolves `APPDYNAMICS_CONTROLLER_HOST_NAME` /
  `APPDYNAMICS_CONTROLLER_PORT` / `APPDYNAMICS_CONTROLLER_SSL_ENABLED` /
  `APPDYNAMICS_AGENT_ACCOUNT_NAME` / `APPDYNAMICS_AGENT_ACCOUNT_ACCESS_KEY`
  from environment variables, and only fails at the DNS lookup step with a
  dummy host - i.e. it registers correctly and just needs a real
  controller to talk to.
- `agents/machine-agent/` - AppDynamics Machine Agent, Linux 64-bit bundle
  (own bundled JRE 17). Runs as the `machine-agent` service (compose
  profile `appd`), image built from `appd/machine-agent/Dockerfile`
  (debian:bookworm-slim + findutils/procps/ca-certificates). Verified:
  agent starts, `APPDYNAMICS_SIM_ENABLED=true` correctly activates Server
  Visibility (it POSTs to `.../controller/sim/v2/agent/machines`), fails
  only on DNS resolution of the dummy host.
- `agents/smart-agent/` - extracted but **not wired in**. This is
  AppDynamics' newer OTel-based auto-instrumentation agent, an alternative
  to the classic Java Agent approach above. Not part of the current plan;
  kept in case it's wanted later instead of/alongside the Java Agent.

None of the `appd`-profile services start with a plain `docker compose up
-d` (Phase 1 behaviour is untouched). Start them explicitly once `.env` has
real controller values:

```bash
docker compose --profile appd up -d db-agent machine-agent
```

and flip `AGENT_ENABLED=true` in `.env` before `docker compose up -d` to
attach the Java Agent to the three app services.

## Still to do once controller access exists

1. Set `CONTROLLER_HOST`, `CONTROLLER_PORT`, `SSL_ENABLED`, `ACCOUNT_NAME`,
   `ACCOUNT_ACCESS_KEY` in `.env`, set `AGENT_ENABLED=true`, restart the app
   services, start `db-agent` and `machine-agent`. Confirm in the
   controller UI: 3 tiers (`frontend`, `orders`, `inventory`) + 1 database
   node + 1 host node = 5 components on the flow map.
2. **JMX metric rule (Way A, preferred)**: in the controller, capture
   `ThreadsAwaitingConnection` from the MBean
   `com.zaxxer.hikari:type=Pool (orders-pool)` on the `orders` tier as a
   custom metric. (`register-mbeans: true` is already set in
   `orders/application.yml`, and the Grafana dashboard already tracks the
   Actuator-exposed equivalent `hikaricp_connections_pending` as a
   preview/validation of this exact signal - see
   `observability/grafana/provisioning/dashboards/pool-overload.json`.)
   Alternative (Way B): Machine Agent JMX extension, same MBean/attribute.
3. **PostgreSQL collector**: in the controller, add a collector for host
   `postgres`, port 5432, using the `appd_monitor` role (already created in
   `db/init.sql`, read-only via `pg_monitor`).
4. **Anomaly Detection baseline**: run `loadtest/normal.js` for a few
   minutes first so the later spike from `loadtest/overload.js` /
   `loadtest/overload.sh` is recognized as an anomaly.
5. **Health Rule "Pool Exhaustion"**:
   - Condition 1: custom metric `ThreadsAwaitingConnection > 0` (Warning),
     `>= 5` (Critical), 1 min. (Same thresholds already used in the Grafana
     dashboard panel, for a direct before/after comparison.)
   - Condition 2 (OR): BT error rate on `orders` above baseline.
6. **Policy -> Action**: email/webhook or a visible event on the Health
   Rule violation. This is the actual "propagated to the user" step scored
   by the RFP.

Once this is done, extend `RUNBOOK.md` with the click/command steps for the
live demo (German, per project convention).
