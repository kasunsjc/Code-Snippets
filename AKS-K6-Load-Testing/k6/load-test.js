import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';

const productLatency = new Trend('product_latency');
const productRequests = new Counter('product_requests');
const baseUrl = (__ENV.BASE_URL || 'http://target-app.k6-demo.svc.cluster.local').replace(/\/$/, '');

export const options = {
  stages: [
    { duration: '30s', target: 5 },
    { duration: '1m', target: 20 },
    { duration: '2m', target: 20 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<200'],
    http_req_failed: ['rate<0.01'],
    product_latency: ['p(95)<200'],
  },
};

export default function () {
  const products = http.get(`${baseUrl}/api/products`, {
    tags: { endpoint: 'products' },
  });
  productLatency.add(products.timings.duration, { endpoint: 'products' });
  productRequests.add(1, { endpoint: 'products' });
  check(products, {
    'products endpoint returns 200': (response) => response.status === 200,
    'products response identifies the demo API': (response) => response.body.includes('k6-demo-api'),
  });

  const health = http.get(`${baseUrl}/health`, {
    tags: { endpoint: 'health' },
  });
  check(health, {
    'health endpoint returns 200': (response) => response.status === 200,
  });

  sleep(1);
}
