import http from 'k6/http';
import { check, sleep } from 'k6';

const targetUrl = __ENV.TARGET_URL || 'https://argocd.kasunrajapakse.xyz/';
const minSleep = Number(__ENV.MIN_SLEEP_SEC || 0.5);
const maxSleep = Number(__ENV.MAX_SLEEP_SEC || 1.5);

function randomSleep(min, max) {
  return Math.random() * (max - min) + min;
}

export const options = {
  scenarios: {
    url_load_test: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 10 },
        { duration: '1m', target: 30 },
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '10s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<1000'],
  },
};

export default function () {
  const response = http.get(targetUrl, {
    tags: { endpoint: targetUrl },
  });

  check(response, {
    'status is 2xx or 3xx': (r) => r.status >= 200 && r.status < 400,
  });

  sleep(randomSleep(minSleep, maxSleep));
}
