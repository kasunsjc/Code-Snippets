import http from 'k6/http';
import { check } from 'k6';

if (!__ENV.BASE_URL) {
  throw new Error('BASE_URL is required; use the HTTPS ingress hostname to populate Traefik metrics.');
}

const baseUrl = __ENV.BASE_URL.replace(/\/$/, '');
const duration = __ENV.DURATION || '6m';

export const options = {
  discardResponseBodies: true,
  scenarios: {
    breach_300ms: {
      executor: 'constant-arrival-rate',
      exec: 'breach300ms',
      rate: 2,
      timeUnit: '1s',
      duration,
      preAllocatedVUs: 4,
      maxVUs: 8,
      gracefulStop: '15s',
    },
    breach_1200ms: {
      executor: 'constant-arrival-rate',
      exec: 'breach1200ms',
      rate: 2,
      timeUnit: '1s',
      duration,
      preAllocatedVUs: 8,
      maxVUs: 16,
      gracefulStop: '15s',
    },
  },
  thresholds: {
    checks: ['rate>0.99'],
    http_req_failed: ['rate<0.01'],
    dropped_iterations: ['count==0'],
    'http_req_duration{endpoint:delay-0.5s}': ['p(95)>300'],
    'http_req_duration{endpoint:delay-2s}': ['p(95)>1200'],
  },
};

function delayedRequest(delay, sloMilliseconds) {
  const response = http.get(`${baseUrl}/delay/${delay}`, {
    timeout: '10s',
    tags: { endpoint: `delay-${delay}s` },
  });
  check(response, {
    [`delayed request exceeds ${sloMilliseconds} ms and returns 200`]: (result) =>
      result.status === 200 && result.timings.duration > sloMilliseconds,
  });
}

export function breach300ms() {
  delayedRequest(0.5, 300);
}

export function breach1200ms() {
  delayedRequest(2, 1200);
}