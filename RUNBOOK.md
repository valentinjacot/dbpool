# RUNBOOK - AFI APM Demo, Use Case 3 (Anomaly Detection)

Dieses Runbook beschreibt, wie die Demo lokal gestartet und die DB-Connection-
Pool-Ueberlastung reproduziert wird. Stand: Phase 1 (agentenfrei). Der
AppDynamics-Teil (Flow Map, Health Rule, Anomaly Detection) wird in Phase 2
ergaenzt, sobald Controller-Zugang und Agent-Binaries vorliegen.

## Voraussetzungen

- Docker und Docker Compose
- Optional: k6 lokal installiert, sonst laeuft k6 ueber den Docker-Container
  `grafana/k6` (Beispiele unten), oder man nutzt den Bash-Fallback
  `loadtest/overload.sh`

## 1. Umgebung vorbereiten

```bash
cp .env.example .env
# .env bei Bedarf anpassen, Passwoerter sind fuer die Demo unkritisch
```

## 2. Stack starten

```bash
docker compose up -d --build
docker compose ps
```

Erwartung: `afi-postgres`, `afi-orders`, `afi-inventory`, `afi-frontend`,
`afi-postgres-exporter`, `afi-prometheus` und `afi-grafana` laufen. Postgres
muss `healthy` sein, bevor `orders` und `inventory` hochfahren (Dependency in
`docker-compose.yml`).

Health-Checks pruefen:

```bash
curl -s http://localhost:8080/api/shop/health
curl -s http://localhost:8081/actuator/health
curl -s http://localhost:8082/actuator/health
```

## 3. Kette pruefen (frontend -> orders -> inventory -> DB)

```bash
curl -s http://localhost:8080/api/shop/checkout | jq
```

Erwartete Antwort: `status: ok`, mit Order-Resultat (inkl. 5 Sekunden
Wartezeit wegen `pg_sleep(5)`) und Inventory-Liste. Das bestaetigt, dass die
komplette Kette funktioniert.

## 4. Normallast fahren (Baseline)

Mit lokal installiertem k6:

```bash
k6 run loadtest/normal.js
```

Ohne lokales k6, ueber Docker:

```bash
docker run --rm --network host -v "$PWD/loadtest:/scripts" grafana/k6 run /scripts/normal.js
```

Erwartung: stabile Antwortzeiten (dominiert durch die 5s `pg_sleep`), keine
Fehler, Pool bleibt ruhig. Das ist die Baseline fuer spaeter (Phase 2:
Anomaly-Detection-Baseline).

Pool-Zustand waehrend der Normallast beobachten:

```bash
curl -s http://localhost:8081/actuator/metrics/hikaricp.connections.active
curl -s http://localhost:8081/actuator/metrics/hikaricp.connections.pending
```

## 5. Ueberlastung auslösen

Mit k6:

```bash
docker run --rm --network host -v "$PWD/loadtest:/scripts" grafana/k6 run /scripts/overload.js
```

Oder mit dem Bash-Fallback (30 gleichzeitige Requests, 300 total):

```bash
./loadtest/overload.sh 30 300
```

**Kombiniertes Szenario fuer die Live-Demo:** `loadtest/scenario.js` bzw.
`loadtest/scenario.sh` fahren Schritt 4 und 5 in einem Lauf: zuerst ruhige
Baseline (Standard 5 Minuten), danach automatisch die Ueberlastung
(Standard 2 Minuten). Damit muss man waehrend der Demo nichts manuell
umschalten.

Mit k6:

```bash
docker run --rm --network host -v "$PWD/loadtest:/scripts" \
  -e BASELINE_DURATION=5m -e OVERLOAD_DURATION=2m \
  grafana/k6 run /scripts/scenario.js
```

Oder mit dem Bash-Fallback (Reihenfolge: base_url, baseline_seconds,
overload_seconds, overload_concurrency):

```bash
./loadtest/scenario.sh http://localhost:8080 300 120 30
```

## 6. Ueberlastung ohne AppDynamics sichtbar machen

Das ist das Abnahmekriterium fuer Phase 1: die Anomalie ist erkennbar, auch
ohne Monitoring-Agent.

**a) HikariCP-Metriken via Actuator/Prometheus (waehrend der Ueberlastung
in einem zweiten Terminal laufen lassen):**

```bash
watch -n 1 'curl -s http://localhost:8081/actuator/metrics/hikaricp.connections.pending; echo; curl -s http://localhost:8081/actuator/metrics/hikaricp.connections.active'
```

Erwartung: `hikaricp.connections.active` steigt auf 5 (Poolgroesse),
`hikaricp.connections.pending` steigt darueber hinaus an, solange die Last
laeuft.

Alternative: Prometheus-Format direkt lesen:

```bash
curl -s http://localhost:8081/actuator/prometheus | grep hikaricp_connections
```

**b) HikariCP-Fehler im Log:**

```bash
docker compose logs -f orders
```

Erwartung: Meldungen wie

```
com.zaxxer.hikari.pool.HikariPool$PoolInitializationException
... Connection is not available, request timed out after 3000ms
SQLTransientConnectionException: orders-pool - Connection is not available, request timed out after 3000ms
```

sowie HTTP 502-Antworten vom `frontend` (Kette propagiert den Fehler von
`orders` nach `frontend`, sichtbar im Antwortcode von
`/api/shop/checkout`).

**c) Kontrast DB-Seite (fuer die spaetere Story in Phase 2):**

```bash
docker compose exec postgres psql -U appuser -d appdb -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';"
```

Erwartung: nur wenige aktive Sessions (die mit `pg_sleep`), die Datenbank
selbst ist nicht ueberlastet. Das untermauert die Aussage aus dem Zielbild:
der Engpass ist der Pool, nicht die Datenbank.

**d) Grafana-Dashboard (visuelle Kontrolle ohne AppD, als Vergleichsbasis
fuer spaeter):**

Prometheus und Grafana sind Teil des Compose-Stacks (siehe
`observability/`) und scrapen die bereits vorhandenen Actuator-Endpunkte
sowie Postgres (via `postgres-exporter` mit dem `appd_monitor`-Benutzer).
Kein zusaetzlicher Schritt noetig, das Dashboard ist automatisch
provisioniert.

- Grafana: http://localhost:3001 (anonymer Viewer-Zugriff aktiv, Login
  `admin` / `admin` bzw. `$GRAFANA_ADMIN_PASSWORD` fuer Aenderungen). Port
  ueber `GRAFANA_HOST_PORT` in `.env` anpassbar, Standard 3001 statt 3000,
  damit kein Konflikt mit anderen lokalen Grafana-Stacks entsteht.
- Dashboard: "AFI UC3 - DB Connection Pool Overload (Phase 1, no AppD)"
- Prometheus direkt: http://localhost:9091 (Port ueber
  `PROMETHEUS_HOST_PORT` anpassbar, Standard 9091 statt 9090)

Panels:

1. Orders-Pool: aktive vs. idle Verbindungen (Maximum = 5)
2. Orders-Pool: `ThreadsAwaitingConnection` (Pending) mit Schwellenwerten
   bei 1 (Warning) und 5 (Critical), analog zur spaeteren Health Rule
   "Pool Exhaustion" aus `appd/healthrules.md`
3. Orders: Connection-Timeout-Fehler pro Minute
4. Frontend: 5xx-Fehlerrate (zeigt die Propagation von `orders` nach
   `frontend`)
5. Inventory-Pool: aktive Verbindungen (Kontrast, bleibt unberuehrt)
6. Postgres: verbundene Backends auf `appdb` (bleibt ruhig)

Waehrend `overload.js` oder `overload.sh` laeuft, das Dashboard offen
lassen (Auto-Refresh 5s, Zeitfenster 15 Minuten). Dies ist der direkte
Vergleichspunkt fuer die spaetere AppD-Ansicht (Flow Map, Health Rule,
Anomaly-Detection-Event): dieselben Signale, hier ohne Agent aus
Actuator-Metriken.

## 7. Ueberlastung beenden / zuruecksetzen

```bash
# Lasttest einfach abwarten oder abbrechen (Ctrl+C)
# Pool erholt sich automatisch, sobald keine neue Last mehr kommt
curl -s http://localhost:8081/actuator/metrics/hikaricp.connections.active
```

## 8. Phase 2 vorbereitet (Agenten vorhanden, Controller-Zugang steht noch aus)

Die AppDynamics-Agent-Binaries (Java Agent, Database Agent, Machine Agent)
sind bereits heruntergeladen, unter `./agents/` entpackt (nicht committed)
und in `docker-compose.yml` verdrahtet. Getestet mit einem ungueltigen
Controller-Host: alle drei Agenten starten sauber, lesen ihre Konfiguration
korrekt aus den Umgebungsvariablen und scheitern erwartungsgemaess nur an
der DNS-Aufloesung des Controllers. Details siehe `appd/healthrules.md`.

Solange `.env` keine echten Controller-Werte enthaelt, bleibt der Stack
100% Phase-1-Verhalten: `docker compose up -d` startet den Java Agent nicht
(`AGENT_ENABLED=false`), und `db-agent`/`machine-agent` starten ueberhaupt
nicht (Compose-Profile `appd`, nicht Teil des Standard-Starts).

Sobald Controller-Zugang existiert:

```bash
# In .env setzen: AGENT_ENABLED=true, CONTROLLER_HOST, CONTROLLER_PORT,
# SSL_ENABLED, ACCOUNT_NAME, ACCOUNT_ACCESS_KEY
docker compose up -d                          # frontend/orders/inventory neu mit Java Agent
docker compose --profile appd up -d db-agent machine-agent
```

Danach in der Controller-UI pruefen: 3 Tiers + 1 DB-Node + 1 Host-Node = 5
Komponenten auf der Flow Map. Die weiteren Schritte (JMX-Metric-Regel,
PostgreSQL-Collector, Anomaly-Detection-Baseline, Health Rule, Policy/
Action) sind in `appd/healthrules.md` vorbereitet und werden nach dem
ersten Controller-Zugriff hier im Runbook ergaenzt.

## Demo-Ablauf (Zielbild, inkl. Phase 2)

1. Flow Map zeigen: `frontend -> orders -> DB`, `orders -> inventory -> DB`,
   Hosts. Mindestens 5 Komponenten, alles gruen. (Phase 2)
2. `normal.js` kurz laufen lassen: stabile Antwortzeiten, Pool ruhig.
3. `overload.js` starten: `orders/slow` unter Last.
4. Live sichtbar machen:
   - HikariCP `ThreadsAwaitingConnection` steigt.
   - `orders` wird kritisch, Fehler `Connection is not available ... timed
     out`.
   - Anomalie propagiert auf `frontend` (Flow Map wird gelb/rot). (Phase 2)
   - Anomaly-Detection-Event, Health-Rule-Violation und Alert erscheinen.
     (Phase 2)
   - DB-Agent: DB ist ruhig, Engpass ist der Pool, nicht die DB. (Phase 2)
5. Aussage: das System hat die Anomalie frueh erkannt und propagiert
   (Event, Alert, Flow-Map-Faerbung).

Phase 1 deckt die Schritte 2 bis 4 (ohne Flow Map und ohne AppD-Events) sowie
den DB-Kontrast in Schritt 4 bereits ab. Phase 2 ergaenzt Flow Map, Anomaly
Detection, Health Rule und Alerting gemaess `appd/healthrules.md`.

## Stack stoppen

```bash
docker compose down
# mit -v werden auch die Postgres-Daten geloescht:
docker compose down -v
```
