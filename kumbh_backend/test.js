import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const apiDuration = new Trend('api_duration');

// ---- Diagnostics: pin down WHERE the residual failures come from ----
// Per-endpoint failure rate + a breakdown of every non-2xx status and
// transport error (status 0 = connection reset / timeout / DNS). The plain
// summary only gives an aggregate %, which is useless for root-causing.
const failByEndpoint = {
  health: new Rate('fail_health'),
  'tents-list': new Rate('fail_tents_list'),
  'bookings-list': new Rate('fail_bookings_list'),
};
const statusCounts = new Counter('status_codes'); // tagged by code+endpoint

// Base URL for the API
const BASE_URL = 'http://bharat-tent-api-alb.eba-32svn3rz.ap-south-1.elasticbeanstalk.com/api/v1';
// Root of the same host, no /api/v1 — needed for routes like /health that
// the gateway registers outside the versioned API group.
const HOST_ROOT = BASE_URL.replace(/\/api\/v1$/, '');

// ---- Load profile: ramps from 0 -> 1000 VUs and back down ----
export const options = {
  stages: [
    { duration: '1m', target: 100 },   // warm up
    { duration: '2m', target: 500 },   // ramp to 500 users
    { duration: '3m', target: 500 },   // hold at 500 users
    { duration: '2m', target: 1000 },  // ramp to 1000 users
    { duration: '3m', target: 1000 },  // hold at 1000 users
    { duration: '2m', target: 0 },     // ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<2000'], // 95% of requests should be below 2s
    http_req_failed: ['rate<0.05'],    // error rate should be below 5%
    errors: ['rate<0.05'],
  },
};

// EDIT THIS: replace with the actual endpoints you want to test.
// Add / remove entries as needed. GET-only endpoints listed as examples.
//
// The gateway registers /health at the root, NOT under /api/v1 (see
// api-gateway/main.go) — every other route here does live under /api/v1.
// health's `path` is therefore a full URL, not a suffix appended to
// BASE_URL like the rest; see how `url` is built below. Getting this
// wrong makes every "health" pick 404, which silently inflated every
// load-test failure rate run against this script by ~33% (exactly its
// 1-in-3 share of the random endpoint pick) even though the backend was
// never actually failing.
const ENDPOINTS = [
  { name: 'health', path: '/health', method: 'GET', fullUrl: true },
  { name: 'tents-list', path: '/tents', method: 'GET' },
  { name: 'bookings-list', path: '/bookings', method: 'GET' },
];

// If any endpoint needs auth, set a token here (or pull from env: __ENV.API_TOKEN).
// This default is a real JWT for a throwaway test user (phone 9999999999,
// logged in via the dev OTP flow, which echoes the OTP back in send-otp's
// response — no real SMS gateway is configured). Safe to reuse for load
// testing; it carries no real customer data. Long-lived, but if it ever
// expires, log in again the same way and swap in the new token.
const AUTH_TOKEN = __ENV.API_TOKEN || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3OTA4MjYzMzMsInBob25lIjoiOTk5OTk5OTk5OSIsInJvbGUiOiJ0b3VyaXN0In0.2cpQJKxG6edXOG-p1LY89Naa07wsZB__NbzYGwNGY8c';

function headers() {
  const h = { 'Content-Type': 'application/json' };
  if (AUTH_TOKEN) {
    h['Authorization'] = `Bearer ${AUTH_TOKEN}`;
  }
  return h;
}

export default function () {
  // Root cause of the residual ~2% failure rate on every run so far:
  // `sleep()` below only runs at the END of an iteration, so the very
  // FIRST request a newly-spawned VU makes fires the instant it's
  // created, with zero jitter. Every ramp stage that adds VUs quickly
  // (e.g. 500 VUs added over a couple minutes) spawns them in a tight
  // burst, and all of them try to open a TCP connection in the same
  // instant — a "thundering herd" that the Windows client's own
  // connection-establishment throughput can't always keep up with,
  // producing `connectex`/status=0 failures that have nothing to do
  // with the backend (confirmed: CPU across all 4 instances stayed
  // under 6% during runs where this happened, and 100% of the
  // failures cluster in a 1-5 second window right at a ramp stage,
  // never during a steady-VU-count hold). This jitter spreads that
  // first connection out over up to 2s so a burst of new VUs doesn't
  // all dial at once.
  sleep(Math.random() * 2);

  // Pick a random endpoint from the list to simulate mixed traffic
  const endpoint = ENDPOINTS[Math.floor(Math.random() * ENDPOINTS.length)];
  const url = endpoint.fullUrl
    ? `${HOST_ROOT}${endpoint.path}`
    : `${BASE_URL}${endpoint.path}`;

  let res;
  const params = { headers: headers(), tags: { name: endpoint.name } };

  if (endpoint.method === 'GET') {
    res = http.get(url, params);
  } else if (endpoint.method === 'POST') {
    res = http.post(url, JSON.stringify(endpoint.body || {}), params);
  }

  apiDuration.add(res.timings.duration);

  const is2xx = res.status >= 200 && res.status < 300;
  const ok = check(res, {
    'status is 200-299': () => is2xx,
    'response time < 2000ms': (r) => r.timings.duration < 2000,
  });

  errorRate.add(!ok);

  // Diagnostics
  if (failByEndpoint[endpoint.name]) failByEndpoint[endpoint.name].add(!is2xx);
  statusCounts.add(1, { code: String(res.status), ep: endpoint.name });
  if (!is2xx) {
    console.error(
      `FAIL ${endpoint.name} status=${res.status} err="${res.error}" ` +
      `err_code=${res.error_code} dur=${res.timings.duration.toFixed(0)}ms ` +
      `body=${String(res.body).slice(0, 120)}`,
    );
  }

  // Simulate realistic user think-time between requests
  sleep(Math.random() * 2 + 1); // 1-3 seconds
}

// ---- Optional: summary handler for a cleaner console report ----
export function handleSummary(data) {
  return {
    stdout: textSummary(data),
  };
}

function textSummary(data) {
  const m = data.metrics;
  const get = (k, f) => (m[k] ? m[k].values[f] : 'N/A');
  return `
================= LOAD TEST SUMMARY =================
Total requests   : ${get('http_reqs', 'count')}
Failed requests  : ${(get('http_req_failed', 'rate') * 100).toFixed(2)}%
Avg duration     : ${get('http_req_duration', 'avg').toFixed(2)} ms
p95 duration     : ${get('http_req_duration', 'p(95)').toFixed(2)} ms
Max duration     : ${get('http_req_duration', 'max').toFixed(2)} ms
Max VUs reached  : ${get('vus_max', 'value')}
--- Failure rate by endpoint ---
health           : ${(get('fail_health', 'rate') * 100).toFixed(2)}%
tents-list       : ${(get('fail_tents_list', 'rate') * 100).toFixed(2)}%
bookings-list    : ${(get('fail_bookings_list', 'rate') * 100).toFixed(2)}%
(Per-request failure reasons — status, err, err_code, body — are logged
 to stderr as "FAIL ..." lines during the run. Grep those to see exactly
 which status codes make up the failure %.)
=======================================================
`;
}