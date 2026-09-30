#!/usr/bin/env bash
# Optional helper: ask the local Ollama "Nimble" decision model one small question.
#
# Sourced by the agent hooks (gradle-agent.sh, route-prompt.sh, check-done.sh, dev.sh). Nimble
# is OPTIONAL: when it is off, missing, cold past the time limit or answers badly, every function
# here fails quietly and the caller does nothing. Nothing here prints except answers.
#
#   NIMBLE_HOOKS=0     turn every Nimble hook off
#   NIMBLE_URL         default http://127.0.0.1:11434
#   NIMBLE_MODEL       default nimble
#
#   nimble_ask <max_seconds> <questions_json>  < state_text
#       POST /v1/systemone; prints the response JSON on one line. Returns 1 on any failure.
#       The state is made ASCII-safe, JSON-escaped and cut to its TAIL so the request fits
#       Nimble's context (the end of a log is where the failure is).
#   nimble_get <response_json> <question_key> <field>
#       field = choice | confidence | noul | p   (p = probability of the chosen label)
#       Prints the value, or nothing (return 1) when it is missing.
#   nimble_ge <number> <threshold>   true when number >= threshold
#
# Bash + curl + sed + awk + tr only (no jq, no python). CRLF-safe.

NIMBLE_URL="${NIMBLE_URL:-http://127.0.0.1:11434}"
NIMBLE_MODEL="${NIMBLE_MODEL:-nimble}"
# State budget in bytes. The request limit is 64 KiB, but Nimble's context (8194 tokens) binds
# first: ~4 bytes/token for Gradle logs, ~2.5 for path-heavy text. nimble_ask retries smaller
# when the server reports too many tokens.
NIMBLE_MAX_BYTES="${NIMBLE_MAX_BYTES:-24000}"

nimble_enabled() {
  [ "${NIMBLE_HOOKS:-1}" != "0" ] && command -v curl >/dev/null 2>&1
}

# stdin -> JSON string body (no surrounding quotes). CR is dropped, tabs become spaces, every
# other control byte and every non-ASCII byte becomes '?', then \ and " are escaped and lines
# are joined with \n.
_nimble_escape() {
  LC_ALL=C tr -d '\r' | LC_ALL=C tr '\11' ' ' | LC_ALL=C tr -c '\12\40-\176' '?' \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | awk 'NR > 1 { printf "%s", "\\" "n" } { printf "%s", $0 }'
}

nimble_ask() {
  nimble_enabled || return 1
  local max_time="$1" questions="$2" raw esc budget keep resp try n m
  budget=$((NIMBLE_MAX_BYTES - ${#questions}))
  [ "$budget" -gt 1000 ] || return 1
  # NUL bytes cannot live in a shell variable; drop them before capturing.
  raw=$(tail -c "$budget" | tr -d '\000')
  keep=$budget
  for try in 1 2 3; do
    # Keep the tail; shrink until the escaped text fits (escaping can only grow it).
    while :; do
      esc=$(printf '%s' "$raw" | tail -c "$keep" | _nimble_escape)
      [ "${#esc}" -le "$budget" ] && break
      keep=$((keep * 3 / 4))
      [ "$keep" -gt 500 ] || return 1
    done
    resp=$(printf '{"model":"%s","keep_alive":"30m","state":"%s","questions":%s}' \
        "$NIMBLE_MODEL" "$esc" "$questions" \
      | curl -s --connect-timeout "${NIMBLE_CONNECT_TIMEOUT:-0.5}" -m "$max_time" \
          -H 'Content-Type: application/json' --data-binary @- \
          "${NIMBLE_URL%/}/v1/systemone" 2>/dev/null) || return 1
    resp=$(printf '%s' "$resp" | tr -d '\r\n')
    case "$resp" in *'"answers"'*) printf '%s\n' "$resp"; return 0 ;; esac
    # Over the context: "prompt 0 has N tokens; expected 1-M tokens". Dense text (paths,
    # stack traces) can pass the byte budget; cut to ~85% of M/N and retry.
    n=$(printf '%s' "$resp" | sed -n 's/.* has \([0-9][0-9]*\) tokens.*/\1/p')
    m=$(printf '%s' "$resp" | sed -n 's/.*expected [0-9]*[^0-9]*\([0-9][0-9]*\).*/\1/p')
    [ -n "$n" ] && [ -n "$m" ] && [ "$n" -gt 0 ] || return 1
    keep=$((keep * m * 85 / (n * 100)))
    [ "$keep" -gt 500 ] || return 1
    budget=$keep
  done
  return 1
}

nimble_get() {
  local out
  out=$(printf '%s' "$1" | awk -v key="$2" -v field="$3" '
    {
      s = $0
      a = index(s, "\"answers\""); if (!a) exit 1
      s = substr(s, a)
      k = index(s, "\"" key "\":{"); if (!k) exit 1
      s = substr(s, k + length(key) + 3)
      if (field == "choice" || field == "p") {
        if (!match(s, /"choice":"[^"]*"/)) exit 1
        c = substr(s, RSTART + 10, RLENGTH - 11)
        if (field == "choice") { print c; exit 0 }
        if (!match(s, "\"" c "\":[0-9.eE+-]+")) exit 1
        print substr(s, RSTART + length(c) + 3, RLENGTH - length(c) - 3); exit 0
      }
      if (!match(s, "\"" field "\":[0-9.eE+-]+")) exit 1
      print substr(s, RSTART + length(field) + 3, RLENGTH - length(field) - 3)
    }') || return 1
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

nimble_ge() {
  awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 >= b + 0) }'
}
