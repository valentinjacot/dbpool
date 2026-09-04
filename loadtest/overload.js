// Overload load: drives concurrent requests against orders/slow (via the
// frontend, so the flow map shows propagation) well beyond the 5-connection
// HikariCP pool on the orders service. Expect HikariCP connection-timeout
// errors and rising ThreadsAwaitingConnection / pending connections.
// Run: docker run --rm --network host -v "$PWD:/scripts" grafana/k6 run /scripts/overload.js
import http from 'k6/http';
import { sleep, check } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export const options = {
    scenarios: {
        overload: {
            executor: 'constant-vus',
            vus: 30,
            duration: __ENV.DURATION || '2m',
        },
    },
};

export default function () {
    const res = http.get(`${BASE_URL}/api/shop/checkout`, { timeout: '15s' });
    check(res, { 'status is 200': (r) => r.status === 200 });
    sleep(0.2);
}
