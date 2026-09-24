// Full demo scenario: quiet baseline first, then the pool overload kicks
// in automatically - one script for the whole live-demo timeline instead
// of running normal.js then overload.js by hand.
//
// Run: docker run --rm --network host -v "$PWD:/scripts" grafana/k6 run /scripts/scenario.js
//
// Override via -e: BASE_URL, BASELINE_DURATION, BASELINE_VUS,
// OVERLOAD_DURATION, OVERLOAD_VUS, REPORTING_URL, REPORTING_RATE_PER_MIN.
// Defaults give a 5 min calm baseline followed by a 2 min overload.
//
// Also runs the always-on low-rate reporting scenario (Phase 3, CLAUDE.md)
// for the full combined duration, spanning both phases - reporting must
// stay calm whether the rest of the system is calm or on fire.
import http from 'k6/http';
import { sleep, check } from 'k6';
import exec from 'k6/execution';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const REPORTING_URL = __ENV.REPORTING_URL || 'http://localhost:8084';
const BASELINE_DURATION = __ENV.BASELINE_DURATION || '5m';
const BASELINE_VUS = Number(__ENV.BASELINE_VUS || 2);
const OVERLOAD_DURATION = __ENV.OVERLOAD_DURATION || '2m';
const OVERLOAD_VUS = Number(__ENV.OVERLOAD_VUS || 30);
const REPORTING_RATE_PER_MIN = Number(__ENV.REPORTING_RATE_PER_MIN || 3);

// Simple "5m" / "30s" / "1h" duration string -> seconds. Only single-unit
// strings are supported, which is all this script's own defaults ever use.
function toSeconds(duration) {
    const match = /^(\d+(?:\.\d+)?)(ms|s|m|h)$/.exec(duration.trim());
    if (!match) {
        throw new Error(`Unsupported duration format: ${duration}`);
    }
    const value = Number(match[1]);
    const unit = match[2];
    const factor = { ms: 0.001, s: 1, m: 60, h: 3600 }[unit];
    return value * factor;
}

const TOTAL_DURATION = `${toSeconds(BASELINE_DURATION) + toSeconds(OVERLOAD_DURATION)}s`;

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
        reporting: {
            executor: 'constant-arrival-rate',
            rate: REPORTING_RATE_PER_MIN,
            timeUnit: '1m',
            duration: TOTAL_DURATION,
            preAllocatedVUs: 2,
            maxVUs: 5,
            exec: 'reporting',
        },
    },
};

export function checkout() {
    const res = http.get(`${BASE_URL}/api/shop/checkout`, { timeout: '15s' });
    check(res, { 'status is 200': (r) => r.status === 200 });
    // baseline paces itself at ~1 req/s per VU, overload fires back to back
    sleep(exec.scenario.name === 'baseline' ? 1 : 0.2);
}

export function reporting() {
    const res = http.get(`${REPORTING_URL}/api/reporting/summary`);
    check(res, { 'reporting status is 200': (r) => r.status === 200 });
}
