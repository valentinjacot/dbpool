package com.afi.frontend;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import java.util.Map;

@RestController
public class FrontendController {

    private final RestClient restClient;
    private final String ordersUrl;
    private final String inventoryUrl;

    public FrontendController(RestClient.Builder builder,
                               @Value("${services.orders-url}") String ordersUrl,
                               @Value("${services.inventory-url}") String inventoryUrl) {
        this.restClient = builder.build();
        this.ordersUrl = ordersUrl;
        this.inventoryUrl = inventoryUrl;
    }

    /**
     * Chains frontend -> orders/slow so the pool overload on orders is
     * visible from the frontend tier too (anomaly propagation up the flow map).
     */
    @GetMapping("/api/shop/checkout")
    public ResponseEntity<Map<String, Object>> checkout() {
        try {
            Map<?, ?> orderResult = restClient.get().uri(ordersUrl + "/api/orders/slow")
                    .retrieve().body(Map.class);
            Object inventoryResult = restClient.get().uri(inventoryUrl + "/api/inventory")
                    .retrieve().body(Object.class);
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

    @GetMapping("/api/shop/health")
    public Map<String, Object> health() {
        return Map.of("status", "ok");
    }
}
