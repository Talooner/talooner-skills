#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

key=""
if [ -n "${TALOONER_LICENSE_KEY:-}" ]; then
  key=$TALOONER_LICENSE_KEY
elif [ -n "${TALOONER_LICENSE_FILE:-}" ]; then
  if [ -r "$TALOONER_LICENSE_FILE" ]; then
    key=$(tr -d '\r\n' < "$TALOONER_LICENSE_FILE")
  else
    printf 'format=bad\n'
    printf 'expired=unknown\n'
    printf 'expires=unknown\n'
    printf 'ai_review=unknown\n'
    printf 'reason=license file is unreadable\n' >&2
    exit 2
  fi
else
  printf 'format=bad\n'
  printf 'expired=unknown\n'
  printf 'expires=unknown\n'
  printf 'ai_review=unknown\n'
  printf 'reason=license key is missing\n' >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  printf 'format=unknown\n'
  printf 'expired=unknown\n'
  printf 'expires=unknown\n'
  printf 'ai_review=unknown\n'
  printf 'reason=python3 is not available; confirm your current key on your license page\n' >&2
  exit 2
fi

printf '%s' "$key" | python3 -c '
import base64, datetime, json, sys

key = sys.stdin.read().strip()
if not key.startswith("TLN1."):
    sys.stdout.write("format=bad\nexpired=unknown\nexpires=unknown\nai_review=unknown\n")
    sys.stderr.write("reason=key does not start with TLN1.\n")
    sys.exit(2)

parts = key.split(".")
if len(parts) != 3 or not parts[1] or not parts[2]:
    sys.stdout.write("format=bad\nexpired=unknown\nexpires=unknown\nai_review=unknown\n")
    sys.stderr.write("reason=key is not TLN1.<payload>.<signature>\n")
    sys.exit(2)

payload = parts[1]
try:
    raw = base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4))
    data = json.loads(raw.decode("utf-8"))
except Exception:
    sys.stdout.write("format=bad\nexpired=unknown\nexpires=unknown\nai_review=unknown\n")
    sys.stderr.write("reason=payload is not base64url JSON\n")
    sys.exit(2)

exp = data.get("exp")
features = data.get("features")
expired = "unknown"
expires = "unknown"
if isinstance(exp, (int, float)) and exp > 0:
    when = datetime.datetime.fromtimestamp(exp, datetime.timezone.utc)
    expires = when.strftime("%Y-%m-%d")
    expired = "yes" if when <= datetime.datetime.now(datetime.timezone.utc) else "no"

if isinstance(features, list):
    ai = "yes" if "ai_review" in features else "no"
else:
    ai = "unknown"

sys.stdout.write("format=ok\n")
sys.stdout.write("expired=%s\n" % expired)
sys.stdout.write("expires=%s\n" % expires)
sys.stdout.write("ai_review=%s\n" % ai)
'
