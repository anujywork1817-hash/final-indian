# 05 — Database Audit

## Status: connection pooling and migration state now confirmed by direct source read; index/EXPLAIN work remains for Phase 5 (requires a running DB)

This audit is grounded in the verified data model and flows from `ARCHITECTURE_CONTEXT.md`, plus direct source confirmation from a Phase 1 code audit.

## Schema, as declared in source

- `users`, `otp_store`, `tents`, `coupons`, `bookings`, `payments` — from `schema.sql`.
- `refunds` — from `migrations/001_create_refunds.sql`, the one properly-migrated table in the system, with well-designed constraints (`uq_refunds_booking_ref`, `uq_refunds_razorpay_refund_id` partial unique, `uq_refunds_idempotency_key`, `ck_refunds_status`, `ck_refunds_amount_bounds`, `ck_refunds_succeeded_has_gateway_id`). This is the template other tables' migrations should follow.

## Schema drift — CORRECTED: more migrations exist than the architecture doc showed, but the runner gap is worse than stated

Direct listing of `kumbh_backend/migrations/` found **13 numbered files**, not 1: `001_create_refunds.sql` through `013_refund_approval_reason.sql`, covering refund approval workflow, cancellation policy, a finance/ledger subsystem (phase 1), payment tracking, multi-currency expenses, gateway reconciliation, invoicing, ledger/bank reports, RBAC/audit tables, vendor payables. This means the `admins`/RBAC/`reviews` schema-drift concern from `ARCHITECTURE_CONTEXT.md` may already be **partially or fully resolved** by migrations `002` and `011` (`002_missing_tables.sql`, `011_rbac_audit.sql`) — needs direct diffing against the doc's claim, not assumed either way.

**The more serious confirmed finding**: `docker-compose.yml`'s local Postgres init (`docker-entrypoint-initdb.d`) only wires `schema.sql` + migrations **001 through 004**. Migrations **005–013 are not applied automatically even in local dev**, and per `DEPLOY.md`/`README.md` must be applied to production by hand via `psql`. This means:
- The local dev/Compose environment and production are **already schema-divergent today** unless someone has manually kept them in sync — the exact failure mode master-prompt §27–28 warns about, now confirmed rather than hypothesized.
- There is still **no migration-runner tool** (`golang-migrate`/`goose`/`flyway`) anywhere in the stack.
- **This must be fixed before Phase 5 optimization work begins** — you cannot safely add indexes or tune queries against a schema whose actual live state isn't guaranteed to match source.

**Action**: (1) extend `docker-compose.yml`'s init to run all 13 migrations, not just 4; (2) `pg_dump --schema-only` the real production DB and diff it against `schema.sql` + all 13 migrations applied in order, to find any remaining undeclared drift; (3) adopt a migration runner so this can never silently diverge again.

## Locking pattern — correct, but needs load-test-driven tuning

Booking creation's `SELECT ... FOR UPDATE` on the tent row is the right primitive for preventing overbooking. The open question, to be answered by measurement (not guessed): under concurrent load against **one popular tent**, what is the lock-wait distribution? If P99 lock-wait time grows unacceptably at realistic peak concurrency (e.g. everyone trying to book the same limited-availability tent during a surge-pricing window — which is this app's actual worst-case real-world traffic pattern), the fix is likely to shrink the transaction's critical section (move the coupon/tax calculation outside the lock, lock only the minimal capacity-check window) rather than removing the lock, since removing it reintroduces the overbooking bug it exists to prevent.

## Refund flow — correct pattern already in place

Money as `BIGINT` paise (never float), the Razorpay refund call fired in a goroutine strictly after the DB transaction commits (so a slow external gateway never holds a row lock), and layered double-execution prevention (unique constraint + conditional claim `UPDATE ... WHERE status IN ('pending','failed')`) are all textbook-correct. Do not rewrite this logic — the only fix needed here is scheduling-level (single-worker execution of the sweep, per the scalability audit), not query-level.

## Connection pooling — CONFIRMED UNCONFIGURED (critical scalability blocker)

Direct source read confirms: **zero** calls to `SetMaxOpenConns`, `SetMaxIdleConns`, or `SetConnMaxLifetime` exist anywhere in the module. Every one of the five services calls `sql.Open("postgres", dbURL)` and uses Go's `database/sql` defaults — **unlimited open connections, no idle timeout**. Concretely:
- A single `booking-service` replica under load can open as many connections as concurrent in-flight requests demand, with no ceiling.
- Master-prompt §11's formula (`instances × per-instance-max-conns ≤ DB max_connections`) is currently `instances × unbounded ≤ small RDS default` — i.e. the formula is already violated by construction, with just one replica of each of the five services running.
- This is very likely the **first thing that breaks** under any real concurrent-user ramp, before CPU or memory becomes the bottleneck, and it will present as Postgres `FATAL: too many connections` or connection-acquisition timeouts — worth specifically watching for in the Phase 2 baseline run even at modest concurrency (a few hundred users), not just at 10k.
- **This is now the single highest-priority Phase 4 fix**, ahead of Redis, ahead of caching — a system that falls over on connection exhaustion at 500 users can't usefully be load-tested for anything else until this is set.

**Fix**: set explicit, documented pool limits in every service at startup, sized per master-prompt §11's formula against the actual target RDS instance class's `max_connections`, e.g. (illustrative, not prescriptive until the RDS instance class is confirmed): `SetMaxOpenConns(20)`, `SetMaxIdleConns(5)`, `SetConnMaxLifetime(5 * time.Minute)` per service instance, then multiply by planned replica count per service and confirm headroom against RDS capacity before any autoscaling policy is enabled.

## Remaining pending items (require a running DB instance, not just source read)
- Actual index list per table (are FKs like `bookings.tent_id` indexed? Composite index on `(tent_id, check_in, check_out)` for the overlap-count query — likely missing, likely needed, to be confirmed with `EXPLAIN ANALYZE` rather than added blindly per master-prompt §10's own instruction).
- Whether long-running queries or lock contention have ever been observed/logged in production (no monitoring exists yet, so this may be genuinely unknown until observability is added in Phase 4/19).
- Full diff of migrations 002/011 against the "undeclared schema" list in `ARCHITECTURE_CONTEXT.md` to determine current true drift state.

## Resolved by this pass (previously listed as unconfirmed)
- ✅ N+1 query risk — confirmed clear (see `03_PERFORMANCE_AUDIT.md`).
- ✅ Connection pool configuration — confirmed absent (see above).
- ✅ Migration file count and local/prod sync gap — confirmed and corrected above.
