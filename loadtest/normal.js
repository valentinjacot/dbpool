// Baseline load for AppD Anomaly Detection baselining (Phase 2) and for
// showing "everything is calm" before the overload in the demo.
//
// Two independent scenarios (Phase 3, CLAUDE.md): the usual frontend
// checkout traffic, plus a separate always-on low-rate scenario against
// reporting - the healthy control consumer of the same PostgreSQL. It runs
// here too (not just in overload.js) so its baseline is established the
// same way orders' is.
//
// Run: docker run --rm --network host -v "$PWD:/scripts" grafana/k6 run /scripts/normal.js
import http from 'k6/http';
import { sleep, check } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const REPORTING_URL = __ENV.REPORTING_URL || 'http://localhost:8084';
const DURATION = __ENV.DURATION || '3m';
const REPORTING_RATE_PER_MIN = Number(__ENV.REPORTING_RATE_PER_MIN || 3);

export const options = {
    scenarios: {
        baseline: {
            executor: 'constant-vus',
            vus: 2,
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
    thresholds: {
        http_req_failed: ['rate<0.01'],
    },
};

export function checkout() {
    const res = http.get(`${BASE_URL}/api/shop/checkout`);
    check(res, { 'status is 200': (r) => r.status === 200 });
    sleep(1);
}

export function reporting() {
    const res = http.get(`${REPORTING_URL}/api/reporting/summary`);
    check(res, { 'reporting status is 200': (r) => r.status === 200 });
}
