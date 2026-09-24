package com.afi.reporting;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class ReportingController {

    private final JdbcTemplate jdbcTemplate;

    public ReportingController(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    /**
     * Independent control consumer of the same PostgreSQL (see Phase 3 in
     * CLAUDE.md): fast, real aggregation reads only, never pg_sleep, never
     * connection-holding. Stays a flat green line through baseline and
     * overload alike, proving the bottleneck is the orders pool, not the DB.
     */
    @GetMapping("/api/reporting/summary")
    public Map<String, Object> summary() {
        Map<String, Object> stats = jdbcTemplate.queryForMap(
                "SELECT "
                        + "(SELECT count(*) FROM appdb.products) AS product_count, "
                        + "(SELECT coalesce(sum(quantity), 0) FROM appdb.inventory) AS total_inventory, "
                        + "(SELECT coalesce(sum(p.price_cents * i.quantity), 0) "
                        + "   FROM appdb.inventory i JOIN appdb.products p ON p.id = i.product_id) AS total_inventory_value_cents, "
                        + "(SELECT count(*) FROM appdb.orders) AS order_count, "
                        + "(SELECT count(*) FROM appdb.checkout_log) AS checkout_count");
        return Map.of("status", "ok", "stats", stats);
    }

    @GetMapping("/api/reporting/health")
    public Map<String, Object> health() {
        Integer result = jdbcTemplate.queryForObject("SELECT 1", Integer.class);
        return Map.of("status", "ok", "check", result);
    }
}
