// Baseline load for AppD Anomaly Detection baselining (Phase 2) and for
// showing "everything is calm" before the overload in the demo.
// Run: docker run --rm --network host -v "$PWD:/scripts" grafana/k6 run /scripts/normal.js
import http from 'k6/http';
import { sleep, check } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export const options = {
    scenarios: {
        baseline: {
            executor: 'constant-vus',
            vus: 2,
            duration: __ENV.DURATION || '3m',
        },
    },
    thresholds: {
        http_req_failed: ['rate<0.01'],
    },
};

export default function () {
    const res = http.get(`${BASE_URL}/api/shop/checkout`);
    check(res, { 'status is 200': (r) => r.status === 200 });
    sleep(1);
}
