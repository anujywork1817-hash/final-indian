export PGPASSWORD=root
PSQL="/c/Program Files/PostgreSQL/18/bin/psql.exe"
REF="$1"; PHONE="$2"
"$PSQL" -U postgres -h localhost -d kumbh_tent -v ON_ERROR_STOP=1 -tAc \
  "INSERT INTO refunds (booking_ref,phone,booking_amount_paise,refund_amount_paise,idempotency_key) VALUES ('$REF','$PHONE',100,100,'dup_probe')" >/dev/null 2>&1
if [ $? -ne 0 ]; then echo "rejected"; else echo "ACCEPTED"; fi
