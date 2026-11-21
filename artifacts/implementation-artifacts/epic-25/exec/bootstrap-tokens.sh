#!/bin/zsh
# Mints JWTs for QA phones via master OTP 1039 on live BE. Usage: ./bootstrap-tokens.sh <phone>...
BASE=https://fenzit-be-1.onrender.com/api/v1
for PHONE in "$@"; do
  OUT="tokens/${PHONE}.json"
  if [[ -s "$OUT" ]] && jq -e '.token' "$OUT" >/dev/null 2>&1; then echo "skip $PHONE (cached)"; continue; fi
  SID=$(curl -s --max-time 20 -X POST $BASE/auth/otp/send -H 'Content-Type: application/json' \
    -d "{\"countryCode\":\"+91\",\"phoneNumber\":\"${PHONE}\"}" | jq -r '.otp_session_id // empty')
  if [[ -z "$SID" ]]; then echo "FAIL send $PHONE"; continue; fi
  sleep 1
  curl -s --max-time 20 -X POST $BASE/auth/otp/verify -H 'Content-Type: application/json' \
    -d "{\"otpSessionId\":\"${SID}\",\"otpCode\":\"1039\"}" > "$OUT"
  if jq -e '.token' "$OUT" >/dev/null 2>&1; then echo "ok $PHONE"; else echo "FAIL verify $PHONE: $(head -c 120 "$OUT")"; fi
  sleep 1
done
