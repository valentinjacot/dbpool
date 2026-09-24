// Overload load: drives concurrent requests against orders/slow (now
// reached via frontend -> checkout -> orders, so the flow map shows
// propagation across two tiers) well beyond the 5-connection HikariCP pool
// on the orders service. Expect HikariCP connection-timeout errors and
// rising ThreadsAwaitingConnection / pending connections.
//
// Also runs the same always-on low-rate reporting scenario as normal.js
// (Phase 3, CLAUDE.md) throughout the overload - reporting must stay a
// flat green line even while orders is on fire, proving the bottleneck is
// the pool, not the database.
//
// Run: docker run --rm --network host -v "$PWD:/scripts" grafana/k6 run /scripts/overload.js
import http from 'k6/http';
import { sleep, check } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const REPORTING_URL = __ENV.REPORTING_URL || 'http://localhost:8084';
const DURATION = __ENV.DURATION || '2m';
const REPORTING_RATE_PER_MIN = Number(__ENV.REPORTING_RATE_PER_MIN || 3);

export const options = {
    scenarios: {
        overload: {
            executor: 'constant-vus',
            vus: 30,
            duration: DURATION,
            exec: 'checkout',
        },
        reporting: {
            executor: 'constant-arrival-rate',
            rate: REPORTING_RATE_PER_MIN,
            timeUnit: '1m',
            duration: DURATION,
            preAllocatedVUs: 2,
            maxVUs: 5,
            exec: 'reporting',
        },
    },
};

export function checkout() {
    const res = http.get(`${BASE_URL}/api/shop/checkout`, { timeout: '15s' });
    check(res, { 'status is 200': (r) => r.status === 200 });
    sleep(0.2);
}

export function reporting() {
    const res = http.get(`${REPORTING_URL}/api/reporting/summary`);
    check(res, { 'reporting status is 200': (r) => r.status === 200 });
}
