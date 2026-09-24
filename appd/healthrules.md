# AppDynamics Health Rule / Policy / Action setup

Status: controller access is live (`se-lab.saas.appdynamics.com`, account
`se-lab`). All three agents (Java Agent on `frontend`/`orders`/`inventory`,
DB Agent, Machine Agent) are running with `AGENT_ENABLED=true` and have
successfully registered with the real controller - see confirmation details
below. Application `AFI-UC3-Demo` (Application ID 10564) should already show
the 3 tiers on the flow map. Remaining work is controller-UI configuration:
PostgreSQL collector, JMX metric rule, Anomaly Detection baseline, Health
Rule, Policy/Action (items 2-6 below).

## What is already wired and tested

Agent binaries live under `./agents/` (gitignored, not committed):

- `agents/java-agent/` - AppDynamics Java Agent (extracted
  `AppServerAgent-*.zip`). Bind-mounted into `orders`, `inventory`,
  `frontend` at `/opt/appdynamics`. Injected via `appd/entrypoint.sh`, which
  only adds `-javaagent:...` and the `-Dappdynamics.*` system properties
  when `AGENT_ENABLED=true` in `.env`. All three also get
  `-Dappdynamics.agent.uniqueHostId=afi-demo-host` (`APPD_UNIQUE_HOST_ID`
  in `docker-compose.yml`), same value as the host-run Machine Agent, so
  the controller correlates all 3 tiers' nodes with that one host instead
  of each container's own ephemeral hostname. Verified against the real
  controller: `Started AppDynamics Java Agent Successfully.` and
  `Registered app server agent with Node ID[...] Component ID[...]
  Application ID [10564]` on all three, correct tier/node/application
  names, `uniqueHostId` present in the logged startup args.
- **Database Agent**: `db-agent` service (compose profile `appd`) runs the
  official prebuilt image `appdynamics/db-agent:latest` from Docker Hub
  (currently v26.7.0.5723). Earlier versions shipped their own Dockerfile
  inside the downloaded zip and we built a local image from it; the 26.x
  line dropped that in favour of the published image, so `docker-compose.yml`
  now points `image:` at it directly - no local build, no bind mount of
  `./agents/db-agent` needed. Same `APPDYNAMICS_*` env var contract either
  way. This image also self-redacts the access key in its own startup log
  line (`MASKED_DB_AGENT_PROPERTIES=...`), so no local patch was needed here
  (unlike the older version, where we had to patch the vendor script
  locally). Verified against the real `se-lab` controller: `Auto agent
  registration SUCCEEDED!`, `Registered DB_AGENT with agentID[...]`,
  `Started afi-uc3-db-agent successfully`. Each container restart gets a
  new agent ID - if you reconfigure/rebuild this service, re-point the
  Database Collector in the controller UI at the current one (the old
  agent ID just goes stale/offline).
- **Machine Agent**: runs directly on the host, not in a container - see
  `appd/machine-agent/run.sh` (`start`/`stop`/`status`/`logs`). A
  containerized Machine Agent just gets its own ephemeral per-container
  hostname, no more correlated with the app tiers' hosts than any other
  container; running it on the host instead gives the whole demo
  environment one stable identity. `run.sh` sources `.env` for controller
  settings, sets `APPDYNAMICS_SIM_ENABLED=true` (Server Visibility) and
  `APPDYNAMICS_AGENT_UNIQUE_HOST_ID=afi-demo-host`. `conf/controller-info.xml`
  also has `<sim-enabled>true</sim-enabled>` set directly, though the env
  var already takes precedence. Verified against the real controller:
  `Machine Agent registered successfully with machineID: 740318 and
  hostID: afi-demo-host`, `Started AppDynamics Machine Agent Successfully`,
  hardware data collectors (CPU/memory/network/disk) running on schedule,
  no errors.
- `agents/smart-agent/` - extracted but **not wired in**. This is
  AppDynamics' newer OTel-based auto-instrumentation agent, an alternative
  to the classic Java Agent approach above. Not part of the current plan;
  kept in case it's wanted later instead of/alongside the Java Agent.

None of this starts with a plain `docker compose up -d` (Phase 1 behaviour
is untouched). Start it explicitly once `.env` has real controller values:

```bash
docker compose --profile appd up -d db-agent   # DB Agent (container)
./appd/machine-agent/run.sh start              # Machine Agent (host process)
```

and flip `AGENT_ENABLED=true` in `.env` before `docker compose up -d` to
attach the Java Agent to the three app services.

## Remaining controller-UI steps

1. ~~Set controller env vars, `AGENT_ENABLED=true`, start `db-agent` and
   `machine-agent`.~~ Done. Confirm in the controller UI: 3 tiers
   (`frontend`, `orders`, `inventory`) + 1 database node + 1 host node = 5
   components on the flow map.
2. **JMX metric rule (Way A, preferred)**: in the controller, capture
   `ThreadsAwaitingConnection` from the MBean
   `com.zaxxer.hikari:type=Pool (orders-pool)` on the `orders` tier as a
   custom metric. (`register-mbeans: true` is already set in
   `orders/application.yml`, and the Grafana dashboard already tracks the
   Actuator-exposed equivalent `hikaricp_connections_pending` as a
   preview/validation of this exact signal - see
   `observability/grafana/provisioning/dashboards/pool-overload.json`.)
   Alternative (Way B): Machine Agent JMX extension, same MBean/attribute.
3. **PostgreSQL collector**: in the controller (Database Monitoring / add
   PostgreSQL instance), point it at the currently-registered DB Agent
   (agent ID logged at `db-agent` startup, changes on every
   restart/rebuild - see above), with:
   - Host: `postgres`, Port: `5432` (Docker Compose service name/internal
     port - not `localhost:5433`, which is only the host-machine mapping)
   - Database: `appdb`
   - Username: `appd_monitor` / Password: `appd_monitor_pass` (from `.env`)
   - SSL: disabled
   `appd_monitor` already has `pg_monitor` (read access to `pg_stat_*`) plus
   `SELECT` on the `appdb` schema, granted in `db/init.sql`.
4. **Anomaly Detection baseline**: needs sustained normal traffic before
   the later spike will register as an anomaly rather than just noise.
   `loadtest/normal.js` works for a quick few-minute check; for actually
   training the baseline, use `loadtest/baseline-24h.sh start` (runs
   unattended in the background, default 24h, same traffic profile as
   `normal.js` - see `RUNBOOK.md` section 4 for usage/monitoring).
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

## Phase 3 (branch `phase3-5-service-topology`, not yet on main)

Evolves the topology to 5 services: `checkout` (orchestrator between
`frontend` and `orders`/`inventory`) and `reporting` (independent, healthy
control consumer of the same PostgreSQL). Component count target: 5 tiers +
1 database node + 1 host node = 7 (see CLAUDE.md Phase 3 for the full spec).

Both new services use the exact same wiring as `orders`/`inventory`/
`frontend`: `appd/entrypoint.sh`, `agents/java-agent` bind mount,
`uniqueHostId=afi-demo-host`, `register-mbeans: true`. Once merged, step 1
above becomes: confirm 5 tiers (`frontend`, `checkout`, `orders`,
`inventory`, `reporting`) + DB + host = 7 components on the flow map, with
the overload propagating `orders -> checkout -> frontend` and `reporting`
staying flat green throughout - the live differential diagnosis (same
database, different outcome, so the fault is the orders pool, not the DB).
`reporting`'s pool (`reporting-pool`) is worth its own JMX/Health-Rule
contrast metric if time allows, precisely because it should never move.
