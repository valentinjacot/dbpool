package com.afi.orders;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class OrdersController {

    private final JdbcTemplate jdbcTemplate;

    public OrdersController(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    /**
     * Deliberately slow endpoint: pg_sleep(5) holds a pool connection for 5s.
     * With maximum-pool-size=5 and concurrent load this exhausts the pool
     * and drives HikariCP connection-timeout errors -> the anomaly to detect.
     */
    @GetMapping("/api/orders/slow")
    public Map<String, Object> slow() {
        Integer count = jdbcTemplate.queryForObject(
                "SELECT count(*) FROM appdb.orders", Integer.class);
        jdbcTemplate.execute("SELECT pg_sleep(5)");
        return Map.of(
                "status", "ok",
                "orderCount", count == null ? 0 : count
        );
    }

    @GetMapping("/api/orders/health")
    public Map<String, Object> health() {
        Integer result = jdbcTemplate.queryForObject("SELECT 1", Integer.class);
        return Map.of("status", "ok", "check", result);
    }
}
