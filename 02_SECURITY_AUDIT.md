# 02 — Security Audit

Severity scale: **Critical** (exploitable now, full compromise or auth bypass) / **High** / **Medium** / **Low**.

## CRITICAL

### SEC-1 — OTP is returned in the API response (complete authentication bypass)
`POST /auth/send-otp` returns `{"otp": "123456"}` in the HTTP response body and prints it to stdout. There is no SMS provider integrated. **Anyone who can call this public endpoint for any phone number can read the OTP and log in as that user.** This is not a hardening gap — it is a working, unauthenticated account-takeover path for every account in the system today.
- **Fix**: integrate a real SMS provider (e.g. MSG91, Twilio, AWS SNS) server-side; never return the OTP value or log it; rate-limit `send-otp` per phone number and per IP.

### SEC-2 — Admin route authorization status: NEEDS RE-VERIFICATION (doc conflict)
`ARCHITECTURE_CONTEXT.md` states every `/admin/*` route is registered in the gateway's public group with no auth. However, direct source inspection (Phase 1 code audit) found `auth-service/rbac.go` and `booking-service/rbac.go` — RBAC modules that did not exist when the architecture doc was written, each independently re-verifying JWT signature/algorithm (`jwt.SigningMethodHMAC` check confirmed at `auth-service/rbac.go:50`, `booking-service/rbac.go:40`). **This means the architecture doc is stale on this specific point and SEC-2 must not be treated as confirmed until the actual gateway route-registration groups and these RBAC middlewares' call sites are read directly.**
- **Required next step (Phase 1 continuation, before Phase 3 fixes are written)**: read `api-gateway/main.go`'s full route table and `auth-service/rbac.go` / `booking-service/rbac.go` in full to determine (a) which routes actually require JWT today, (b) whether role (`admin` vs pilgrim) is checked, not just token validity, (c) whether `tent-service` and `payment-service` admin-adjacent routes have equivalent protection or were missed when RBAC was added to only two of five services.
- **If confirmed still open**: fix as originally planned — protected group + explicit role check, applied consistently across all five services, not just the two that currently have `rbac.go`.

### SEC-3 — Hardcoded secret fallbacks (confirmed, worse than initially documented)
Code-level confirmation: the literal `"kumbh2027secret"` JWT-secret fallback is hardcoded **directly in Go source in at least 6 files** — `api-gateway/main.go:282-284`, `auth-service/handler.go:99-101`, `auth-service/rbac.go:46-48`, `booking-service/rbac.go:36-38`, `tent-service/audit.go:26-28`, `cmd/auth.go:62-64,95-97` — not just as a compose-file default. Algorithm confusion is *not* a risk here (HMAC method is explicitly pinned and checked at every one of these sites), but the shared hardcoded fallback is: if `JWT_SECRET` is unset in any of the five independently-deployed services, that service accepts/issues tokens signed with a publicly-known literal. `docker-compose.yml` separately defaults to `kumbh2027supersecretkey` (4 occurrences). Razorpay signature verification falls back to `"test_secret"` per the architecture doc (not yet independently re-confirmed at the exact line).
An unconfigured or misconfigured deploy silently becomes forgeable: anyone can mint a valid JWT for any phone number, and anyone can forge a payment-success signature to mark any booking `confirmed` for free.
- **Fix**: fail startup loudly (`log.Fatal`) if `JWT_SECRET` / `RAZORPAY_KEY_SECRET` are unset or below a minimum entropy/length in any environment that isn't explicitly `local`/`test`. Never silently default security-critical secrets. Apply this check in all five services and `cmd/`, not just the gateway.

### SEC-4 — Internal services trust an unauthenticated header
`booking-service`, `tent-service`, `payment-service`, `auth-service` each accept `X-User-Phone` as the identity of the caller with no verification that the request actually passed through the gateway's JWT check. Since each service is independently network-reachable on its own port, this header can be set directly by anyone who can reach the port, impersonating any user.
- **Fix, in order of effort**: (a) network-level — restrict inbound access to these ports to the gateway's security group / subnet only (no public exposure); (b) app-level — have the gateway sign a short-lived internal assertion (e.g. HMAC over phone+timestamp, or re-verify the same JWT in each service) instead of a bare trusted header.

## HIGH

### SEC-5 — Committed secrets in `docker-compose.yml` (confirmed, with exact values)
Confirmed by direct read: `docker-compose.yml` lines 101-102 and 142-143 hardcode a **real-looking Razorpay test key pair** as env-var defaults — `RAZORPAY_KEY_ID=${RAZORPAY_KEY_ID:-rzp_test_SqpASBdCN2DXd0}` and `RAZORPAY_KEY_SECRET=${RAZORPAY_KEY_SECRET:-0CA01F0L5t325WgA1FcQQKth}` — plus the JWT-secret default at lines 43, 62, 97, 144. `.gitignore` correctly excludes `.env` and Firebase service-account JSON files, but does **not** protect `docker-compose.yml` itself, which is tracked and contains these values in plain text in git history.
- **Fix**: remove all literal credential values from `docker-compose.yml`; require them via `.env` (gitignored) with `.env.example` holding placeholders only, matching the pattern `.env.example` already correctly uses (`xxxxxxxxxxxxxxxxxxxxxxxx` placeholders). **Rotate the exposed Razorpay test key pair** regardless of whether it's "only test" — treat any credential that has been committed to git history as compromised on principle, and confirm via Razorpay dashboard whether this key pair has ever touched a live/production context.

### SEC-6 — CORS wildcard on every service
`Access-Control-Allow-Origin: *` is set on every service, including ones that should only ever be called by the gateway or by the two known frontend origins.
- **Fix**: allowlist the exact known origins (Flutter web build origin if any, admin console origin) at the gateway; downstream services should not need CORS at all if network-isolated per SEC-4.

### SEC-7 — Schema drift breaks reproducibility and hides real access-control columns
`users.blocked`, `users.kyc_status`, and the entire `admins` table live only in a hand-patched production database, not in any versioned SQL. Besides being an operational hazard (§01), this means the *actual* access-control state of the system (who's blocked, who's an admin) is not auditable from source control at all.
- **Fix**: write the missing DDL as a proper migration, apply a migration runner (e.g. `golang-migrate`), and treat schema as code from this point forward.

### SEC-10 — RDS provisioned publicly-accessible
`DEPLOY.md` documents creating the production RDS instance with `--publicly-accessible` (line ~35). Combined with SEC-4 (services trust an unauthenticated header) and no confirmed security-group restriction, this widens the network attack surface for the single most sensitive component in the system — direct database exposure to the internet, gated only by password auth.
- **Fix**: recreate/migrate RDS as **not** publicly accessible, reachable only from the application's VPC/security group. If external access is needed for admin/migration work, use a bastion host or SSM Session Manager tunnel, not a public endpoint.

### SEC-11 — Docker containers run as root, no HEALTHCHECK in image
Every service `Dockerfile` (confirmed pattern via `api-gateway/Dockerfile`) is a proper multi-stage build (`golang:1.25-alpine` builder → `alpine:latest` runtime, binary-only), but has **no `USER` directive** (runs as root inside the container) and **no `HEALTHCHECK` instruction** — health checking is delegated entirely to the EB platform config (`.ebextensions/healthcheck.config`), which means the container has no self-contained health signal for orchestrators that aren't EB (Docker Compose, Kubernetes, ECS run standalone).
- **Fix**: add a non-root `USER` in each Dockerfile's final stage; add a `HEALTHCHECK` instruction (or ensure K8s/ECS task defs define liveness/readiness probes directly, per master-prompt §39) so the container is self-describing regardless of orchestrator.

## MEDIUM

### SEC-8 — Refund policy default (100%, zero fee) contradicts the published Terms & Conditions
Not a security vulnerability in the traditional sense, but a **financial-integrity / fraud-surface issue**: if `REFUND_TIERS` is ever unset in prod (plausible, given SEC-3's pattern of silent fallbacks), every cancellation refunds 100% regardless of timing, directly contradicting the in-app T&C (7+ days → 80%, 3–6 days → 50%, <48h → 0%) and creating a straightforward way for users to book, cancel, and be refunded in full with no penalty, at odds with business intent.
- **Fix**: set `REFUND_TIERS=168:80,72:50,0:0` explicitly in every environment's config, and consider failing startup if it's unset in prod rather than silently defaulting to full refund.

### SEC-9 — No rate limiting anywhere
No rate limiting exists on `/send-otp`, `/verify-otp`, admin login, or any other endpoint (per architecture doc and to be confirmed by code audit). Combined with SEC-1, this means OTP brute-forcing and enumeration are also unmitigated even after SEC-1 is fixed.
- **Fix**: distributed rate limiting via Redis (token bucket per phone/IP) once Redis is introduced — see `04_SCALABILITY_AUDIT.md`.

## Pending confirmation from code-level audit (not yet verified at time of writing)
- Exact JWT validation: is `alg` pinned to HS256 explicitly, or does the verifier accept whatever `alg` the token claims (algorithm-confusion risk)?
- Password/secret hashing for `admins.password_hash` — confirmed as bcrypt per architecture doc; cost factor not yet confirmed.
- File upload handling (if any) — MIME/extension/signature validation status.
- Structured logging — whether OTPs, tokens, or PII currently reach logs beyond the one confirmed OTP-to-stdout case.
- Presence/absence of `govulncheck`, `npm audit`, or any SAST tooling in CI (there is currently no CI at all per architecture doc, so this is presumed absent).

## Do NOT do
Per the master prompt's own constraint (§44): none of the above fixes should be implemented by weakening the mechanism to make load tests pass more easily. All five criticals above must be fixed as part of Phase 3 (Security Hardening) *before* Phase 9's 10,000-user run — running a load test against a system with SEC-1/SEC-2 open would validate the performance of a system that is not safe to call production-ready regardless of throughput numbers.
