# 07 — Implementation Roadmap

Phases as defined by the master prompt (§45), sequenced and scoped against the confirmed findings in files 01–06. **No code has been written yet — this is the plan for Phases 2 onward, gated on explicit sign-off per the master prompt's own "audit only, do not modify code yet" instruction for Phase 1.**

## Phase 1 — Discovery (this document set) — COMPLETE, with two follow-ups
- ✅ `01_ARCHITECTURE_AUDIT.md`, `02_SECURITY_AUDIT.md`, `03_PERFORMANCE_AUDIT.md`, `04_SCALABILITY_AUDIT.md`, `05_DATABASE_AUDIT.md`, `06_LOAD_TEST_PLAN.md` produced from a combination of the existing `ARCHITECTURE_CONTEXT.md` and a direct Phase-1 source-code audit.
- **Open follow-up before Phase 3 fixes are written**: re-verify SEC-2 (admin route auth status) directly against `api-gateway/main.go`'s route table and both `rbac.go` files — the pre-existing architecture doc and the new RBAC files disagree, and this must be resolved with certainty before writing an auth fix (fixing something already fixed would be wasted/risky churn; not fixing something broken is the critical-severity item in this whole report).
- **Open follow-up**: confirm exact Razorpay-signature-verification fallback line and value (architecture doc says `"test_secret"`, not yet independently re-confirmed at the exact source line in this pass).

## Phase 2 — Baseline (blocked until a test environment exists)
Cannot produce real P50/P95/P99/throughput numbers without running the application against a real (even if small) Postgres instance and issuing real HTTP load. **This phase requires infrastructure not currently available in this working session** (see final BLOCKED status). Plan: once available, run Scenario B (dashboard/read) and Scenario D (mixed) at low concurrency (e.g. 100–500 VUs) first, purely to establish `PERFORMANCE_BASELINE.md` numbers, before attempting Phase 9's staged 10k ramp.

## Phase 3 — Security Hardening (code changes begin here — requires explicit go-ahead)
In order of the Critical/High findings in `02_SECURITY_AUDIT.md`:
1. SEC-1 — replace OTP-in-response with a real SMS provider integration (needs a provider account/API key — external dependency, cannot be completed without one).
2. SEC-2 — resolve the doc/code conflict, then close the gap found (protected route group + role check, applied uniformly across all five services).
3. SEC-3 — remove all hardcoded secret fallbacks; fail-fast on missing required secrets in non-local environments.
4. SEC-5 — strip committed credentials from `docker-compose.yml`; rotate the exposed Razorpay test key pair.
5. SEC-4 — network-restrict direct access to internal service ports (infra-level; app-level internal-assertion signing as a defense-in-depth follow-up).
6. SEC-10 — recreate RDS as non-publicly-accessible.
7. SEC-11 — non-root Docker user, in-image HEALTHCHECK.
8. SEC-6, SEC-8, SEC-9 — CORS allowlist, refund-policy env default, rate limiting (the last depends on Redis, so partially overlaps Phase 4).

## Phase 4 — Scalability
1. **Database connection pooling** (highest priority per `05_DATABASE_AUDIT.md` — this is the most likely first-failure point, ahead of everything else in this phase).
2. `http.Server` timeouts + graceful shutdown across all five services and `cmd/` (or remove `cmd/` from the module entirely if it's confirmed genuinely dead — worth a one-line confirmation before Phase 4 rather than carrying it forward indefinitely).
3. Introduce Redis: read-through cache for `GET /tents`, distributed rate limiting, distributed lock for the reminder/refund-sweep cron so N replicas don't duplicate work.
4. Extract the reminder scheduler and refund-retry sweep to run under a single-instance lock (or a dedicated non-autoscaled worker), so `booking-service` itself can be freely horizontally scaled without the duplication bug.
5. Object storage abstraction — **pending confirmation of whether any file upload exists at all** (Phase 1 found none in the Go backend); may be a no-op for this phase if confirmed absent.
6. Structured JSON logging + request-ID propagation across the gateway→service hop.

## Phase 5 — Database
1. Fix migration/schema sync gap (`05_DATABASE_AUDIT.md`): wire all 13 migrations into Compose init, adopt a migration runner, reconcile drift against `ARCHITECTURE_CONTEXT.md`'s undeclared-schema list.
2. `EXPLAIN ANALYZE` the confirmed-hot queries (tent listing, booking overlap-count, admin stats) against a realistically-sized dataset, add indexes only where evidence supports it.
3. Re-examine the booking-creation lock scope under the targeted concurrent-single-tent test from `06_LOAD_TEST_PLAN.md` Scenario D; shrink the transaction's critical section if lock-wait P99 is unacceptable.

## Phase 6 — Containerization
Non-root user + HEALTHCHECK per SEC-11 (can be done alongside Phase 3 since it's a small, isolated change); confirm resource limits are set appropriately once real memory/CPU usage is known from Phase 2/9.

## Phase 7 — Load balancing
Verify identical behavior across N replicas once Phase 4's cron/pool fixes land — this is the first point at which running `docker compose up --scale api-gateway=5` (etc.) becomes a meaningful test rather than one that immediately exhausts the DB pool.

## Phase 8 — k6 suite build
Build the six scripts defined in `06_LOAD_TEST_PLAN.md` against the config/thresholds structure defined there.

## Phase 9 — 10,000-user staged run
Only after Phases 3–8 are complete. Staged 1k→2.5k→5k→7.5k→10k→12.5k→15k, per plan.

## Phase 10 — Failure testing
Per `06_LOAD_TEST_PLAN.md`'s failure-scenario section.

## Phase 11 — Final security re-audit
Re-run whatever security tooling is adopted in Phase 3 (govulncheck, secret scanning) against the hardened code, confirm zero Critical/High findings remain open or are explicitly documented as accepted.

## Phase 12 — Final report
`PRODUCTION_READINESS.md` with the PASS/FAIL table per master-prompt §12/§49, populated only from actually-executed results.

---

## What's needed from you before Phase 2 can start

This phase can proceed with source-level work (Phase 3 security fixes, Phase 4 pool/timeout code, Phase 5 migration consolidation) without additional infrastructure — those are code changes I can make directly and verify locally against the existing `docker-compose.yml` Postgres container. **Phase 2's baseline and Phase 9's 10k-user run specifically require infrastructure this working session does not have** (see the BLOCKED status below) — those need either cloud credentials/an environment to provision, or a decision to run them locally against Compose with the environment caveat from `06_LOAD_TEST_PLAN.md` stated explicitly in the results.
