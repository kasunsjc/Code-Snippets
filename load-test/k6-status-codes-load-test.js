import http from 'k6/http';
import { check, sleep } from 'k6';

const baseUrl = (__ENV.BASE_URL || 'https://argocd.kasunrajapakse.xyz/').replace(/\/$/, '');
const minSleep = Number(__ENV.MIN_SLEEP_SEC || 0.2);
const maxSleep = Number(__ENV.MAX_SLEEP_SEC || 1.0);

// Use comma-separated numeric HTTP status codes, e.g. "200,400,404,500"
const expectedStatusCodes = (__ENV.EXPECTED_STATUS_CODES || '200,404')
  .split(',')
  .map((code) => Number(code.trim()))
  .filter((code) => Number.isInteger(code));

// Endpoints chosen to commonly return mixed status codes.
const routes = [
  '/',
  '/404',
  '/does-not-exist',
  '/status/400',
  '/status/500',
];

function randomSleep(min, max) {
  return Math.random() * (max - min) + min;
}

function pickRandomRoute() {
  return routes[Math.floor(Math.random() * routes.length)];
}

export const options = {
  scenarios: {
    status_code_mix: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '20s', target: 15 },
        { duration: '300s', target: 30 },
        { duration: '20s', target: 0 },
      ],
      gracefulRampDown: '10s',
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<1500'],
  },
};

export default function () {
  const route = pickRandomRoute();
  const url = `${baseUrl}${route}`;

  const response = http.get(url, {
    tags: { route },
  });

  check(response, {
    'status is in expected list': (r) => expectedStatusCodes.includes(r.status),
  });

  sleep(randomSleep(minSleep, maxSleep));
}
