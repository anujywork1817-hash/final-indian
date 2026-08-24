#!/usr/bin/env bash
# Probes ck_refunds_rejected_has_reason: the database itself must
# refuse a 'rejected' row with no explanation, independently of
# whatever the HTTP handler validates.
#
# Echoes "rejected" when the constraint holds, "ACCEPTED" if the
# write slipped through.
export PGPASSWORD="${PGPASSWORD:-root}"
PSQL="${PSQL:-/c/Program Files/PostgreSQL/18/bin/psql.exe}"
REF="$1"

"$PSQL" -U postgres -h localhost -d kumbh_tent -v ON_ERROR_STOP=1 -tAc \
  "UPDATE refunds SET status='rejected', rejection_reason=NULL WHERE booking_ref='$REF'" \
  >/dev/null 2>&1

if [ $? -ne 0 ]; then echo "rejected"; else echo "ACCEPTED"; fi
