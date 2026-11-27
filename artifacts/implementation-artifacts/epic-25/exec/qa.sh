#!/bin/zsh
# Epic-25 QA helper. Usage: qa.sh <caseId> <expected-summary> ; plus api helper below.
BASE=https://fenzit-be-1.onrender.com/api/v1
LEDGER=/Users/admin/workspace/fenzit-meta/artifacts/implementation-artifacts/epic-25/RESULTS-LEDGER.md
tok() { jq -r .token "tokens/${1}.json"; }
# api <phone> <METHOD> <path> [json-body] [idempotency:y]
api() {
  local P=$1 M=$2 PATH_=$3 BODY=$4 IDEM=$5
  local -a H=("Authorization: Bearer $(tok $P)" "Content-Type: application/json")
  [[ -n "$IDEM" ]] && H+=("X-Idempotency-Key: $(uuidgen | tr 'A-Z' 'a-z')")
  if [[ -n "$BODY" ]]; then
    curl -s --max-time 60 -X "$M" "$BASE$PATH_" -H "$H[1]" -H "$H[2]" ${H[3]:+-H "$H[3]"} -d "$BODY" -w "\n%{http_code}"
  else
    curl -s --max-time 60 -X "$M" "$BASE$PATH_" -H "$H[1]" -H "$H[2]" ${H[3]:+-H "$H[3]"} -w "\n%{http_code}"
  fi
}
log() { # log <caseId> <verdict> <evidence>
  echo "| $1 | $2 | $(date '+%H:%M:%S') | $3 |" >> "$LEDGER"
}
apib() { api "$@" | sed '$d'; }
apis() { api "$@" | tail -1; }
