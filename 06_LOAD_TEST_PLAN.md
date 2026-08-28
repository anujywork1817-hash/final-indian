# 06 — Load Test Plan

## Status: PLAN ONLY — nothing has been executed yet

No k6/Locust/Artillery scripts exist anywhere in the repo today (confirmed by direct search of `kumbh_backend/`). This document defines the plan; `07_IMPLEMENTATION_ROADMAP.md` schedules when it gets built and run. Per master-prompt §46, no numbers are claimed here — this is scope and methodology only.

## Why this can't run yet, as-is

Running any load test against the current codebase, even at low concurrency, would primarily measure two things that are already known to fail, not the application's real ceiling:
1. **Unbounded DB connection pool** (`05_DATABASE_AUDIT.md`) — very likely exhausts a small RDS instance's `max_connections` at a few hundred concurrent users, long before 10,000. Testing past this point produces meaningless numbers until it's fixed.
2. **Open security holes** (`02_SECURITY_AUDIT.md`) — SEC-1 (OTP-bypass) and the SEC-2 admin-route status must be resolved before it's meaningful to call any subsequent load-test result "production readiness" evidence, per master-prompt §44's instruction not to let performance and security trade off against each other.

**Required before Scenario A can run**: pool limits set (Phase 4), SEC-1/SEC-3 fixed (Phase 3), graceful shutdown added (Phase 4) so instance recycling during a long soak test doesn't itself cause false failures.

## Test suite structure (to build in Phase 8)

```
k6/
├── config.js          # shared config: base URL, thresholds, stages
├── auth.js             # Scenario A
├── dashboard.js        # Scenario B (tent browse/detail — the app's actual "dashboard")
├── read-heavy.js        # Scenario C
├── mixed-workload.js    # Scenario D
├── stress.js            # Scenario E
└── soak.js              # Scenario F
```

## Scenario A — Authentication
Simulates: `send-otp` → `verify-otp` → JWT stored → one authenticated profile fetch. Target 10,000 VUs ramped, not instant. **Blocked today by SEC-1** — testing the current OTP-in-response flow would be testing an exploit, not a login. Must run against the Phase-3-hardened auth flow (real OTP delivery mocked via a test-mode SMS stub, not the production bypass).

## Scenario B — Dashboard (tent browse)
`GET /tents` (with and without `?class=` filter) + `GET /tents/:id` detail + reviews fetch, at 10,000 VUs. This is confirmed (Phase 1 audit) to be a single well-formed JOIN query today — the interesting question this test answers is not "is the query correct" (it is) but "what's the connection-pool and cache-miss behavior at scale," which is exactly why Redis caching (Phase 4) should land *before* this scenario is trusted as a ceiling number.

## Scenario C — Read-heavy workload
Mix of tent browse, search/filter, booking list (`GET /bookings`), e-ticket/QR data fetch — representative of the majority of real traffic in this domain (far more people browse and check bookings than create new ones).

## Scenario D — Mixed workload
60% reads (browse, booking list) / 20% search / 10% writes (booking creation, review submission) / 5% auth / 5% other (coupon validate, profile update). This is the closest proxy to real production traffic shape and the primary number to report for "does this handle 10k concurrent users."

**Special sub-scenario within D, required given the confirmed architecture**: a *concentrated* write test — many concurrent booking attempts against **one single tent** with limited `total_units`, to specifically exercise the `SELECT ... FOR UPDATE` row-lock path flagged in `03_PERFORMANCE_AUDIT.md`. Aggregate mixed-workload numbers will hide this; it needs its own targeted run (e.g. 500 VUs all booking the same tent/date-range simultaneously) to characterize lock-wait P99 and confirm no overbooking occurs under contention — this is a correctness test disguised as a load test, and is arguably the single most business-critical scenario in this entire plan given the app's real-world peak-Kumbh-surge use case.

## Scenario E — Stress (find the breaking point)
Progressive ramp: 1,000 → 2,500 → 5,000 → 7,500 → 10,000 → 12,500 → 15,000 VUs, each step held long enough to reach steady state before advancing. Record the exact step at which any of: error rate, P95/P99 latency, DB connection saturation, or memory growth crosses the thresholds defined below. Do not skip straight to 10,000 (master-prompt §33/§45 Phase 9 explicitly requires the staged ramp).

## Scenario F — Soak
Sustained moderate load (a level well below the Scenario E breaking point, e.g. 50–70% of the confirmed safe ceiling) held for an extended duration (recommend minimum 2 hours, ideally 8–24h for real leak detection). Watch specifically for: memory growth in each of the five services, DB connection count drift over time (should be flat, not climbing — a climb indicates a connection leak given the current unbounded-pool state), and the reminder-cron/refund-sweep duplication issue manifesting as duplicate push notifications if more than one `booking-service` replica is in the soak environment.

## Acceptance thresholds (illustrative structure — to be finalized with real numbers after Phase 2 baseline, per master-prompt §33/§43: measure first, then set achievable targets, do not invent numbers up front)

| Metric | Threshold (placeholder — set from Phase 2 baseline) |
|---|---|
| HTTP error rate | < 0.1% sustained (excluding intentional negative-test requests) |
| P95 latency, read endpoints | TBD from baseline |
| P95 latency, write endpoints (booking creation) | TBD from baseline |
| P99 latency | TBD from baseline |
| DB connection pool utilization | < 80% of configured max sustained |
| 5xx errors during steady-state | 0 |
| Memory growth over soak duration | Flat within noise, no monotonic climb |

## Environment documentation requirement (master-prompt §34)

Before any numbers from this suite are reported as meaningful, the report accompanying them must state explicitly: load-generator resources/location, application instance count/size, database instance class and confirmed `max_connections`, Redis instance (once introduced), network topology/region, and whether autoscaling was enabled during the run. **A 10,000-VU test against a local Docker Compose Postgres container on a developer laptop is a load-generator/toy-environment test, not evidence the production topology handles 10,000 users** — this distinction must be stated plainly in whatever environment the test is eventually run in, not glossed over.

## Failure-scenario testing (Phase 10, master-prompt §35)
To be run once the above baseline scenarios pass: kill one `booking-service` instance mid-soak and confirm the load balancer routes around it with no client-visible errors beyond in-flight requests on that instance (which requires the graceful-shutdown fix to be clean rather than abrupt); simulate Postgres connection failure and confirm the app returns clean 5xx/retry-able errors rather than hanging or crashing; simulate Razorpay/FCM unavailability and confirm the confirmed 10s/20s/30s timeouts actually bound the failure rather than cascading.
