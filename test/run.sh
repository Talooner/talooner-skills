#!/usr/bin/env bash
set -uo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SKILL="$ROOT/talooner-onboard"
VERIFY="$SKILL/scripts/verify.sh"
DECODE="$SKILL/scripts/decode-license.sh"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/talooner-fixtures.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

fail=0
pass() { printf 'PASS %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

make_repo() {
  src=$1
  dst=$2
  mkdir -p "$dst"
  cp -R "$src/." "$dst/"
  git -C "$dst" init -q
  git -C "$dst" -c user.name=fixture -c user.email=fixture@example.com add -A
  git -C "$dst" -c user.name=fixture -c user.email=fixture@example.com commit -qm init
}

expect_verify() {
  name=$1
  repo=$2
  want=$3
  out="$TMP/$name.out"
  if "$VERIFY" --repo "$repo" >"$out" 2>&1; then got=0; else got=1; fi
  if [ "$got" -eq "$want" ]; then
    pass "verify $name"
  else
    cat "$out"
    bad "verify $name (exit $got, want $want)"
  fi
}

make_key() {
  python3 -c 'import base64,json,sys,time
exp=int(time.time())+int(sys.argv[1])
features=sys.argv[2].split(",") if sys.argv[2] else []
data={"v":1,"email":"marker@example.com","exp":exp,"features":features}
payload=base64.urlsafe_b64encode(json.dumps(data).encode()).rstrip(b"=").decode()
print("TLN1.%s.%s" % (payload, "signature"))' "$1" "$2"
}

make_repo "$ROOT/test/fixtures/clean-repo" "$TMP/clean-repo"
expect_verify clean-repo "$TMP/clean-repo" 0

make_repo "$ROOT/test/fixtures/clean-repo" "$TMP/existing-guides"
mkdir -p "$TMP/existing-guides/docs/guides"
cat > "$TMP/existing-guides/docs/guides/deploy.md" <<'MD'
# Deploy in one command

Run it from `/Users/you/project`.
MD
git -C "$TMP/existing-guides" -c user.name=fixture -c user.email=fixture@example.com add -A
git -C "$TMP/existing-guides" -c user.name=fixture -c user.email=fixture@example.com commit -qm guides
expect_verify existing-guides "$TMP/existing-guides" 0

make_repo "$ROOT/test/fixtures/clean-repo" "$TMP/stale-generated"
printf 'one command to onboard\n' > "$TMP/stale-generated/.talooner/notes.md"
git -C "$TMP/stale-generated" -c user.name=fixture -c user.email=fixture@example.com add -A
git -C "$TMP/stale-generated" -c user.name=fixture -c user.email=fixture@example.com commit -qm notes
expect_verify stale-generated "$TMP/stale-generated" 1

make_repo "$ROOT/test/fixtures/dirty-repo" "$TMP/dirty-repo"
printf '\nchanged\n' >> "$TMP/dirty-repo/app/main.go"
expect_verify dirty-repo "$TMP/dirty-repo" 1

make_repo "$ROOT/test/fixtures/clean-repo" "$TMP/missing-rules"
rm -f "$TMP/missing-rules/.talooner/rules.tln" "$TMP/missing-rules/.talooner/rules.tln.test"
git -C "$TMP/missing-rules" -c user.name=fixture -c user.email=fixture@example.com add -A
git -C "$TMP/missing-rules" -c user.name=fixture -c user.email=fixture@example.com commit -qm remove-rules
expect_verify missing-rules "$TMP/missing-rules" 1

make_repo "$ROOT/test/fixtures/clean-repo" "$TMP/failing-test"
sed 's/flagged 1$/flagged 999/' "$TMP/failing-test/.talooner/rules.tln.test" > "$TMP/failing-test/.talooner/rules.tln.test.new"
mv "$TMP/failing-test/.talooner/rules.tln.test.new" "$TMP/failing-test/.talooner/rules.tln.test"
git -C "$TMP/failing-test" -c user.name=fixture -c user.email=fixture@example.com add -A
git -C "$TMP/failing-test" -c user.name=fixture -c user.email=fixture@example.com commit -qm failing-test
expect_verify failing-test "$TMP/failing-test" 1

make_repo "$ROOT/test/fixtures/bad-secret" "$TMP/bad-secret"
fake="TLN1.$(printf '%*s' 40 '' | tr ' ' A).$(printf '%*s' 40 '' | tr ' ' B)"
printf 'placeholder %s\n' "$fake" > "$TMP/bad-secret/.talooner/notes.md"
expect_verify bad-secret "$TMP/bad-secret" 1

make_repo "$ROOT/test/fixtures/clean-repo" "$TMP/bad-ci"
cat > "$TMP/bad-ci/.github/workflows/talooner.yml" <<'YAML'
name: talooner
on:
  pull_request:
jobs:
  rules:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
YAML
git -C "$TMP/bad-ci" -c user.name=fixture -c user.email=fixture@example.com add -A
git -C "$TMP/bad-ci" -c user.name=fixture -c user.email=fixture@example.com commit -qm bad-ci
expect_verify bad-ci "$TMP/bad-ci" 1

key=$(make_key 86400 "ai_review")
out=$(TALOONER_LICENSE_KEY="$key" "$DECODE" 2>/dev/null) && rc=0 || rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^ai_review=yes$' && printf '%s' "$out" | grep -q '^expired=no$'; then
  pass "decode valid with AI review"
else
  bad "decode valid with AI review (exit $rc)"
fi
if printf '%s' "$out" | grep -q 'marker@example.com' || printf '%s' "$out" | grep -q "$key"; then
  bad "decode printed private payload"
else
  pass "decode prints no payload"
fi

key=$(make_key 86400 "qa")
out=$(TALOONER_LICENSE_KEY="$key" "$DECODE" 2>/dev/null) && rc=0 || rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^ai_review=no$'; then
  pass "decode valid without AI review"
else
  bad "decode valid without AI review (exit $rc)"
fi

key=$(make_key -3600 "ai_review")
out=$(TALOONER_LICENSE_KEY="$key" "$DECODE" 2>/dev/null) && rc=0 || rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^expired=yes$'; then
  pass "decode expired"
else
  bad "decode expired (exit $rc)"
fi

env -u TALOONER_LICENSE_KEY -u TALOONER_LICENSE_FILE "$DECODE" >/dev/null 2>&1
if [ $? -eq 2 ]; then pass "decode missing key"; else bad "decode missing key"; fi

TALOONER_LICENSE_KEY="TLN1.not-base64.signature" "$DECODE" >/dev/null 2>&1
if [ $? -eq 2 ]; then pass "decode malformed key"; else bad "decode malformed key"; fi

cp -R "$SKILL" "$TMP/installed-skill"
mkdir -p "$TMP/doctor-repo"
git -C "$TMP/doctor-repo" init -q
printf '# target\n' > "$TMP/doctor-repo/README.md"
git -C "$TMP/doctor-repo" -c user.name=fixture -c user.email=fixture@example.com add -A
git -C "$TMP/doctor-repo" -c user.name=fixture -c user.email=fixture@example.com commit -qm init
if ( cd "$TMP/doctor-repo" && "$TMP/installed-skill/scripts/doctor.sh" --repo "$TMP/doctor-repo" >/dev/null 2>&1 ); then
  pass "doctor runs from an unrelated cwd"
else
  bad "doctor runs from an unrelated cwd"
fi

if [ "$fail" -eq 0 ]; then
  printf 'fixtures: PASS\n'
  exit 0
fi
printf 'fixtures: FAIL\n'
exit 1
