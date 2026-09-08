// Full demo scenario: quiet baseline first, then the pool overload kicks
// in automatically - one script for the whole live-demo timeline instead
// of running normal.js then overload.js by hand.
//
// Run: docker run --rm --network host -v "$PWD:/scripts" grafana/k6 run /scripts/scenario.js
//
// Override via -e: BASE_URL, BASELINE_DURATION, BASELINE_VUS,
// OVERLOAD_DURATION, OVERLOAD_VUS. Defaults give a 5 min calm baseline
// followed by a 2 min overload.
import http from 'k6/http';
import { sleep, check } from 'k6';
import exec from 'k6/execution';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const BASELINE_DURATION = __ENV.BASELINE_DURATION || '5m';
const BASELINE_VUS = Number(__ENV.BASELINE_VUS || 2);
const OVERLOAD_DURATION = __ENV.OVERLOAD_DURATION || '2m';
const OVERLOAD_VUS = Number(__ENV.OVERLOAD_VUS || 30);

export const options = {
    scenarios: {
        baseline: {
            executor: 'constant-vus',
            vus: BASELINE_VUS,
            duration: BASELINE_DURATION,
            exec: 'checkout',
        },
        overload: {
            executor: 'constant-vus',
            vus: OVERLOAD_VUS,
            duration: OVERLOAD_DURATION,
            startTime: BASELINE_DURATION,
            exec: 'checkout',
        },
    },
};

export function checkout() {
    const res = http.get(`${BASE_URL}/api/shop/checkout`, { timeout: '15s' });
    check(res, { 'status is 200': (r) => r.status === 200 });
    // baseline paces itself at ~1 req/s per VU, overload fires back to back
    sleep(exec.scenario.name === 'baseline' ? 1 : 0.2);
}
