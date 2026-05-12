// Continuous load against the nginx demo, so Beyla / Alloy always has
// something to instrument. ~10 req/s steady, with a mix of routes and
// occasional 5xx for error-rate panels to look real.

import http from "k6/http";
import { sleep, check } from "k6";

export const options = {
  vus: 5,
  duration: "9999h",            // run until the container is killed
  thresholds: { http_req_failed: ["rate<0.1"] },
};

const routes = [
  { path: "/",                 weight: 60 },
  { path: "/api/users/1",      weight: 20 },
  { path: "/api/products",     weight: 15 },
  { path: "/api/orders/42",    weight: 4 },
  { path: "/api/will-500",     weight: 1 }, // nginx returns 500 for this
];

function pick() {
  const total = routes.reduce((s, r) => s + r.weight, 0);
  let n = Math.random() * total;
  for (const r of routes) { if ((n -= r.weight) <= 0) return r.path; }
  return "/";
}

export default function () {
  const r = http.get(`http://nginx:80${pick()}`);
  check(r, { "got response": (resp) => resp.status > 0 });
  sleep(0.5);
}
