# Kumbh Tent — Backend

Go microservices behind a single API gateway.

| Service | Port | Responsibility |
| --- | --- | --- |
| `api-gateway` | 8080 | Public entrypoint, JWT verification, proxying |
| `auth-service` | 8081 | OTP login, profile, KYC, FCM tokens |
| `tent-service` | 8082 | Tent catalogue, reviews |
| `booking-service` | 8083 | Bookings, coupons, **refunds**, reminders |
| `payment-service` | 8084 | Razorpay order creation and verification |

Configuration lives in `.env` — copy `.env.example` and fill it in.
Production/Elastic Beanstalk values are documented in `.env.aws.example`.

---

## Running locally

```powershell
.\run-local.ps1            # build if needed, then start all 5 services
.\run-local.ps1 -Rebuild   # force a rebuild first
.\run-local.ps1 -Stop      # stop everything
```

Then smoke-test the whole stack end to end:

```bash
bash scripts/smoke-test.sh
```

### Ports

| Service | Port |
| --- | --- |
| api-gateway | **18090** |
| auth-service | 8081 |
| tent-service | 8082 |
| booking-service | 8083 |
| payment-service | 8084 |
| PostgreSQL | 5432 |

API base URL: **`http://localhost:18090/api/v1`**

> The gateway deliberately avoids both 8080 and 8090 on this
> machine:
>
> - **8080** is owned by `Desktop\kumbh-backend-update\kumbh-local.exe`,
>   an unrelated project. It also answers `/health` with 200, so a
>   naive check reports "up" while our gateway has actually died
>   with a bind error.
> - **8090** gets grabbed by `com.docker.backend` whenever Docker
>   Desktop starts and nothing else is holding it.
>
> Because of the first case, `run-local.ps1` requires the `/health`
> response body to *name the expected service* — HTTP 200 alone is
> not treated as proof.
>
> If 18090 ever conflicts too, check what Windows has reserved
> with `netsh int ipv4 show excludedportrange protocol=tcp` and
> pick a port outside those ranges. Change it in `run-local.ps1`
> (both the `$services` table and `$env:API_GATEWAY_PORT`) and in
> the app's `kBaseUrl`.

### Database setup (one time)

`run-local.ps1` expects a `kumbh_tent` database that has had
`schema.sql` and every file under `migrations/` applied, in order:

```bash
psql -U postgres -h localhost -d kumbh_tent -f schema.sql
for f in migrations/*.sql; do
  psql -U postgres -h localhost -d kumbh_tent -f "$f"
done
```

`002` is required — without it, admin login, reviews and KYC all
fail, because those tables/columns appear in no other SQL file.
`003` adds the refund approval gate. `005`-`015` back the finance/
P&L, payment-tracking, invoicing, ledger, RBAC/audit and
vendor-payables features — skipping them makes those endpoints
fail with a Postgres `42P01 relation does not exist` error (see
BUG-25: they used to be applied nowhere, dev included — see
`docker-compose.dev.yml`, which now mounts all of them).

Seed an admin account so the panel can be used (bcrypt hash for
`admin123`; generate your own for anything non-local):

```sql
INSERT INTO admins (username, password_hash)
VALUES ('admin', '<bcrypt-hash>')
ON CONFLICT (username) DO UPDATE SET password_hash = EXCLUDED.password_hash;
```

### Configuration precedence

`run-local.ps1` exports the local settings into the environment
before launching each binary, and the services run from `bin\`
which contains no `.env`. `godotenv.Load()` never overrides an
already-set variable, so the repo's docker-compose-oriented
`.env` (which points `DATABASE_URL` at the container hostname
`postgres` and the service URLs at container DNS names) is left
untouched and cannot interfere.

### Test credentials

- **Admin console:** `admin` / `admin123`
- **Pilgrim login:** any phone number — `POST /auth/send-otp`
  returns the OTP directly in the response body, so no SMS
  provider is needed locally. (This is also a serious production
  vulnerability — see *Known gaps*.)

### Expected local behaviour

Refunds will settle to status `failed`, not `succeeded`. That is
correct: the Razorpay refund call is real, and test payment ids
created by the smoke test do not exist at Razorpay. The failure
is recorded with the gateway error and left retryable, which is
exactly the designed path. Use
`POST /api/v1/admin/refunds/:ref/settle` to close one out
manually.

### Pointing the apps at localhost

Neither client reads its base URL from configuration; both
hardcode it in source.

- Flutter — set `kBaseUrl` in
  `kumbh_tent/lib/core/constants/constants.dart`. `ApiService.baseUrl`
  now just aliases that constant, so one edit covers both the Dio
  and raw-`http` call sites. (They used to be separate values,
  which meant half the app could talk to production while the
  other half talked to localhost.)
- React admin — `kumbh-admin/src/App.js`, the `API_BASE` constant.

**Physical Android device over USB** — the phone's `localhost`
is the phone, so tunnel it:

```bash
adb reverse tcp:18090 tcp:18090
```

`adb reverse` is **not durable**. It is dropped whenever the adb
server restarts, the device reconnects, or `flutter run`
attaches — which is every launch. A dropped tunnel shows up in
the app as `DioException [connection error] ... Connection
refused`, and the port in that message is not necessarily 18090,
so it misleads.

Rather than re-running it by hand, keep it alive in a second
terminal:

```powershell
cd kumbh_tent
.\keep-tunnel.ps1
```

That re-applies the tunnel every 3 seconds and logs when it
restores one, so relaunching the app never silently breaks the
connection.

To check the tunnel is genuinely carrying (not just registered
on the PC side), confirm the phone itself has a listener —
18090 is hex `46AA`:

```bash
adb shell "cat /proc/net/tcp /proc/net/tcp6 | grep -i ':46AA'"
```

`kBaseUrl` is a `const`, so a hot *reload* will not pick up a
change to it — you need a hot restart (`R`) or a rebuild.

`android:usesCleartextTraffic="true"` and the `INTERNET`
permission are already set in `AndroidManifest.xml`, so plain
HTTP works on device without extra config.

Other targets: Android emulator → `http://10.0.2.2:18090/api/v1`;
Wi-Fi without a cable → `http://<your-LAN-IP>:18090/api/v1` plus a
firewall rule allowing inbound 18090.

---

## Refunds on cancellation

### What it does

When a customer cancels a booking, the backend now calculates
what they are owed, records it, and actually sends the money
back through Razorpay.

Before this existed, `PUT /bookings/:ref/cancel` set
`status = 'cancelled'` and nothing else — while the app told
every user *"Refunds are processed within 5-7 business days to
your original payment method."* No refund was ever issued.

The flow:

1. **Cancel** — the booking row is locked `FOR UPDATE` inside a
   transaction, so two concurrent cancels cannot both proceed.
2. **Quote** — the refund is computed from what was actually
   *collected* (a successful row in `payments`), not from
   `bookings.total_amount`. An unpaid booking refunds nothing.
3. **Record** — a `refunds` row is inserted in the same
   transaction. A unique index on `refunds.booking_ref` makes a
   second refund for the same booking impossible at the database
   level.
4. **Await approval** — with `REFUND_REQUIRE_APPROVAL=true` (the
   default) the row is parked at `awaiting_approval` and
   **nothing is sent to the gateway**. Staff approve or reject
   it in the admin panel's *Refunds* tab.
5. **Commit**, then **pay** — once approved, the Razorpay call
   happens *after* the transaction commits, so a slow gateway
   never holds a row lock.
6. **Retry** — if the gateway fails, the row is left `failed`
   with the error recorded, and a background worker re-drives it
   until `REFUND_MAX_ATTEMPTS`. Staff can force further retries.

### The approval gate

A cancellation creates a refund *request*, not a payout.

| Action | Endpoint | Effect |
| --- | --- | --- |
| Approve | `POST /api/v1/admin/refunds/:ref/approve` | `awaiting_approval` → `pending` (or `manual` for cash bookings), then dispatches |
| Reject | `POST /api/v1/admin/refunds/:ref/reject` | `awaiting_approval` → `rejected`, terminal, nothing ever sent. **`reason` is required.** |

Both record `reviewed_by` and `reviewed_at`. Rejections also
store `rejection_reason`, which is shown to the customer and
enforced by `ck_refunds_rejected_has_reason` — a refusal to
return someone's money has to stay explainable months later.

The gate cannot be bypassed. Every other path that touches a
refund excludes `awaiting_approval`:

- the background retry worker selects only `pending`/`failed`
- `executeRefund`'s claim UPDATE matches only `pending`/`failed`
- `/retry` accepts only `failed`/`manual`/`pending`
- `/settle` accepts only `manual`/`failed`/`pending`

Approve and reject are both single-winner conditional UPDATEs
(`WHERE status = 'awaiting_approval'`), so two admins clicking
at once cannot double-dispatch — the second gets HTTP 409.

Bookings with a refund in `awaiting_approval` are protected from
deletion by the user, both admin clear endpoints and the nightly
cron. `rejected` is *not* protected: nothing is owed, so normal
cleanup applies, while the refund record itself survives as
audit.

### Money handling

All amounts are stored and computed in **paise as `BIGINT`**.
Percentages are applied once and rounded half-up at that single
point, so no floating-point drift can reach a customer's bank.

Three database constraints back the application logic:

| Constraint | Guarantees |
| --- | --- |
| `uq_refunds_booking_ref` | one refund per booking, ever |
| `ck_refunds_amount_bounds` | `refund + fee <= collected`, nothing negative |
| `ck_refunds_succeeded_has_gateway_id` | a "succeeded" refund always carries proof |

`refunds` is deliberately **not** foreign-keyed to `bookings`:
bookings are hard-deleted by users, by two admin endpoints and
by a nightly cron. A refund is a financial record and carries
its own snapshot so it outlives the booking. Those four deletion
paths now skip any booking whose refund is still unsettled.

### Refund states

| Status | Meaning |
| --- | --- |
| `awaiting_approval` | requested; waiting on a staff decision. Nothing sent. |
| `rejected` | staff declined, with a recorded reason. Terminal. |
| `pending` | approved and queued for the gateway |
| `processing` | claimed by a worker, gateway call in flight |
| `succeeded` | gateway confirmed; `settled_at` set |
| `failed` | gateway rejected; retried automatically |
| `manual` | cash booking — staff must settle by hand |
| `not_applicable` | nothing owed (unpaid booking, or a 0% tier) |

`failed` is never shown to the customer as a failure — it is
retried, so the app still says "processing". Staff see the real
state and the gateway error via the admin endpoints.

### Configuration

All settings are env vars with safe defaults; see `.env.example`
for the annotated list.

| Variable | Default | Purpose |
| --- | --- | --- |
| `REFUND_ENABLED` | `true` | Master switch |
| `REFUND_TIERS` | *(empty)* | Notice-based tiers; empty = **100% refund** |
| `REFUND_FEE_PERCENT` | `0` | Flat fee deducted after the tier |
| `REFUND_SETTLEMENT_DAYS` | `3-4` | The wait time shown to users |
| `REFUND_MAX_ATTEMPTS` | `6` | Automatic gateway retries |
| `REFUND_RETRY_INTERVAL_MINUTES` | `15` | Retry worker cadence |
| `REFUND_GATEWAY_TIMEOUT_SECONDS` | `20` | Per-call Razorpay timeout |
| `RAZORPAY_REFUND_SPEED` | `normal` | `normal` (free) or `optimum` (paid, faster) |

`booking-service` now needs `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET`
as well as `payment-service`, since it is what issues the refund.

**`REFUND_TIERS` format** — `<hours-of-notice>:<percent>`, comma
separated, e.g. `168:80,72:50,0:0` meaning ≥168h → 80%, ≥72h →
50%, otherwise 0%. Malformed entries are logged and skipped
rather than crashing the service; a fully invalid value falls
back to 100%, which is the customer-safe direction.

> **Default policy is 100% refund, no fee.** This was chosen so
> that an unconfigured deployment can never quietly short-change
> a customer. Charging a cancellation fee is an explicit opt-in.
>
> ⚠️ **This does not match the app's published Terms & Conditions**,
> which state 80% / 50% / none by notice period
> (`kumbh_tent/lib/features/profile/screens/terms_screen.dart`).
> To match the published terms exactly, set
> `REFUND_TIERS=168:80,72:50,0:0`. Decide which of the two is
> authoritative before launch.

### Endpoints

All customer routes are under `/api/v1` on the gateway and
require a JWT. Admin routes currently inherit the same
(un-authenticated) treatment as every other `/api/v1/admin/*`
route — see *Known gaps* below.

| Method | Endpoint | Purpose |
| --- | --- | --- |
| `PUT` | `/api/v1/bookings/:ref/cancel` | Cancel, and create the refund |
| `GET` | `/api/v1/bookings/:ref/refund` | Refund state for own booking |
| `GET` | `/api/v1/bookings/:ref/refund-quote` | Preview a refund before cancelling |
| `GET` | `/api/v1/admin/refunds` | List refunds; `?status=awaiting_approval`, `?limit=` |
| `POST` | `/api/v1/admin/refunds/:ref/approve` | Release a refund to the gateway |
| `POST` | `/api/v1/admin/refunds/:ref/reject` | Decline it; `reason` required |
| `POST` | `/api/v1/admin/refunds/:ref/retry` | Force a retry, resetting the attempt budget |
| `POST` | `/api/v1/admin/refunds/:ref/settle` | Record an out-of-band settlement |

`GET /api/v1/admin/refunds` also returns `outstanding` — the
total still owed across all unsettled refunds — and
`active_policy`, a rendering of the live configuration.

`POST /api/v1/admin/refunds/:ref/settle` requires a `reference`
in the body (bank UTR, cash receipt number) and is how a
`manual` (cash) refund gets closed out:

```bash
curl -X POST "$GATEWAY/api/v1/admin/refunds/KT-ABC123/settle" \
  -H 'Content-Type: application/json' \
  -d '{"reference":"UTR123456789","note":"cash returned at counter"}'
```

`GET /api/v1/bookings` (the app's booking list) now also carries
`refund_status`, `refund_amount` and `refund_message` per
booking, which is what the Cancellations screen renders.

### Migration

```bash
for f in migrations/*.sql; do
  psql "$DATABASE_URL" -f "$f"
done
```

Idempotent — safe to run repeatedly. `001` creates `refunds` and
also adds two columns the services already used but that
`schema.sql` never declared (`bookings.razorpay_order_id`,
`users.fcm_token`); `005`-`015` back finance/P&L, payment
tracking, invoicing, the ledger, RBAC/audit and vendor payables.

There is no migration runner in this repo; migrations are
applied by hand. `schema.sql` is only used to initialise a fresh
local Postgres via docker-compose, so **a fresh local database
needs every migration applied too** — `docker-compose.dev.yml`
does this automatically for local Docker Postgres; a hand-rolled
local `psql` setup or a fresh RDS instance does not, and must run
the loop above.

### Tests

```bash
go test ./booking-service/
```

Covers the refund calculation: tier boundaries from both sides,
half-up rounding, fee stacking, and an exhaustive sweep
asserting the calculation can never violate the database's
amount constraints.

### Known gaps

- **KYC is broken end-to-end** (pre-existing, found during local
  testing, not yet fixed). Two separate faults:
  1. The Flutter app posts to `/kyc`, but the gateway only
     registers `/api/v1/auth/kyc` → **404**.
  2. Even at the correct path, `/api/v1/auth/kyc` sits in the
     gateway's *public* route block, so `jwtMiddleware` never
     runs, `c.Get("phone")` is unset, and `proxy()` therefore
     never forwards the `X-User-Phone` header the handler
     requires → **401**.

  The handler itself is correct — calling auth-service directly
  on `:8081` succeeds. The fix is to move the route into the
  `protected` group and change the app's path to `/auth/kyc`.
  `scripts/smoke-test.sh` pins both faults so a fix is noticed.
- **Admin refund routes are unauthenticated at the gateway**,
  matching every other existing `/api/v1/admin/*` route. Anyone
  who can reach the gateway can list refunds and trigger
  retries. This is a pre-existing pattern in this codebase, not
  something introduced here, but it is more serious on a
  money-moving endpoint and should be fixed before launch.
- `RAZORPAY_REFUND_SPEED=normal` is Razorpay's free tier, which
  they document as taking 5–7 working days to reach the customer's
  bank. The app promises **3–4**. Either set `optimum` (Razorpay
  charges for it) or change `REFUND_SETTLEMENT_DAYS` to match
  reality.
