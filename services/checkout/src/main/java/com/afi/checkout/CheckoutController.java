package com.afi.checkout;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import java.util.Map;

@RestController
public class CheckoutController {

    private final RestClient restClient;
    private final JdbcTemplate jdbcTemplate;
    private final String ordersUrl;
    private final String inventoryUrl;

    public CheckoutController(RestClient.Builder builder,
                               JdbcTemplate jdbcTemplate,
                               @Value("${services.orders-url}") String ordersUrl,
                               @Value("${services.inventory-url}") String inventoryUrl) {
        this.restClient = builder.build();
        this.jdbcTemplate = jdbcTemplate;
        this.ordersUrl = ordersUrl;
        this.inventoryUrl = inventoryUrl;
    }

    /**
     * Orchestrates orders/slow + inventory (moved here from frontend, see
     * Phase 3 in CLAUDE.md). The overload on orders now propagates through
     * two tiers: orders -> checkout -> frontend. The audit insert below is
     * checkout's own fast, non-blocking DB touch - its HikariCP pool
     * (checkout-pool) stays calm throughout, unlike orders'.
     */
    @GetMapping("/api/checkout")
    public ResponseEntity<Map<String, Object>> checkout() {
        try {
            Map<?, ?> orderResult = restClient.get().uri(ordersUrl + "/api/orders/slow")
                    .retrieve().body(Map.class);
            Object inventoryResult = restClient.get().uri(inventoryUrl + "/api/inventory")
                    .retrieve().body(Object.class);
            jdbcTemplate.update("INSERT INTO appdb.checkout_log DEFAULT VALUES");
            return ResponseEntity.ok(Map.of(
                    "status", "ok",
                    "order", orderResult,
                    "inventory", inventoryResult
            ));
        } catch (RestClientException e) {
            return ResponseEntity.status(HttpStatus.BAD_GATEWAY)
                    .body(Map.of("status", "error", "message", e.getMessage()));
        }
    }

    @GetMapping("/api/checkout/health")
    public Map<String, Object> health() {
        Integer result = jdbcTemplate.queryForObject("SELECT 1", Integer.class);
        return Map.of("status", "ok", "check", result);
    }
}
