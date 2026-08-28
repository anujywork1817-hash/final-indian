# 01 — Architecture Audit

Source of truth: `ARCHITECTURE_CONTEXT.md` (code-verified) + direct inspection. This is a read-only audit — no code was changed to produce it.

## System shape

This is a **distributed monolith**, not microservices: five Go binaries (`api-gateway`, `auth-service`, `tent-service`, `booking-service`, `payment-service`), all in **one Go module**, all connecting **directly to the same PostgreSQL database** with no per-service data ownership. Helper code (e.g. FCM sending) is copy-pasted across services rather than shared. A sixth directory, `cmd/`, is a legacy pre-split monolith that still compiles but is not deployed.

```
Flutter app ──┐
              ├──> api-gateway (8080) ──> auth-service (8081)
React admin ──┘         │                 tent-service (8082)
                         │                 booking-service (8083)
                         │                 payment-service (8084)
                         │                        │
                         └── (direct reach, no gw)─┘
                                        │
                                  PostgreSQL (single instance)
```

## Entry points

- `api-gateway/main.go` — sole intended public entrypoint. Gin. Parses JWT, sets `X-User-Phone`, proxies via `proxy(target)` (reads full body, rebuilds request, 30s client timeout).
- Each downstream service also has its own `main.go` and listens on its own port directly — **and nothing stops a client reaching those ports directly**, bypassing the gateway and its JWT check entirely.

## Trust model (critical)

Downstream services do **not** validate JWTs themselves. They trust the `X-User-Phone` header set by the gateway, unconditionally. Since the services are independently network-reachable, this is a bypassable trust boundary, not a real one, unless network policy (security groups / K8s NetworkPolicy) restricts direct access to gateway-only. No such restriction is documented or enforced in code.

## Statefulness

- **HTTP layer**: stateless — auth is JWT-in-header, no server-side session store, no sticky-session dependency. Good foundation for horizontal scaling.
- **Cron / background work**: `booking-service` runs `startReminderScheduler()` as an **in-process goroutine loop** with no leader election or distributed lock. Running N replicas of `booking-service` behind a load balancer means the reminder/cleanup job runs **N times daily**, sending N duplicate push notifications per user and racing on delete/cleanup. This is a concrete horizontal-scaling blocker as-is.
- **Refund retry worker**: same pattern — in-process goroutine sweep every `REFUND_RETRY_INTERVAL_MINUTES`. Idempotency is protected at the DB layer (conditional claim UPDATE + unique constraints), so concurrent replicas won't double-refund, but they will still do duplicate wasted work and duplicate Razorpay API calls competing for the same rows.
- **No Redis or any shared cache/session store currently exists anywhere in the stack.**

## Database architecture

- Single PostgreSQL instance, no read replicas, no connection-pool tuning documented in the architecture doc (needs code-level confirmation — see `05_DATABASE_AUDIT.md`).
- **Schema drift**: `admins`, `reviews` tables and several `users` columns (`id_type`, `id_number`, `kyc_status`, `blocked`, `verified_at`) are used by application code but declared in **no SQL file** in the repo. A database built from source (`schema.sql` + `migrations/001_create_refunds.sql`) will not have these and the app will fail on those code paths. This is a **rebuild/DR blocker**, not just a documentation gap.
- No migration runner. Migrations are applied by hand via `psql`. This is incompatible with automated CI/CD deploys and with any multi-environment (staging/prod) parity guarantee.

## Client applications

- Flutter app and React admin point at **two different backend URLs**, both hardcoded in source with no build-time environment injection. This means promoting a build between environments requires a source edit + rebuild, not a config change — incompatible with standard CI/CD promotion flows.
- Flutter: `flutter_riverpod`/`go_router` are dependencies but unused — no impact on backend scalability, noted for completeness only.

## Deployment model today

- Docker images pushed to a specific AWS ECR account/region, `docker-compose.yml` used for local dev via a `local` profile with a Postgres container that self-initializes from `schema.sql`.
- Stated production target: AWS Elastic Beanstalk + RDS + CloudFront, with a parallel Render.com deployment also live. Two live production targets with (per the doc) inconsistent env-var naming between them (`GATEWAY_PORT` vs `API_GATEWAY_PORT`) is itself an operational risk — a documented config value silently does nothing on one of the two.

## Immediate architectural blockers for the stated goal (10k concurrent, horizontally scaled, load-balanced)

1. Admin API is completely unauthenticated at the gateway (see `02_SECURITY_AUDIT.md`) — this must be fixed before any scale-up increases the blast radius.
2. Downstream services are directly reachable and trust an unauthenticated header — same category of issue, network-level fix required (private subnet / service mesh / mutual auth) alongside app-level fix.
3. In-process cron/refund-worker will duplicate work N× under N replicas — needs either a distributed lock (Redis `SETNX`/advisory lock) or extraction to a single dedicated worker process that is *not* horizontally scaled, or a real job queue.
4. No Redis / shared cache tier exists — required for distributed rate limiting (§13 of the master prompt) and recommended for read caching.
5. Schema drift means "spin up a fresh instance from source" does not currently work — this defeats horizontal autoscaling of *new* database instances/read replicas built from source, and defeats disaster recovery restore-from-scratch testing.
6. No migration runner — blocks safe, repeatable, automated schema rollout as part of CI/CD.
7. Connection-pool sizing not yet confirmed from code (pending) — must be verified before deciding real instance-count × pool-size ceilings against RDS `max_connections`.

## What's already right (don't rebuild these)

- JWT-based stateless auth at the HTTP layer (mechanism is sound; algorithm/secret handling has real bugs — see security audit).
- Booking creation already uses `SELECT ... FOR UPDATE` + a transaction to prevent overbooking — correct pattern, keep it.
- Refund idempotency is enforced with DB constraints (`uq_refunds_booking_ref`, conditional claim UPDATE) — correct pattern, keep it, just needs the distributed-scheduling fix above so retries aren't wastefully duplicated.
- Money is stored as `BIGINT` paise in `refunds`, not float — correct, keep it.
