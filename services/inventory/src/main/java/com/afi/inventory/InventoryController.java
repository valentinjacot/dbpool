package com.afi.inventory;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

@RestController
public class InventoryController {

    private final JdbcTemplate jdbcTemplate;

    public InventoryController(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @GetMapping("/api/inventory")
    public List<Map<String, Object>> list() {
        return jdbcTemplate.queryForList(
                "SELECT p.sku, p.name, i.quantity " +
                        "FROM appdb.inventory i JOIN appdb.products p ON p.id = i.product_id " +
                        "ORDER BY p.id");
    }

    @GetMapping("/api/inventory/health")
    public Map<String, Object> health() {
        Integer result = jdbcTemplate.queryForObject("SELECT 1", Integer.class);
        return Map.of("status", "ok", "check", result);
    }
}
