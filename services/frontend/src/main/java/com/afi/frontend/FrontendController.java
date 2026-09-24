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
    private final String checkoutUrl;

    public FrontendController(RestClient.Builder builder,
                               @Value("${services.checkout-url}") String checkoutUrl) {
        this.restClient = builder.build();
        this.checkoutUrl = checkoutUrl;
    }

    /**
     * Chains frontend -> checkout -> orders/slow so the pool overload on
     * orders is visible two tiers up (anomaly propagation across the flow
     * map: orders -> checkout -> frontend, see Phase 3 in CLAUDE.md).
     */
    @GetMapping("/api/shop/checkout")
    public ResponseEntity<Map<String, Object>> checkout() {
        try {
            Map<?, ?> checkoutResult = restClient.get().uri(checkoutUrl + "/api/checkout")
                    .retrieve().body(Map.class);
            return ResponseEntity.ok(Map.of(
                    "status", "ok",
                    "checkout", checkoutResult
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
