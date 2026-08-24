# Architecture Context Prompt — Kumbh Tent Booking Platform

> Copy everything below the line into your AI tool of choice.
> It is a self-contained description of the real system as it
> exists in code today (verified by reading the source, not
> inferred from docs).

---

## ROLE

You are a senior software architect. Below is the complete
context of a production tent-booking platform for the Kumbh
Mela pilgrimage in Prayagraj, India. Using **only** this
context, produce:

1. A C4-style architecture (System Context → Container →
   Component) rendered as Mermaid diagrams.
2. Sequence diagrams for the critical flows (auth, booking,
   payment, cancellation+refund).
3. An entity-relationship diagram of the data model.
4. A deployment/infrastructure diagram.
5. A prioritised technical-debt register with severity and
   remediation effort.

Do not invent services, tables, or endpoints that are not
listed here. Where the context explicitly flags something as
missing, broken, or inconsistent, model it as-is and call it
out rather than silently correcting it.

---

## 1. DOMAIN

A two-sided marketplace for pilgrim accommodation:

- **Pilgrims** browse tent listings, book stays for date
  ranges, pay online or in cash at the tent, receive a QR
  e-ticket, can cancel for a refund, and rate their stay.
- **Staff/admins** manage the tent catalogue, bookings,
  coupons, users, KYC verification, refunds, and broadcast
  push notifications.

Currency is INR (₹). Pricing supports surge multipliers for
peak Kumbh dates.

---

## 2. TECH STACK

| Tier | Technology |
| --- | --- |
| Mobile app | **Flutter 3.44.4 / Dart** (Android, iOS, Windows, Web targets present) |
| Admin console | **React 19.2** (Create React App / react-scripts 5) |
| Backend | **Go 1.25**, **Gin v1.10** web framework |
| Database | **PostgreSQL** (15 in local compose, 16 verified, RDS in prod) |
| Auth | **JWT HS256** (`golang-jwt/jwt/v5`), **bcrypt** for admin passwords |
| Payments | **Razorpay** REST API (orders, verify, refunds) |
| Push | **Firebase Cloud Messaging (FCM) V1 API** via `golang.org/x/oauth2/google` |
| DB driver | `lib/pq` (database/sql, no ORM — raw SQL throughout) |
| Config | `joho/godotenv` + environment variables |
| Container | Docker / docker-compose; images in **AWS ECR** |
| Hosting | **AWS Elastic Beanstalk** + **RDS** + **CloudFront**; a Render.com deployment also exists |

**Notable:** there is no ORM, no migration runner, no DI
framework, and no message queue. All persistence is
hand-written SQL against `database/sql`.

---

## 3. REPOSITORY LAYOUT

```
INDIAN TENT/
├── kumbh_backend/          # Go microservices (single Go module: "kumbh-backend")
│   ├── api-gateway/        # main.go — edge proxy + JWT middleware
│   ├── auth-service/       # main.go, handler.go
│   ├── tent-service/       # main.go, handler.go, tent_reviews.go
│   ├── booking-service/    # main.go, handler.go, reminders.go,
│   │                       #   refunds.go, refund_policy.go, refund_policy_test.go
│   ├── payment-service/    # main.go, handler.go, orders.go
│   ├── cmd/                # LEGACY monolith (see §9) — auth.go, bookings.go, tents.go, main.go
│   ├── migrations/         # 001_create_refunds.sql
│   ├── schema.sql          # initial DDL + seed data
│   ├── docker-compose.yml
│   ├── .env.example, .env.aws.example
│   └── README.md
├── kumbh_tent/             # Flutter mobile app
│   └── lib/
│       ├── core/           # constants/, network/api_service.dart, theme/
│       └── features/       # auth/, booking/, home/, payment/, profile/, tents/
└── kumbh-admin/            # React admin SPA (src/App.js — 1,536 lines, single file)
```

All five Go services live in **one Go module** and share the
`main` package name per directory. They are separate binaries
but share no internal library code — helpers like
`sendFCMNotification` are **duplicated** across services.

---

## 4. SERVICES

Every service connects **directly to the same PostgreSQL
database**. There is no per-service data ownership; this is a
distributed monolith, not true microservices.

| Service | Port | Responsibility |
| --- | --- | --- |
| `api-gateway` | 8080 | Sole public entrypoint. Verifies JWT, injects `X-User-Phone`, proxies to internal services. |
| `auth-service` | 8081 | OTP login, JWT issuance, profile, FCM token registration, KYC submission, admin login, user administration |
| `tent-service` | 8082 | Tent catalogue, availability labels, reviews |
| `booking-service` | 8083 | Bookings, coupons, **refunds**, admin stats/revenue, broadcast notifications, nightly cron |
| `payment-service` | 8084 | Razorpay order creation, payment signature verification |

### Gateway mechanics

- CORS: `Access-Control-Allow-Origin: *` on every service.
- `proxy(target)` reads the whole body, rebuilds the request,
  forwards `Authorization`, and sets `X-User-Phone` from the
  JWT claim. 30s client timeout.
- **Trust model:** downstream services trust the
  `X-User-Phone` header absolutely. They are directly
  reachable on their ports and perform no JWT validation of
  their own — anyone who can reach port 8083 can impersonate
  any user by setting that header.
- Routes are split into a public block and a
  `protected := r.Group("/api/v1")` block guarded by
  `jwtMiddleware()`.
- **All `/api/v1/admin/*` routes are registered in the PUBLIC
  block** — they are entirely unauthenticated at the gateway.

---

## 5. COMPLETE ENDPOINT INVENTORY

Route-registration counts (verified by building each service's
gin route tree): gateway 47, booking 24, auth 15, tent 10,
payment 4 — 100 total, no conflicts.

### Public (no JWT)
```
POST   /api/v1/auth/send-otp
POST   /api/v1/auth/verify-otp
GET    /api/v1/tents
GET    /api/v1/tents/:id
GET    /api/v1/tents/:id/reviews
GET    /api/v1/coupons
POST   /api/v1/auth/kyc
POST   /api/v1/auth/admin/login
POST   /api/v1/auth/admin/change-password
POST   /api/v1/auth/admin/change-username
```

### Protected (JWT required)
```
POST   /api/v1/bookings
GET    /api/v1/bookings
PUT    /api/v1/bookings/:ref/cancel
DELETE /api/v1/bookings/:ref
GET    /api/v1/bookings/:ref/refund
GET    /api/v1/bookings/:ref/refund-quote
POST   /api/v1/coupons/validate
POST   /api/v1/orders/create
POST   /api/v1/payments/verify
GET    /api/v1/profile
PUT    /api/v1/profile
POST   /api/v1/fcm-token
POST   /api/v1/tents/:id/reviews
```

### Admin (registered public — NOT authenticated)
```
GET    /api/v1/admin/bookings
PUT    /api/v1/admin/bookings/:ref/status
DELETE /api/v1/admin/bookings/cancelled
DELETE /api/v1/admin/bookings/cancelled/all
GET    /api/v1/admin/stats
GET    /api/v1/admin/revenue/weekly
GET    /api/v1/admin/users
PUT    /api/v1/admin/users/:phone/block
GET    /api/v1/admin/tents
POST   /api/v1/admin/tents
PUT    /api/v1/admin/tents/:id
DELETE /api/v1/admin/tents/:id
GET    /api/v1/admin/coupons
POST   /api/v1/admin/coupons
PUT    /api/v1/admin/coupons/:id/toggle
DELETE /api/v1/admin/coupons/:id
POST   /api/v1/admin/notifications/send
GET    /api/v1/admin/kyc
PUT    /api/v1/admin/kyc/:phone/verify
GET    /api/v1/admin/refunds
POST   /api/v1/admin/refunds/:ref/retry
POST   /api/v1/admin/refunds/:ref/settle
```

Every service also exposes `GET /health` and `HEAD /health`.

---

## 6. DATA MODEL

### Declared in `schema.sql`
- **users** — id, phone (UNIQUE), name, email, role, created_at
- **otp_store** — phone (PK), otp, expires_at, created_at
- **tents** — id, name, class (basic/standard/premium/luxury/vip), location, distance, rating, reviews, price, base_price, is_surge, surge, amenities `TEXT[]`, images `TEXT[]`, capacity, total_units, is_active, created_at
- **coupons** — id, code (UNIQUE), discount (decimal fraction), description, min_amount, max_uses, used_count, is_active, expires_at, created_at
- **bookings** — id, booking_ref (UNIQUE), phone, tent_id → tents, tent_name, location, class, check_in, check_out, nights, guests, units, base_amount, coupon_code, discount, tax, total_amount, status, payment_id, guest_name, guest_phone, id_proof, bed_type, gender_preference, addons, created_at, updated_at
- **payments** — id, booking_ref → bookings, razorpay_order, razorpay_payment, razorpay_signature, amount, status, created_at

### Declared in `migrations/001_create_refunds.sql`
- **refunds** — id, booking_ref (UNIQUE), phone, tent_name, check_in, razorpay_payment_id, razorpay_refund_id, booking_amount_paise, refund_amount_paise, fee_paise, policy_rule, policy_percent, currency, status, attempts, last_error, idempotency_key, created_at, updated_at, settled_at
  - Money stored as **BIGINT paise**, never float.
  - Deliberately **no FK to bookings** — bookings are hard-deleted by four separate code paths, and a refund must outlive the booking as a financial record.
  - Constraints: `uq_refunds_booking_ref` (makes double-refund impossible), `uq_refunds_razorpay_refund_id` (partial), `uq_refunds_idempotency_key`, `ck_refunds_status`, `ck_refunds_amount_bounds` (refund+fee ≤ collected, nothing negative), `ck_refunds_succeeded_has_gateway_id`.
  - Also repairs drift: adds `bookings.razorpay_order_id`, `users.fcm_token`.

### ⚠️ UNDECLARED — used by code, in NO schema file
These exist only in whatever production database was hand-patched. A database built from `schema.sql` + `001` will crash on these paths:

- **`admins`** table — username, password_hash (bcrypt). Powers all admin login.
- **`reviews`** table — booking_ref, tent_id, phone, rating, review.
- **`users.id_type`, `users.id_number`, `users.kyc_status`** — the entire KYC feature.
- **`users.blocked`** / role-based blocking, **`verified_at`**.

Booking status enum: `pending → confirmed → completed`, or `cancelled`.
Refund status enum: `pending → processing → succeeded | failed | manual | not_applicable`.

---

## 7. FLOWS

### 7.1 Authentication (OTP)
1. App → `POST /auth/send-otp {phone}`.
2. Service generates a random 6-digit OTP, upserts into `otp_store` with a 5-minute expiry.
3. **🚨 The OTP is returned in the HTTP response body** (`{"otp": "123456"}`) and printed to stdout. There is no SMS provider integrated. Anyone can request an OTP for any phone number and read it from the response — this is a complete authentication bypass.
4. App → `POST /auth/verify-otp {phone, otp}`. On match, issues an **HS256 JWT with a 30-day expiry** containing the phone claim.
5. Token + phone stored in `flutter_secure_storage`. Any cached FCM token is registered.
6. Gateway's `jwtMiddleware` parses the token and sets `phone` into the gin context; `proxy` forwards it as `X-User-Phone`.

JWT secret falls back to the hardcoded literal `"kumbh2027secret"` (gateway/auth) or `"kumbh2027supersecretkey"` (compose) when `JWT_SECRET` is unset.

Admin login is separate: username + bcrypt password against `admins`, issuing a 24-hour JWT with `role: admin` — **which no endpoint ever checks**.

### 7.2 Browse & search
`GET /tents` (optional `?class=` filter) → tent-service computes an availability label from booked units vs `total_units`. Detail view adds reviews and rating aggregates.

### 7.3 Booking creation
`POST /bookings` → booking-service:
1. `BEGIN` transaction.
2. `SELECT ... FROM tents WHERE id=$1 FOR UPDATE` — locks the tent row.
3. Counts already-booked units for the overlapping date range (`status NOT IN ('cancelled')`).
4. Rejects if requested units exceed remaining capacity.
5. Applies coupon discount + tax, generates a `booking_ref`, inserts with `status='pending'`.
6. `COMMIT`.

This is the one pre-existing flow that correctly uses a transaction + row lock to prevent overbooking.

### 7.4 Payment (Razorpay)
1. App → `POST /orders/create {booking_ref}`. Payment-service verifies the booking belongs to the caller and is still `pending`, calls Razorpay `POST /v1/orders` (amount in paise, `payment_capture: 1`), stores `razorpay_order_id` on the booking, returns the order id.
2. App opens the Razorpay SDK checkout (`razorpay_flutter`).
3. App → `POST /payments/verify {booking_ref, order_id, payment_id, signature}`.
4. Service recomputes `HMAC-SHA256(order_id + "|" + payment_id, RAZORPAY_KEY_SECRET)` and compares. Failures are recorded as a `failed` payments row.
5. On success: inserts a `success` payments row, sets booking `status='confirmed'`, fires an FCM "Booking Confirmed" push asynchronously.

**Cash path:** bookings may carry `payment_id = 'CASH'` ("pay at tent"), remaining `pending` until check-in, with a cron reminder.

**Note:** signature verification falls back to the literal secret `"test_secret"` if `RAZORPAY_KEY_SECRET` is unset, meaning an unconfigured deploy would accept forged signatures.

### 7.5 Cancellation & refund
`PUT /bookings/:ref/cancel` → booking-service:
1. `BEGIN`; `SELECT ... FROM bookings WHERE booking_ref AND phone FOR UPDATE`.
2. Reject if already `cancelled` or `completed`.
3. Determine the amount **actually collected** from the `payments` table (not `bookings.total_amount`), so unpaid bookings refund nothing. Cash bookings that are `confirmed` count as paid.
4. `RefundPolicy.Quote(paidPaise, now, checkIn)` — pure function, integer paise, round-half-up.
5. Update booking to `cancelled`; `INSERT INTO refunds ... ON CONFLICT (booking_ref) DO NOTHING`.
6. `COMMIT`.
7. **After commit, outside the transaction**, call Razorpay `POST /v1/payments/:id/refund` in a goroutine — a slow gateway must never hold a row lock.
8. Success → `succeeded` + gateway id + FCM push. Failure → `failed` with the error text preserved, retryable.

**Double-execution prevention** is layered: a unique index on `booking_ref`, plus a conditional "claim" UPDATE (`WHERE status IN ('pending','failed') AND attempts < max`) so only one worker can ever move a row into `processing`.

**Retry worker:** a goroutine sweeps `pending`/`failed` refunds every `REFUND_RETRY_INTERVAL_MINUTES` (default 15) up to `REFUND_MAX_ATTEMPTS` (default 6). Staff can force retries or record out-of-band settlements (cash/NEFT) via the admin endpoints.

**Policy** is env-driven: `REFUND_TIERS` as `hours:percent` pairs (empty = 100% refund), plus `REFUND_FEE_PERCENT`. Default is **100%, zero fee** — chosen so an unconfigured deploy can never under-refund.

> **⚠️ Policy conflict:** the app's own Terms & Conditions screen publishes 7+ days → 80%, 3–6 days → 50%, within 48h → none. The 100% default contradicts it. `REFUND_TIERS=168:80,72:50,0:0` matches the published terms. The T&C also has an undefined 48–72h band.

### 7.6 Booking deletion (four paths, all refund-aware)
Cancelled bookings are hard-deleted by: the user (`DELETE /bookings/:ref`), two admin endpoints (30-day and delete-all), and a nightly cron. All four now skip any booking whose refund is `pending`/`processing`/`failed`/`manual`.

### 7.7 Reviews
`POST /tents/:id/reviews {booking_ref, rating, review}` — inserts into `reviews` and recomputes the tent's aggregate rating and count.

### 7.8 KYC
`POST /auth/kyc {id_type, id_number}` sets `users.kyc_status='pending'`; an admin verifies via `PUT /admin/kyc/:phone/verify`.

### 7.9 Notifications & scheduled work
`booking-service` runs `startReminderScheduler()` — an infinite goroutine that sleeps until **02:30 UTC (08:00 IST)** daily and then:
- auto-completes `confirmed` bookings whose `check_out` has passed;
- sends "thank you / please rate" pushes for stays ending today;
- sends check-in reminders for tomorrow and today;
- sends cash-payment reminders for `pending` + `CASH` bookings;
- deletes cancelled bookings older than 30 days (now refund-aware).

FCM uses the V1 API with an OAuth2 token minted from a service-account JSON (file path or inline env), hardcoded project id `kumbh-tent-19e88`, channel `kumbh_tent_channel`.

---

## 8. CLIENT APPLICATIONS

### Flutter app (`kumbh_tent`)
Screens by feature:
- **auth/** — splash, login, OTP, name setup
- **tents/** — browse, search, tent detail
- **booking/** — booking form, my bookings, e-ticket (QR), cancellations, coupons, review
- **payment/** — payment screen (Razorpay SDK)
- **profile/** — profile, edit profile, KYC, terms, privacy policy
- **home/** — home screen

Networking is **split and inconsistent**: `core/network/api_service.dart` wraps **Dio** with a `baseUrl` and auth-header injection, but several screens (e.g. `my_bookings_screen.dart`) bypass it and use the raw **`http`** package with manually-read secure-storage tokens.

Notable dependency facts:
- `flutter_riverpod` is declared and `ProviderScope` wraps the app, **but no providers exist** — state is all `StatefulWidget` + `setState`.
- `go_router` is declared but **completely unused**; navigation is imperative `Navigator.push(MaterialPageRoute(...))`.
- Also present: `google_maps_flutter`, `geolocator`, `table_calendar`, `qr_flutter`, `cached_network_image`, `shimmer`, `lottie`, `hive_flutter`, `share_plus`, `image_picker`.

### React admin (`kumbh-admin`)
A single 1,536-line `src/App.js` — no router, no state library, no component splitting. Plain `fetch` against a module-level `API_BASE`. Manages tents, bookings, coupons, users, KYC, stats, and broadcast notifications.

**⚠️ The two clients point at different backends:**
- Flutter → `https://d3dmb495g7jwhi.cloudfront.net/api/v1`
- Admin → `https://kumbh-gateway.onrender.com/api/v1`

Both apps hardcode their base URL in source with other environments left as commented-out lines; there is no build-time environment configuration.

---

## 9. DEPLOYMENT & CONFIGURATION

- `docker-compose.yml` pulls five images from **ECR account 112284275877**, region `ap-south-1`. A `local` profile adds a Postgres container that runs `schema.sql` + `001_create_refunds.sql` via `docker-entrypoint-initdb.d`.
- Production targets **AWS Elastic Beanstalk** + **RDS** (`sslmode=require`) fronted by **CloudFront**. A Render.com deployment also exists.
- Config via env vars: `DATABASE_URL`, `JWT_SECRET`, `RAZORPAY_KEY_ID/SECRET`, `*_SERVICE_URL`, `*_SERVICE_PORT`, `FIREBASE_SERVICE_ACCOUNT[_JSON]`, and the `REFUND_*` family.
- **Config bug:** `.env.aws.example` documents `GATEWAY_PORT=80`, but `api-gateway/main.go` reads `API_GATEWAY_PORT`. Setting the documented variable has no effect.
- **Secrets are committed:** `docker-compose.yml` contains literal Razorpay test keys and a default JWT secret as fallback values.
- **No migration runner exists.** `schema.sql` only runs on fresh-database init. Migrations are applied by hand with `psql`.

### Legacy code
`kumbh_backend/cmd/` is an **older monolithic version** of the app (auth + bookings + tents in one binary, with its own `authMiddleware`). It is part of the same Go module and still compiles, but nothing deploys it. It duplicates and diverges from the live service logic.

---

## 10. TESTING

- Go: `booking-service` has 33 passing assertions covering refund tier boundaries, half-up rounding, fee stacking, and an exhaustive sweep proving the calculation cannot violate the DB constraints. **No other Go service has any tests.**
- Flutter: 10 passing widget tests for the refund status panel. The pre-existing `widget_test.dart` splash smoke test **fails** (`!timersPending` — the splash screen holds an unconditional 2,800 ms `Future.delayed`).
- React admin: only the CRA default `App.test.js`.
- No integration tests, no contract tests, no CI configuration in the repository.

---

## 11. KNOWN ISSUES TO MODEL

Rank these in your technical-debt register:

1. **OTP returned in the API response** — total auth bypass; no SMS provider exists.
2. **All admin endpoints unauthenticated** at the gateway, including refund retry/settle, user blocking, and tent CRUD.
3. **Internal services trust `X-User-Phone` blindly** and are directly reachable; the gateway is not the only path in.
4. **Hardcoded secret fallbacks** — JWT (`kumbh2027secret`) and Razorpay signature (`test_secret`) both default to literals when env vars are unset.
5. **Undeclared schema** — `admins`, `reviews`, and the KYC/blocking columns exist in no DDL file; the schema cannot be reproduced from source.
6. **No migration runner**; `schema.sql` only applies to brand-new databases.
7. **Two clients, two different backend URLs**, both hardcoded.
8. **Distributed monolith** — five services, one shared database, no data ownership, duplicated helper code.
9. **Legacy `cmd/` monolith** still in the module.
10. **Unused architectural dependencies** — Riverpod and go_router declared but not used, so the app has no state-management or routing strategy.
11. **Cron is an in-process goroutine loop** — it runs in every replica, so horizontal scaling would multiply reminders and refund retries.
12. **Refund policy contradicts the published Terms & Conditions.**
13. `CORS: *` on every service.

---

## 12. OUTPUT REQUIREMENTS

- Use Mermaid for every diagram.
- Distinguish **current state** from **recommended target state**; give the target as a separate diagram with a migration path.
- For the debt register use a table: Issue | Severity (Critical/High/Medium/Low) | Impact | Remediation | Effort (S/M/L).
- Explicitly mark anything you infer beyond the context above as an assumption.
