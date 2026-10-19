import http from 'k6/http';
import { check } from 'k6';

if (!__ENV.BASE_URL) {
  throw new Error('BASE_URL is required, e.g. BASE_URL=https://httpbin.example.com');
}
const baseUrl = __ENV.BASE_URL.replace(/\/$/, '');
const peakRps = Number(__ENV.PEAK_RPS || 300);

if (!Number.isInteger(peakRps) || peakRps < 10) {
  throw new Error('PEAK_RPS must be an integer of at least 10.');
}

export const options = {
  discardResponseBodies: true,
  scenarios: {
    stress: {
      executor: 'ramping-arrival-rate',
      startRate: 10,
      timeUnit: '1s',
      preAllocatedVUs: Math.ceil(peakRps / 4),
      maxVUs: peakRps * 2,
      stages: [
        { duration: '1m', target: Math.round(peakRps * 0.25) },
        { duration: '2m', target: Math.round(peakRps * 0.5) },
        { duration: '2m', target: peakRps },
        { duration: '3m', target: peakRps },
        { duration: '1m', target: 0 },
      ],
      gracefulStop: '30s',
    },
  },
  thresholds: {
    http_req_failed: [{ threshold: 'rate<0.05', abortOnFail: true, delayAbortEval: '1m' }],
    http_req_duration: ['p(95)<500', 'p(99)<1500'],
    checks: ['rate>0.95'],
    // Iterations k6 couldn't start because every VU was still waiting on a slow response.
    dropped_iterations: ['rate<1'],
  },
};

const params = (endpoint) => ({ tags: { endpoint }, timeout: '10s' });

export default function () {
  const pick = Math.random();
  let response;

  if (pick < 0.5) {
    response = http.get(`${baseUrl}/get?scenario=stress`, params('get'));
  } else if (pick < 0.7) {
    response = http.post(`${baseUrl}/post`, JSON.stringify({ scenario: 'stress' }), {
      ...params('post'),
      headers: { 'Content-Type': 'application/json' },
    });
  } else if (pick < 0.9) {
    response = http.get(`${baseUrl}/bytes/1024`, params('bytes-1024'));
  } else {
    response = http.get(`${baseUrl}/bytes/65536`, params('bytes-65536'));
  }

  check(response, { 'status is 200': (r) => r.status === 200 });
}
