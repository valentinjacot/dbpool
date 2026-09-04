# AppDynamics Health Rule / Policy / Action setup

Placeholder for Phase 2. Filled in once controller access and agent binaries
are available (see CLAUDE.md, section "Phase 2: instrumentation").

Will document, click by click:
- JMX metric rule (Way A) capturing `ThreadsAwaitingConnection` from
  `com.zaxxer.hikari:type=Pool (orders-pool)`, alternative Machine Agent JMX
  extension (Way B).
- PostgreSQL collector setup for the Database Visibility agent.
- Anomaly Detection baseline (using `loadtest/normal.js`).
- Health Rule "Pool Exhaustion" (conditions, thresholds).
- Policy -> Action (email/webhook/visible event).
