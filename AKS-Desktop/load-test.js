import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  stages: [
    { duration: "1m", target: 100 },   // ramp up to 100 VUs
    { duration: "2m", target: 200 },   // ramp up to 200 VUs
    { duration: "20m", target: 200 },  // hold at 200 VUs for 20 min
    { duration: "1m", target: 0 },     // ramp down to 0
  ],
  thresholds: {
    http_req_duration: ["p(95)<1000"], // 95% of requests should complete within 1s
    http_req_failed: ["rate<0.05"],    // less than 5% of requests should fail
  },
};

export default function () {
  const res = http.get("http://project-2-app.kasunrajapakse.xyz/");

  check(res, {
    "status is 200": (r) => r.status === 200,
    "response time < 1000ms": (r) => r.timings.duration < 1000,
  });

  sleep(0.3);
}
