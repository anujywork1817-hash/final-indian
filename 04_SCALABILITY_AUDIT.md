# 04 — Scalability Audit

## Horizontal scaling readiness by component

| Component | Stateless today? | Blocker if scaled to N replicas now | Required fix |
|---|---|---|---|
| `api-gateway` | Yes | None identified — JWT parsing is per-request, no local state | Safe to scale as-is once behind a real LB |
| `auth-service` | Yes (JWT issuance is stateless) | SEC-1 (OTP bypass) makes scaling it just serve more attackers faster | Fix SEC-1 first |
| `tent-service` | Yes | None identified at the stateless-HTTP level; read load will hit shared DB harder per replica with no cache | Add Redis read-through cache for `GET /tents` |
| `booking-service` | **No** — runs the reminder cron and refund-retry sweep in-process | N replicas = N× duplicate cron execution and N× duplicate FCM sends, N× competing sweep queries | Extract scheduled work to a single dedicated worker (not autoscaled), or add a distributed lock (Postgres advisory lock or Redis `SET NX`) so only one replica's sweep executes per interval |
| `payment-service` | Yes | None identified beyond shared-DB pool pressure | Standard scaling once pool sizing is fixed |
| PostgreSQL | N/A (the shared state) | Single instance, no read replica, unconfirmed connection-pool ceiling | Confirm/set pool limits per instance now; add read replica once read traffic is characterized |
| Redis | Does not exist | Required for: distributed rate limiting, distributed lock for cron, recommended for read caching | Introduce in Phase 4 |

## No sticky sessions, no local session state — confirmed good

Authentication is JWT-in-header end to end; no server-side session map was found anywhere in the architecture. This is the correct foundation and should be preserved exactly as-is — do not introduce server-side sessions to "fix" anything, that would be a regression against the master prompt's §7 requirement.

## Deployment-target portability

Current deployment already spans two different platforms (AWS Elastic Beanstalk+RDS+CloudFront, and Render.com) from the same codebase, which is a good sign for portability — but the two platforms are configured with **inconsistent environment variable names** (`GATEWAY_PORT` vs `API_GATEWAY_PORT`), meaning the "portability" is accidental/fragile rather than deliberately engineered. Recommendation: standardize on one canonical env-var contract, document it once in `.env.example`, and make every platform-specific config (EB `.ebextensions`, Render config, future K8s manifests, future Docker Compose) map onto that single contract rather than each inventing its own names.

## Load balancing readiness

- **No graceful shutdown — CONFIRMED ABSENT.** Every service (`api-gateway`, `auth-service`, `tent-service`, `booking-service`, `payment-service`, `cmd/`) calls `gin.Default()` → `r.Run(":"+port)` with zero custom `http.Server{}`, zero `signal.Notify`, zero `.Shutdown(ctx)` calls anywhere in the module. Combined with no `ReadTimeout`/`WriteTimeout`/`IdleTimeout`, this means: (a) a `SIGTERM` from an orchestrator (K8s pod eviction, ECS task stop, EB deploy rotation) kills in-flight requests immediately rather than draining them — a direct violation of master-prompt §6 and §29; (b) no protection against slow-client resource exhaustion. **This is a required Phase 4 fix, blocking on it before any rolling-deploy or autoscale-in policy is safe to enable.**
- Health endpoint exists (`GET /health` per EB config `HealthCheckPath: /health`) but its *implementation* (does it check DB connectivity, making it unsuitable as a liveness probe per master-prompt §6?) has not yet been read line-by-line — pending.
- No evidence of any application-level load balancer configuration in-repo (no nginx/ALB/Traefik config found in source) — EB provisions its own ALB per the deployment model, which is standard and fine, but is infrastructure-level, not represented in or portable via source control. This matters for the master-prompt §4 deployment-independence goal: moving off EB currently means re-deriving the load-balancer config from scratch rather than porting a manifest.

## Addendum: confirmed by direct source read (Phase 1 code audit)

- **Cron duplication risk — confirmed real, not hypothetical.** `booking-service/reminders.go` (daily reminder/cleanup scheduler) and `booking-service/refunds.go` (refund retry sweep loop) are both in-process goroutines with no leader election or distributed lock found anywhere in the module. N replicas of `booking-service` = N× duplicate execution, exactly as flagged.
- **Async work is minimal and bounded** — only two `go func()` call sites exist in the entire backend (`payment-service/handler.go:187,203`), both firing a single FCM push after payment verification. No unbounded per-request goroutine spawning was found — this is a non-issue, not a risk.
- **Redis, rate limiting: confirmed absent**, not just undocumented — zero Redis imports anywhere in `go.mod`/`go.sum`/source; zero rate-limiter middleware or library usage found.
- **Logging: plain `log`/`fmt.Print*` throughout, no structured logging, no request-ID/trace-ID propagation** — confirmed across all 21 relevant `.go` files. This matters for scalability specifically because correlating a slow/failed request across the gateway→service hop during an incident (e.g. while diagnosing a load-test failure) is currently not possible from logs alone.
- **Docker containers run as root, no in-image HEALTHCHECK** — multi-stage builds are otherwise correctly structured (`golang:1.25-alpine` builder → `alpine:latest` runtime, binary-only). See `02_SECURITY_AUDIT.md` SEC-11 for the fix.
- **No CI/CD pipeline exists at all** — confirmed, no `.github/workflows` or equivalent in the project (only third-party `node_modules` workflow files were found, not project CI).

## Autoscaling readiness

Cannot be assessed as "ready" while:
1. The in-process cron duplicates work under replication (must fix first — scaling out today actively makes correctness worse, not just cost-inefficient).
2. Connection-pool ceilings are unconfirmed (scaling out today could exhaust the DB with no capacity planning in place).

## Single points of failure (preliminary — full table in Phase 1 continuation once infra specifics are confirmed)

| Component | SPOF today? | Risk | Recommended fix |
|---|---|---|---|
| PostgreSQL | Yes | High — no replica, one instance | RDS Multi-AZ (already implied by "RDS" in prod) + read replica once read/write split is implemented in app code |
| Reminder/refund cron | Yes (by design flaw, not by infra) | Medium — if the one replica handling it goes down, reminders/refund retries silently stop with no alerting observed | Dedicated worker + monitoring/alerting on last-run timestamp |
| Redis | N/A — doesn't exist yet | N/A | When introduced, must be deployed with failover (e.g. managed Redis with replica) since rate-limiting and cache will depend on it |
| Object storage | Not yet confirmed whether any file storage is used at all | Unknown | Confirm in Phase 1 continuation |
