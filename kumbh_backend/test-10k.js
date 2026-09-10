import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const apiDuration = new Trend('api_duration');

// Base URL for the API — new AWS account backend (bharat-tent-api-prod)
const BASE_URL = 'http://bharat-tent-api-prod.eba-umvanuqr.ap-south-1.elasticbeanstalk.com/api/v1';
// Root of the same host, no /api/v1 — /health lives here, not under
// /api/v1 (see api-gateway/main.go's route registration). Confirmed
// this exact mismatch caused a ~33% false failure rate in earlier runs
// of test.js until fixed — don't reintroduce it here.
const HOST_ROOT = BASE_URL.replace(/\/api\/v1$/, '');

// ---- Load profile: 1,000 -> 10,000 VUs and back down ----
// Ramped in stages, not a single jump, on purpose: k6's own client-side
// connection-establishment throughput (especially on Windows) chokes on
// a "thundering herd" if too many VUs are told to dial at once — this
// was the whole story behind test.js's earlier false-failure chase this
// session. Each stage below adds VUs gradually; combined with the
// per-iteration jitter further down, this keeps the burst manageable.
//
// 10,000 concurrent VUs is a serious load — budget ~26 minutes for the
// full run, and expect this to meaningfully stress both your backend
// AND the machine running k6. If you see failures, check backend
// CPU/target-health first (CloudWatch) before assuming it's the app —
// last time, the backend was fine and the failures were entirely
// client-side/test-script artifacts.
export const options = {
  stages: [
    { duration: '2m', target: 1000 },   // ramp to 1,000
    { duration: '3m', target: 1000 },   // hold
    { duration: '2m', target: 2500 },   // ramp to 2,500
    { duration: '3m', target: 2500 },   // hold
    { duration: '2m', target: 5000 },   // ramp to 5,000
    { duration: '3m', target: 5000 },   // hold
    { duration: '3m', target: 10000 },  // ramp to 10,000
    { duration: '4m', target: 10000 },  // hold
    { duration: '3m', target: 0 },      // ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<2000'], // 95% of requests should be below 2s
    http_req_failed: ['rate<0.05'],    // error rate should be below 5%
    errors: ['rate<0.05'],
  },
};

// EDIT THIS: replace with the actual endpoints you want to test.
const ENDPOINTS = [
  { name: 'health', path: '/health', method: 'GET', fullUrl: true },
  { name: 'tents-list', path: '/tents', method: 'GET' },
  { name: 'bookings-list', path: '/bookings', method: 'GET' },
];

// Auth token for the protected /bookings endpoint. No token is
// hardcoded here — pass one at runtime instead:
//   k6 run --env API_TOKEN=<jwt> test-10k.js
//
// Get one by logging a test user in via the OTP flow (this backend
// echoes the OTP back in send-otp's response — no real SMS gateway is
// configured, so this works without a real phone):
//   curl -X POST http://bharat-tent-api-prod.eba-umvanuqr.ap-south-1.elasticbeanstalk.com/api/v1/auth/send-otp \
//     -H "Content-Type: application/json" -d '{"phone":"9999999999"}'
//   # take the "otp" field from the response, then:
//   curl -X POST http://bharat-tent-api-prod.eba-umvanuqr.ap-south-1.elasticbeanstalk.com/api/v1/auth/verify-otp \
//     -H "Content-Type: application/json" -d '{"phone":"9999999999","otp":"<otp-from-above>"}'
//   # take the "token" field from that response and pass it as API_TOKEN
//
// Without a token, /bookings will 401 on every pick (1/3 of traffic) —
// see test.js's own history this session for exactly how misleading
// that makes the failure-rate number look.
const AUTH_TOKEN = __ENV.API_TOKEN || '';

function headers() {
  const h = { 'Content-Type': 'application/json' };
  if (AUTH_TOKEN) {
    h['Authorization'] = `Bearer ${AUTH_TOKEN}`;
  }
  return h;
}

export default function () {
  // Spreads each VU's first connection out over up to 2s so a fast
  // ramp stage doesn't dial hundreds of new connections in the same
  // instant — see test.js's comment on this same line for the full
  // story (this was the fix for a ~2% residual failure rate that
  // turned out to be a client-side connection-burst artifact, not a
  // backend problem).
  sleep(Math.random() * 2);

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

  const ok = check(res, {
    'status is 200-299': (r) => r.status >= 200 && r.status < 300,
    'response time < 2000ms': (r) => r.timings.duration < 2000,
  });

  errorRate.add(!ok);

  // Simulate realistic user think-time between requests
  sleep(Math.random() * 2 + 1); // 1-3 seconds
}

// ---- Summary handler for a cleaner console report ----
export function handleSummary(data) {
  return {
    stdout: textSummary(data),
  };
}

function textSummary(data) {
  const m = data.metrics;
  const get = (k, f) => (m[k] ? m[k].values[f] : 'N/A');
  return `
================= LOAD TEST SUMMARY (1k-10k VUs) =================
Total requests   : ${get('http_reqs', 'count')}
Failed requests  : ${(get('http_req_failed', 'rate') * 100).toFixed(2)}%
Avg duration     : ${get('http_req_duration', 'avg').toFixed(2)} ms
p95 duration     : ${get('http_req_duration', 'p(95)').toFixed(2)} ms
Max duration     : ${get('http_req_duration', 'max').toFixed(2)} ms
Max VUs reached  : ${get('vus_max', 'value')}
====================================================================
`;
}
