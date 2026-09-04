# CLAUDE.md - AFI APM Demo: Use Case 3 (Anomaly Detection)

## Goal

Build a working demo environment to present **AFI Use Case 3 (ZK04)** live:

> Topology with at least 5 components (services, hosts, DB). Simulate a
> **DB connection pool overload** and show how the system **detects the anomaly
> early and propagates it to the user.**

Monitoring stack: **AppDynamics** (Java agent, Database agent, optional Machine
agent), on-prem capable. The demo runs locally via Docker.

RFP scoring: 0 / 3 / 7 / 10 points. What matters is not the spike itself but
**early detection + alerting/propagation.**

## Phases (important)

We deliberately build in two phases. This mirrors the project approach: get the
application and infrastructure running first, then instrument.

- **Phase 1 (now, agent-free):** applications, DB, load, and the reproducible
  connection pool overload. No AppD, but verifiable without AppD (via Spring Boot
  Actuator / Micrometer and the HikariCP logs). Goal: the anomaly behaviour is in
  place and triggerable on demand.
- **Phase 2 (later, additive):** controller access and agent binaries are added.
  Instrumentation happens **without code changes** (only `-javaagent`, env vars,
  extra containers, and controller configuration). Phase 1 already prepares all
  hooks (JMX enabled, tier/node names planned, mount paths ready, switchable via
  env var).

In Phase 1, do not build anything that would have to be reworked in Phase 2.

## Non-goals / limits

- No production code, no persistence rigor. This is a demo.
- No real customer data. Synthetic data only.
- The **controller** and the **agent binaries** are NOT obtained by you. They
  arrive in Phase 2, provided by the user.

## Prerequisites

**Phase 1 (needed now):**
- Installed locally: Docker + Docker Compose, JDK 17, Maven, k6 (optional,
  fallback provided).

**Phase 2 (later, not needed yet):**
- **Controller** reachable: `CONTROLLER_HOST`, `CONTROLLER_PORT`,
  `SSL_ENABLED (true/false)`, `ACCOUNT_NAME`, `ACCOUNT_ACCESS_KEY`.
  (SaaS trial or on-prem lab.)
- **Agent binaries** from the licensed portal, placed under `./agents/`:
  `javaagent.jar` (App Server Agent), `db-agent.jar` (Database Visibility),
  `machineagent.zip` (optional, for host nodes).

In Phase 2: if the controller or an agent is missing, ask instead of assuming. Do
not download agents from the internet.

## Tech stack

- Java 17, Spring Boot 3.x, Maven (multi-module).
- HikariCP (default in Spring Boot) as the connection pool - deliberately small.
- PostgreSQL 16 (Docker).
- Load generator: k6 script, fallback: bash + curl + xargs.
- AppDynamics Java agent via `-javaagent`, DB agent as a separate process.

## Target topology (>= 5 components for the flow map)

```
[k6 client] --HTTP--> frontend --HTTP--> orders --JDBC--> PostgreSQL
                                    \--HTTP--> inventory --JDBC--> PostgreSQL
```

Components on the flow map:
1. Tier `frontend`
2. Tier `orders`   <-- carries the small pool, the overload happens here
3. Tier `inventory`
4. Database `postgres` (DB node + Database module via DB agent)
5. Host(s) via Machine agent

This visibly satisfies the "at least 5 components" requirement.

## Repo structure (to create)

```
afi-apm-uc3/
  docker-compose.yml
  .env.example
  agents/                # javaagent.jar, db-agent.jar, machineagent.zip (from user, Phase 2)
  db/init.sql            # schema + seed + monitoring user for DB agent
  services/
    frontend/            # Spring Boot, calls orders + inventory
    orders/              # Spring Boot, small pool, slow query
    inventory/           # Spring Boot, normal pool
  loadtest/
    normal.js            # k6 baseline load (for anomaly baseline)
    overload.js          # k6 overload
    overload.sh          # bash fallback
  appd/
    db-agent/            # config for Database Visibility collector
    healthrules.md       # click-through guide: Health Rule / Policy / Action
  RUNBOOK.md             # step-by-step for the live demo (write in German, see below)
```

## Key configuration

### orders service (the bottleneck)

`application.yml`:
```yaml
spring:
  datasource:
    url: jdbc:postgresql://postgres:5432/appdb
    username: appuser
    password: apppass
    hikari:
      maximum-pool-size: 5
      connection-timeout: 10000      # 10s -> fast, visible errors
      pool-name: orders-pool
      register-mbeans: true          # expose HikariCP JMX MBeans
```

Overload endpoint (holds connections for a long time):
```
GET /api/orders/slow   -> runs "SELECT pg_sleep(5), ..."
GET /api/orders/health -> fast query (contrast)
```
`pg_sleep(5)` holds a connection for 5s. With pool=5 and ~30 concurrent requests,
the waiting ones run into `connection-timeout` and HikariCP throws
`SQLTransientConnectionException: ... request timed out`. In Phase 2 the Java
agent captures this as a BT error + slow call.

**Phase 1 verification without AppD:** enable Actuator + Micrometer so the
overload is visible already:
```yaml
management:
  endpoints.web.exposure.include: health,metrics,prometheus
  metrics.enable.hikaricp: true
```
Check via `hikaricp.connections.pending` and `hikaricp.connections.active`
(Actuator/Prometheus endpoint) plus the HikariCP warning
`Connection is not available, request timed out` in the log. This is the
acceptance criterion for Phase 1.

### frontend / inventory

- `frontend`: calls `orders/slow` and `inventory` (makes the chain visible so the
  anomaly propagates from `orders` to `frontend`).
- `inventory`: normal pool (e.g. 10), fast queries.

### PostgreSQL (`db/init.sql`)

- Schema `appdb`, a few tables with seed data.
- App user `appuser`.
- Monitoring user for the DB agent with read access to `pg_stat_*` (for Database
  Visibility). Create this already in Phase 1 so Phase 2 changes nothing on the DB.

## Phase 2: instrumentation (additive, no code changes)

Everything below is added only once controller access and agent binaries exist.
It changes **no** application code: only JVM args, env vars, extra containers, and
controller configuration. Build the Java agent binding via env var so that, when
empty/absent, it is simply ignored (e.g. `JAVA_TOOL_OPTIONS` set only when
`AGENT_ENABLED=true`).

### AppDynamics Java agent (per service)

As JVM args / env vars (in docker-compose per service, vary tier/node name):
```
-javaagent:/opt/appdynamics/javaagent.jar
-Dappdynamics.controller.hostName=${CONTROLLER_HOST}
-Dappdynamics.controller.port=${CONTROLLER_PORT}
-Dappdynamics.controller.ssl.enabled=${SSL_ENABLED}
-Dappdynamics.agent.accountName=${ACCOUNT_NAME}
-Dappdynamics.agent.accountAccessKey=${ACCOUNT_ACCESS_KEY}
-Dappdynamics.agent.applicationName=AFI-UC3-Demo
-Dappdynamics.agent.tierName=orders          # resp. frontend / inventory
-Dappdynamics.agent.nodeName=orders-01
```
Mount the agent jar via volume from `./agents/javaagent.jar` into the container.

### Making the HikariCP metric visible in AppD

MBean: `com.zaxxer.hikari:type=Pool (orders-pool)`, attributes include
`ActiveConnections`, `IdleConnections`, `TotalConnections`,
`ThreadsAwaitingConnection`.

Two ways (document both in the RUNBOOK, way A preferred):
- **A) Java agent JMX metric rule** in the controller: capture
  `ThreadsAwaitingConnection` from the MBean above as a custom metric.
- **B) Machine agent JMX extension** as an alternative.

This metric is the clearest early-detection signal and the basis for the Health
Rule.

### Database Visibility agent (`db-agent`)

- Separate process/container: `java -jar db-agent.jar` with controller config.
- In the controller, create a **PostgreSQL collector** (host `postgres`, port
  5432, monitoring user). Shows top queries, sessions, connections on the DB side.
- Expected picture during the demo: the DB is **not** saturated (few active
  sessions running `pg_sleep`). Story: the bottleneck is the pool, not the DB.

### Anomaly Detection + Health Rule + Policy/Action (the scoring piece)

In the controller (guide in `appd/healthrules.md`):
1. Enable **Anomaly Detection** for `AFI-UC3-Demo`. First create a **baseline**
   with `normal.js` (a few minutes of normal load) so the later spike is
   recognized as an anomaly.
2. **Health Rule** "Pool Exhaustion":
   - Condition 1: custom metric `ThreadsAwaitingConnection > 0` (Warning),
     `>= 5` (Critical), 1 min.
   - Condition 2 (OR): BT error rate on `orders` above baseline.
3. **Policy** on the Health Rule -> **Action**: email/webhook OR a visible event.
   This is how the anomaly is propagated to the user.

## Build order (for you, Claude Code)

**Phase 1 (now, agent-free):**
1. `.env.example` + docker-compose skeleton (postgres, 3 services).
2. Implement the three Spring Boot services minimally (endpoints + JDBC),
   Actuator/Micrometer enabled, `orders` with small pool + `register-mbeans`.
3. `db/init.sql` with schema, seed, monitoring user (the latter already now so
   Phase 2 needs no DB change).
4. `loadtest/` with `normal.js`, `overload.js`, `overload.sh`.
5. Start, check the chain (frontend -> orders/slow -> DB) and **verify the
   overload without AppD**: HikariCP timeout errors in the log +
   `hikaricp.connections.pending` rising via Actuator. -> acceptance criterion.
6. Create `RUNBOOK.md` (Phase 1 part: how to trigger the overload and make it
   visible without AppD). Write RUNBOOK.md in German (see conventions).

**Phase 2 (later, additive, after controller + agents are provided):**
7. Wire in the Java agent via env var/volume, check the flow map (3 tiers + DB).
8. Wire in DB agent + Machine agent (host nodes -> >= 5 components).
9. Run baseline load, then set up Anomaly Detection + Health Rule + Policy.
10. Extend `RUNBOOK.md` with the AppD part (click/command steps for the live
    demo), in German.

Pause at the end of Phase 1 and confirm to the user that the overload is
reproducible before starting Phase 2.

## RUNBOOK content (write RUNBOOK.md in German, Swiss spelling)

The generated `RUNBOOK.md` is human-facing and used in a German-speaking context,
close to the AFI presentation. Write it in German, Swiss spelling (no scharfes s),
no em dashes. Use the target flow below as its content (extend the AppD-specific
steps in Phase 2).

### Demo-Ablauf (Zielbild)

1. Flow Map zeigen: `frontend -> orders -> DB`, `orders -> inventory -> DB`,
   Hosts. >= 5 Komponenten, alles gruen.
2. `normal.js` kurz laufen lassen: stabile Antwortzeiten, Pool ruhig.
3. `overload.js` starten: `orders/slow` unter Last.
4. Live sichtbar machen:
   - HikariCP `ThreadsAwaitingConnection` steigt.
   - `orders` wird kritisch, Fehler `Connection is not available ... timed out`.
   - Anomalie propagiert auf `frontend` (Flow Map wird gelb/rot).
   - Anomaly-Detection-Event + Health-Rule-Violation + Alert erscheinen.
   - DB-Agent: DB ist ruhig -> Engpass ist der Pool, nicht die DB.
5. Aussage: das System hat die Anomalie frueh erkannt und propagiert (Event +
   Alert + Flow-Map-Faerbung).

## Conventions

- Build/spec docs (this CLAUDE.md) in English. The human-facing `RUNBOOK.md` in
  German, Swiss spelling (no scharfes s).
- No em dashes anywhere.
- Secrets only via `.env`, never commit. `.env` in `.gitignore`.
- Do not commit agent jars (`agents/` in `.gitignore`, except a placeholder).
