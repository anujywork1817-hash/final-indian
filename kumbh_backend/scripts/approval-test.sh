#!/usr/bin/env bash
# Verifies the refund approval gate end to end.
#
# The property that matters: a cancelled booking must NOT send
# anything to the payment gateway until a human approves it.
API="${API:-http://localhost:18090/api/v1}"
PSQL="${PSQL:-/c/Program Files/PostgreSQL/18/bin/psql.exe}"
DIR="$(dirname "$0")"
export PGPASSWORD="${PGPASSWORD:-root}"
PASS=0
FAIL=0

j() { python "$DIR/jq.py" "$1"; }
sql() { "$PSQL" -U postgres -h localhost -d kumbh_tent -tAc "$1" 2>/dev/null | tr -d ' \r'; }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

chk() {
  if [ "$2" = "$3" ]; then echo "  PASS  $1"; PASS=$((PASS + 1));
  else echo "  FAIL  $1 (got '$2' want '$3')"; FAIL=$((FAIL + 1)); fi
}
chkn() {
  if [ -n "$2" ]; then echo "  PASS  $1 -> $2"; PASS=$((PASS + 1));
  else echo "  FAIL  $1 (empty)"; FAIL=$((FAIL + 1)); fi
}

# Creates a paid, confirmed booking and echoes its ref.
make_paid_booking() {
  local phone="$1"
  local otp token tid bk ref tot
  otp=$(curl -s -X POST "$API/auth/send-otp" -H 'Content-Type: application/json' -d "{\"phone\":\"$phone\"}" | j otp)
  token=$(curl -s -X POST "$API/auth/verify-otp" -H 'Content-Type: application/json' -d "{\"phone\":\"$phone\",\"otp\":\"$otp\"}" | j token)
  tid=$(curl -s "$API/tents" | j tents.0.id)
  bk=$(curl -s -X POST "$API/bookings" -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
      -d "{\"tent_id\":$tid,\"check_in\":\"2027-03-10\",\"check_out\":\"2027-03-12\",\"guests\":2,\"units\":1}")
  ref=$(echo "$bk" | j booking.booking_ref)
  tot=$(sql "SELECT total_amount FROM bookings WHERE booking_ref='$ref'")
  sql "INSERT INTO payments (booking_ref,razorpay_payment,amount,status) VALUES ('$ref','pay_APPROVAL_$RANDOM',$tot,'success');
       UPDATE bookings SET status='confirmed', payment_id='pay_APPROVAL_$RANDOM' WHERE booking_ref='$ref';" >/dev/null
  echo "$ref|$token"
}

echo "== 1. Cancelling parks the refund, does NOT pay it =="
IFS='|' read -r REF TOKEN <<< "$(make_paid_booking "97771$RANDOM")"
chkn "booking created" "$REF"
CR=$(curl -s -X PUT "$API/bookings/$REF/cancel" -H "Authorization: Bearer $TOKEN")
chk "refund_status is awaiting_approval" "$(echo "$CR" | j refund_status)" "awaiting_approval"
chk "requires_approval flag set" "$(echo "$CR" | j requires_approval)" "true"
chk "DB agrees" "$(sql "SELECT status FROM refunds WHERE booking_ref='$REF'")" "awaiting_approval"
chk "attempts still 0 (nothing sent)" "$(sql "SELECT attempts FROM refunds WHERE booking_ref='$REF'")" "0"
chk "no gateway refund id" "$(sql "SELECT COALESCE(razorpay_refund_id,'NONE') FROM refunds WHERE booking_ref='$REF'")" "NONE"
chk "requested_at recorded" "$(sql "SELECT CASE WHEN requested_at IS NULL THEN 'null' ELSE 'set' END FROM refunds WHERE booking_ref='$REF'")" "set"
echo "        msg: $(echo "$CR" | j message)"

echo "== 2. An unapproved refund is immune to the worker and to staff shortcuts =="
chk "retry cannot bypass approval -> 409" "$(code -X POST "$API/admin/refunds/$REF/retry")" "409"
chk "settle cannot bypass approval -> 409" "$(code -X POST "$API/admin/refunds/$REF/settle" -H 'Content-Type: application/json' -d '{"reference":"SNEAKY"}')" "409"
chk "still awaiting_approval" "$(sql "SELECT status FROM refunds WHERE booking_ref='$REF'")" "awaiting_approval"

echo "== 3. Customer sees a pending-review state, not a promise =="
RJ=$(curl -s "$API/bookings/$REF/refund" -H "Authorization: Bearer $TOKEN")
chk "status exposed" "$(echo "$RJ" | j refund.status)" "awaiting_approval"
chkn "customer message" "$(echo "$RJ" | j refund.message)"
chk "message mentions approval" "$(echo "$RJ" | j refund.message | grep -ci 'approv')" "1"

echo "== 4. Booking cannot be deleted while a decision is pending =="
chk "DELETE blocked -> 409" "$(code -X DELETE "$API/bookings/$REF" -H "Authorization: Bearer $TOKEN")" "409"

echo "== 5. Approval releases it to the gateway =="
AP=$(curl -s -X POST "$API/admin/refunds/$REF/approve" -H 'Content-Type: application/json' -d '{"reviewer":"alice"}')
chkn "approve response" "$(echo "$AP" | j message)"
chk "reviewer recorded" "$(sql "SELECT reviewed_by FROM refunds WHERE booking_ref='$REF'")" "alice"
chk "reviewed_at recorded" "$(sql "SELECT CASE WHEN reviewed_at IS NULL THEN 'null' ELSE 'set' END FROM refunds WHERE booking_ref='$REF'")" "set"
sleep 3
# Razorpay rejects the fake payment id, so this correctly lands
# on 'failed' and stays retryable — proving it WAS dispatched.
chkn "status after dispatch" "$(sql "SELECT status FROM refunds WHERE booking_ref='$REF'")"
chk "attempts incremented (gateway was called)" "$(sql "SELECT CASE WHEN attempts > 0 THEN 'yes' ELSE 'no' END FROM refunds WHERE booking_ref='$REF'")" "yes"

echo "== 6. Double approval is impossible =="
chk "second approve -> 409" "$(code -X POST "$API/admin/refunds/$REF/approve" -H 'Content-Type: application/json' -d '{"reviewer":"bob"}')" "409"
chk "reviewer unchanged" "$(sql "SELECT reviewed_by FROM refunds WHERE booking_ref='$REF'")" "alice"

echo "== 7. Rejection path =="
IFS='|' read -r REF2 TOKEN2 <<< "$(make_paid_booking "97772$RANDOM")"
curl -s -X PUT "$API/bookings/$REF2/cancel" -H "Authorization: Bearer $TOKEN2" >/dev/null
chk "reject without reason -> 400" "$(code -X POST "$API/admin/refunds/$REF2/reject" -H 'Content-Type: application/json' -d '{}')" "400"
chk "still awaiting after failed reject" "$(sql "SELECT status FROM refunds WHERE booking_ref='$REF2'")" "awaiting_approval"
chk "reject with reason -> 200" "$(code -X POST "$API/admin/refunds/$REF2/reject" -H 'Content-Type: application/json' -d '{"reason":"Cancelled after check-in","reviewer":"alice"}')" "200"
chk "status rejected" "$(sql "SELECT status FROM refunds WHERE booking_ref='$REF2'")" "rejected"
chk "reason stored" "$(sql "SELECT rejection_reason FROM refunds WHERE booking_ref='$REF2'")" "Cancelledaftercheck-in"
chk "never dispatched" "$(sql "SELECT attempts FROM refunds WHERE booking_ref='$REF2'")" "0"
chk "approve after reject -> 409" "$(code -X POST "$API/admin/refunds/$REF2/approve")" "409"

echo "== 8. Rejected refund owes nothing, so cleanup may proceed =="
chk "DELETE now allowed -> 200" "$(code -X DELETE "$API/bookings/$REF2" -H "Authorization: Bearer $TOKEN2")" "200"
chk "rejection record survives" "$(sql "SELECT COUNT(*) FROM refunds WHERE booking_ref='$REF2'")" "1"

echo "== 9. DB refuses a reasonless rejection =="
chk "constraint blocks empty reason" "$(bash "$DIR/reject_probe.sh" "$REF")" "rejected"

echo "== 10. Admin queue reporting =="
AR=$(curl -s "$API/admin/refunds")
chk "requires_approval advertised" "$(echo "$AR" | j requires_approval)" "true"
chkn "awaiting_approval count" "$(echo "$AR" | j awaiting_approval)"
echo "        policy: $(echo "$AR" | j active_policy)"

echo ""
echo "=========================================="
echo "  PASSED: $PASS    FAILED: $FAIL"
echo "=========================================="
[ "$FAIL" -eq 0 ] || exit 1
