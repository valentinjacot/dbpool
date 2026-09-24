-- AFI APM Demo UC3 - schema, seed data, monitoring user
-- Runs once on first container start (mounted into /docker-entrypoint-initdb.d)
-- Executed as the POSTGRES_USER superuser (appuser).

CREATE SCHEMA IF NOT EXISTS appdb AUTHORIZATION appuser;

SET search_path TO appdb;

CREATE TABLE IF NOT EXISTS products (
    id          SERIAL PRIMARY KEY,
    sku         TEXT NOT NULL UNIQUE,
    name        TEXT NOT NULL,
    price_cents INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS inventory (
    product_id  INTEGER PRIMARY KEY REFERENCES products(id),
    quantity    INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS orders (
    id          SERIAL PRIMARY KEY,
    product_id  INTEGER NOT NULL REFERENCES products(id),
    quantity    INTEGER NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Phase 3: checkout's own fast, non-blocking DB touch (its HikariCP pool
-- stays calm throughout, unlike orders' - see CLAUDE.md Phase 3).
CREATE TABLE IF NOT EXISTS checkout_log (
    id          SERIAL PRIMARY KEY,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO products (sku, name, price_cents) VALUES
    ('SKU-001', 'Widget A', 1999),
    ('SKU-002', 'Widget B', 2999),
    ('SKU-003', 'Widget C', 4999),
    ('SKU-004', 'Gadget X', 9999),
    ('SKU-005', 'Gadget Y', 14999)
ON CONFLICT (sku) DO NOTHING;

INSERT INTO inventory (product_id, quantity)
SELECT id, 100 FROM products
ON CONFLICT (product_id) DO NOTHING;

-- ---------------------------------------------------------------------
-- Monitoring user for the AppDynamics Database Visibility agent (Phase 2).
-- Created already in Phase 1 so Phase 2 requires no DB changes.
-- pg_monitor is a built-in Postgres role granting read access to
-- pg_stat_activity, pg_stat_statements etc. without superuser rights.
-- ---------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'appd_monitor') THEN
        CREATE ROLE appd_monitor WITH LOGIN PASSWORD 'appd_monitor_pass';
    END IF;
END
$$;

GRANT pg_monitor TO appd_monitor;
GRANT CONNECT ON DATABASE appdb TO appd_monitor;
GRANT USAGE ON SCHEMA appdb TO appd_monitor;
GRANT SELECT ON ALL TABLES IN SCHEMA appdb TO appd_monitor;
