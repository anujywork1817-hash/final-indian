import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const apiDuration = new Trend('api_duration');

// Base URL for the API
const BASE_URL = 'http://bharat-tent-api-prod2.eba-32svn3rz.ap-south-1.elasticbeanstalk.com/api/v1';

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
const ENDPOINTS = [
  { name: 'health', path: '/health', method: 'GET' },
  { name: 'tents-list', path: '/tents', method: 'GET' },
  { name: 'bookings-list', path: '/bookings', method: 'GET' },
];

// If any endpoint needs auth, set a token here (or pull from env: __ENV.API_TOKEN)
const AUTH_TOKEN = __ENV.API_TOKEN || '';

function headers() {
  const h = { 'Content-Type': 'application/json' };
  if (AUTH_TOKEN) {
    h['Authorization'] = `Bearer ${AUTH_TOKEN}`;
  }
  return h;
}

export default function () {
  // Pick a random endpoint from the list to simulate mixed traffic
  const endpoint = ENDPOINTS[Math.floor(Math.random() * ENDPOINTS.length)];
  const url = `${BASE_URL}${endpoint.path}`;

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
=======================================================
`;
}