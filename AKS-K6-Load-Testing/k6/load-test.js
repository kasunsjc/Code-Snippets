import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';

const normalLatency = new Trend('normal_latency', true);
const expectedErrorResponses = new Counter('expected_error_responses');
const baseUrl = (__ENV.BASE_URL || 'http://target-app.k6-demo.svc.cluster.local').replace(/\/$/, '');
const testType = __ENV.TEST_TYPE || 'load';
const normalP95 = Number(__ENV.NORMAL_P95_MS || 200);

const profiles = {
  smoke: { executor: 'constant-vus', vus: 1, duration: '10s' },
  load: {
    executor: 'ramping-vus',
    startVUs: 0,
    stages: [
      { duration: '30s', target: 5 },
      { duration: '1m', target: 20 },
      { duration: '2m', target: 20 },
      { duration: '30s', target: 0 },
    ],
  },
  spike: {
    executor: 'ramping-vus',
    startVUs: 1,
    stages: [
      { duration: '10s', target: 5 },
      { duration: '10s', target: 50 },
      { duration: '30s', target: 50 },
      { duration: '10s', target: 0 },
    ],
  },
  failure: { executor: 'constant-vus', vus: 2, duration: '20s' },
};

if (!Object.prototype.hasOwnProperty.call(profiles, testType)) {
  throw new Error(`Unknown TEST_TYPE '${testType}'; use smoke, load, spike, or failure.`);
}
if (!Number.isFinite(normalP95) || normalP95 <= 0) {
  throw new Error('NORMAL_P95_MS must be a positive number.');
}

const thresholds = {
  checks: ['rate>0.99'],
  'http_req_failed{kind:normal}': ['rate<0.01'],
  normal_latency: [`p(95)<${normalP95}`],
};

if (testType === 'failure') {
  thresholds['http_req_failed{kind:expected_error}'] = ['rate<0.01'];
  thresholds['http_req_failed{kind:delay}'] = ['rate<0.01'];
  thresholds['http_req_duration{kind:delay}'] = ['p(95)<3000'];
  thresholds['http_req_failed{kind:timeout}'] = ['rate>0.99'];
  thresholds.expected_error_responses = ['count>0'];
}

export const options = {
  scenarios: { [testType]: { ...profiles[testType], gracefulStop: '10s' } },
  thresholds,
};

function normalTraffic() {
  const getResponse = http.get(`${baseUrl}/get?scenario=mixed`, {
    tags: { kind: 'normal', endpoint: 'get' },
    timeout: '5s',
  });
  normalLatency.add(getResponse.timings.duration);
  check(getResponse, {
    'GET returns the requested URL': (response) => response.status === 200 && response.json('url').includes('/get?scenario=mixed'),
  });

  const postResponse = http.post(`${baseUrl}/post`, JSON.stringify({ scenario: 'mixed' }), {
    headers: { 'Content-Type': 'application/json' },
    tags: { kind: 'normal', endpoint: 'post' },
    timeout: '5s',
  });
  normalLatency.add(postResponse.timings.duration);
  check(postResponse, {
    'POST echoes the JSON payload': (response) => response.status === 200 && response.json('json.scenario') === 'mixed',
  });

  for (const size of [1024, 65536]) {
    const payloadResponse = http.get(`${baseUrl}/bytes/${size}`, {
      responseType: 'binary',
      tags: { kind: 'normal', endpoint: `bytes-${size}` },
      timeout: '5s',
    });
    normalLatency.add(payloadResponse.timings.duration);
    check(payloadResponse, {
      [`payload contains ${size} bytes`]: (response) => response.status === 200 && response.body.byteLength === size,
    });
  }

  const authResponse = http.get(`${baseUrl}/basic-auth/demo/secret`, {
    headers: { Authorization: 'Basic ZGVtbzpzZWNyZXQ=' },
    tags: { kind: 'normal', endpoint: 'auth-valid' },
    timeout: '5s',
  });
  normalLatency.add(authResponse.timings.duration);
  check(authResponse, {
    'valid demo credentials authenticate': (response) => response.status === 200 && response.json('authenticated') === true,
  });
}

function failureTraffic() {
  for (const status of [404, 500]) {
    const statusResponse = http.get(`${baseUrl}/status/${status}`, {
      responseCallback: http.expectedStatuses(status),
      tags: { kind: 'expected_error', endpoint: `status-${status}` },
      timeout: '5s',
    });
    expectedErrorResponses.add(statusResponse.status === status ? 1 : 0);
    check(statusResponse, {
      [`expected HTTP ${status} is returned`]: (response) => response.status === status,
    });
  }

  const deniedResponse = http.get(`${baseUrl}/basic-auth/demo/secret`, {
    headers: { Authorization: 'Basic ZGVtbzp3cm9uZw==' },
    responseCallback: http.expectedStatuses(401),
    tags: { kind: 'expected_error', endpoint: 'auth-invalid' },
    timeout: '5s',
  });
  expectedErrorResponses.add(deniedResponse.status === 401 ? 1 : 0);
  check(deniedResponse, {
    'invalid demo credentials return 401': (response) => response.status === 401,
  });

  const delayedResponse = http.get(`${baseUrl}/delay/1`, {
    tags: { kind: 'delay', endpoint: 'delay' },
    timeout: '5s',
  });
  check(delayedResponse, {
    'delayed response succeeds after at least one second': (response) => response.status === 200 && response.timings.duration >= 1000,
  });

  const timeoutResponse = http.get(`${baseUrl}/delay/2`, {
    tags: { kind: 'timeout', endpoint: 'timeout' },
    timeout: '500ms',
  });
  check(timeoutResponse, {
    'slow response hits the deliberate client timeout': (response) => response.status === 0 && response.error_code === 1050,
  });
}

export default function () {
  normalTraffic();
  if (testType === 'failure') {
    failureTraffic();
  }
  sleep(1);
}
