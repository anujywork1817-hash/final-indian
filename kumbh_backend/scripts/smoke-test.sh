#!/usr/bin/env bash
# End-to-end smoke test against the local stack (gateway :8090).
API="${API:-http://localhost:18090/api/v1}"
PSQL="/c/Program Files/PostgreSQL/18/bin/psql.exe"
DIR="$(dirname "$0")"
export PGPASSWORD=root
PASS=0
FAIL=0

j() { python "$DIR/jq.py" "$1"; }

chk() {
  if [ "$2" = "$3" ]; then
    echo "  PASS  $1"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  $1 (got '$2' want '$3')"
    FAIL=$((FAIL + 1))
  fi
}

chkn() {
  if [ -n "$2" ]; then
    echo "  PASS  $1 -> $2"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  $1 (empty)"
    FAIL=$((FAIL + 1))
  fi
}

sql() { "$PSQL" -U postgres -h localhost -d kumbh_tent -tAc "$1" 2>/dev/null | tr -d ' \r'; }

code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

# Numeric compare: Postgres renders numeric as 100800.00 while
# JSON renders 100800. Same money, different text.
chknum() {
  if python -c "import sys;sys.exit(0 if abs(float('$2' or 'nan')-float('$3' or 'nan'))<0.005 else 1)" 2>/dev/null; then
    echo "  PASS  $1 ($2 == $3)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  $1 (got '$2' want '$3')"
    FAIL=$((FAIL + 1))
  fi
}

PHONE="98765$RANDOM"

echo "== 1. Auth (OTP) =="
OTP=$(curl -s -X POST "$API/auth/send-otp" -H 'Content-Type: application/json' -d "{\"phone\":\"$PHONE\"}" | j otp)
chkn "send-otp returns OTP" "$OTP"
TOKEN=$(curl -s -X POST "$API/auth/verify-otp" -H 'Content-Type: application/json' -d "{\"phone\":\"$PHONE\",\"otp\":\"$OTP\"}" | j token)
chk "verify-otp returns 3-part JWT" "$(echo "$TOKEN" | awk -F. '{print NF}')" "3"
AUTH="Authorization: Bearer $TOKEN"

echo "== 2. JWT enforcement =="
chk "no token -> 401" "$(code "$API/bookings")" "401"
chk "bad token -> 401" "$(code "$API/bookings" -H 'Authorization: Bearer garbage')" "401"
chk "good token -> 200" "$(code "$API/bookings" -H "$AUTH")" "200"

echo "== 3. Tents / coupons =="
TENTS=$(curl -s "$API/tents")
chk "8 seeded tents" "$(echo "$TENTS" | j tents.#)" "8"
TID=$(echo "$TENTS" | j tents.0.id)
chkn "first tent id" "$TID"
chkn "tent detail name" "$(curl -s "$API/tents/$TID" | j name)"
chk "4 seeded coupons" "$(curl -s "$API/coupons" | j coupons.#)" "4"

echo "== 4. Create booking (transaction + FOR UPDATE path) =="
BK=$(curl -s -X POST "$API/bookings" -H "$AUTH" -H 'Content-Type: application/json' \
  -d "{\"tent_id\":$TID,\"check_in\":\"2027-02-10\",\"check_out\":\"2027-02-12\",\"guests\":2,\"units\":1}")
REF=$(echo "$BK" | j booking.booking_ref)
chkn "booking created" "$REF"
chk "status pending" "$(echo "$BK" | j booking.status)" "pending"
chk "appears in my bookings" "$(curl -s "$API/bookings" -H "$AUTH" | j bookings.#)" "1"

echo "== 5. Refund quote: unpaid booking owes nothing =="
chk "unpaid quotes 0" "$(curl -s "$API/bookings/$REF/refund-quote" -H "$AUTH" | j refund_amount)" "0"

echo "== 6. Simulate a captured payment =="
TOT=$(sql "SELECT total_amount FROM bookings WHERE booking_ref='$REF'")
sql "INSERT INTO payments (booking_ref,razorpay_payment,amount,status) VALUES ('$REF','pay_LOCAL1',$TOT,'success'); UPDATE bookings SET status='confirmed',payment_id='pay_LOCAL1' WHERE booking_ref='$REF';" >/dev/null
chkn "booking total" "$TOT"
chk "now confirmed" "$(sql "SELECT status FROM bookings WHERE booking_ref='$REF'")" "confirmed"

echo "== 7. Refund quote: paid, 100% policy =="
chknum "quotes full amount" "$(curl -s "$API/bookings/$REF/refund-quote" -H "$AUTH" | j refund_amount)" "$TOT"

echo "== 8. Cancel -> refund recorded =="
CR=$(curl -s -X PUT "$API/bookings/$REF/cancel" -H "$AUTH")
chk "cancelled" "$(echo "$CR" | j status)" "cancelled"
chknum "refund_amount = total" "$(echo "$CR" | j refund_amount)" "$TOT"
chk "policy rule" "$(echo "$CR" | j policy_rule)" "full_refund"
echo "        msg: $(echo "$CR" | j message)"

echo "== 9. Double-execution guard =="
chk "second cancel -> 400" "$(code -X PUT "$API/bookings/$REF/cancel" -H "$AUTH")" "400"
chk "exactly ONE refund row" "$(sql "SELECT COUNT(*) FROM refunds WHERE booking_ref='$REF'")" "1"
chk "unique index blocks manual duplicate" "$(bash "$DIR/dup_test.sh" "$REF" "$PHONE")" "rejected"

echo "== 10. Refund visible to the user =="
chkn "refund status" "$(curl -s "$API/bookings/$REF/refund" -H "$AUTH" | j refund.status)"
chkn "customer message" "$(curl -s "$API/bookings/$REF/refund" -H "$AUTH" | j refund.message)"
chkn "refund_status on bookings list" "$(curl -s "$API/bookings" -H "$AUTH" | j bookings.0.refund_status)"

echo "== 11. Unsettled refund protects the booking =="
chk "DELETE blocked -> 409" "$(code -X DELETE "$API/bookings/$REF" -H "$AUTH")" "409"

echo "== 12. Admin =="
AL=$(curl -s -X POST "$API/auth/admin/login" -H 'Content-Type: application/json' -d '{"username":"admin","password":"admin123"}')
chk "admin JWT is 3-part" "$(echo "$AL" | j token | awk -F. '{print NF}')" "3"
chk "admin role" "$(echo "$AL" | j role)" "admin"
chk "wrong password -> 401" "$(code -X POST "$API/auth/admin/login" -H 'Content-Type: application/json' -d '{"username":"admin","password":"wrong"}')" "401"
chkn "admin bookings" "$(curl -s "$API/admin/bookings" | j bookings.#)"
chkn "admin stats total_bookings" "$(curl -s "$API/admin/stats" | j total_bookings)"
chkn "admin tents" "$(curl -s "$API/admin/tents" | j tents.#)"
AR=$(curl -s "$API/admin/refunds")
chk "admin refunds total" "$(echo "$AR" | j total)" "1"
chkn "outstanding owed" "$(echo "$AR" | j outstanding)"
echo "        policy: $(echo "$AR" | j active_policy)"

echo "== 13. Approval gate, then retry + manual settle =="
# Refunds start at 'awaiting_approval', so staff shortcuts must
# be refused until someone approves. See scripts/approval-test.sh
# for the full gate coverage.
chk "retry before approval -> 409" "$(code -X POST "$API/admin/refunds/$REF/retry")" "409"
chk "settle before approval -> 409" "$(code -X POST "$API/admin/refunds/$REF/settle" -H 'Content-Type: application/json' -d '{"reference":"X"}')" "409"
chk "approve -> 200" "$(code -X POST "$API/admin/refunds/$REF/approve" -H 'Content-Type: application/json' -d '{"reviewer":"smoke-test"}')" "200"
sleep 3
chk "retry queued -> 202" "$(code -X POST "$API/admin/refunds/$REF/retry")" "202"
chk "settle without reference -> 400" "$(code -X POST "$API/admin/refunds/$REF/settle" -H 'Content-Type: application/json' -d '{}')" "400"
sleep 2
chk "settle with reference -> 200" "$(code -X POST "$API/admin/refunds/$REF/settle" -H 'Content-Type: application/json' -d '{"reference":"UTR-LOCAL-1","note":"local test"}')" "200"
chk "refund now succeeded" "$(sql "SELECT status FROM refunds WHERE booking_ref='$REF'")" "succeeded"
chk "DELETE now allowed -> 200" "$(code -X DELETE "$API/bookings/$REF" -H "$AUTH")" "200"
chk "refund record SURVIVES booking deletion" "$(sql "SELECT COUNT(*) FROM refunds WHERE booking_ref='$REF'")" "1"

echo "== 14. Profile / KYC (migration 002 columns) =="
chk "profile phone" "$(curl -s "$API/profile" -H "$AUTH" | j phone)" "$PHONE"
# KYC handler itself works; reached directly it succeeds.
chk "KYC handler works (direct to auth-service)" "$(curl -s -X POST "http://localhost:8081/auth/kyc" -H "X-User-Phone: $PHONE" -H 'Content-Type: application/json' -d '{"id_type":"aadhaar","id_number":"1234-5678-9012"}' | j status)" "pending"
# KNOWN PRE-EXISTING BUG, pinned so a future fix is noticed:
# /api/v1/auth/kyc sits in the gateway's PUBLIC block, so
# jwtMiddleware never runs and proxy() never forwards
# X-User-Phone -> the handler always sees an unauthorised call.
chk "KNOWN BUG: KYC via gateway -> 401" "$(code -X POST "$API/auth/kyc" -H "X-User-Phone: $PHONE" -H 'Content-Type: application/json' -d '{"id_type":"aadhaar","id_number":"1"}')" "401"
# And the Flutter app calls /kyc, which is not registered at all.
chk "KNOWN BUG: app path /api/v1/kyc -> 404" "$(code -X POST "$API/kyc" -H 'Content-Type: application/json' -d '{"id_type":"a","id_number":"1"}')" "404"
chkn "admin KYC list" "$(curl -s "$API/admin/kyc" | j kyc_users.#)"

echo "== 15. Reviews (migration 002 table) =="
chkn "reviews endpoint responds" "$(curl -s "$API/tents/$TID/reviews" | j total)"

echo ""
echo "=========================================="
echo "  PASSED: $PASS    FAILED: $FAIL"
echo "=========================================="
[ "$FAIL" -eq 0 ] || exit 1
