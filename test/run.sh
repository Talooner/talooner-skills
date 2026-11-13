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

make_repo "$ROOT/test/fixtures/split-rules" "$TMP/split-rules"
expect_verify split-rules "$TMP/split-rules" 0

make_repo "$ROOT/test/fixtures/split-rules" "$TMP/split-no-script"
mv "$TMP/split-no-script/.talooner/test-rules.sh" "$TMP/split-no-script/test-rules.removed"
git -C "$TMP/split-no-script" -c user.name=fixture -c user.email=fixture@example.com add -A
git -C "$TMP/split-no-script" -c user.name=fixture -c user.email=fixture@example.com commit -qm split-no-script
expect_verify split-no-script "$TMP/split-no-script" 1
if grep -q 'test-rules.sh' "$TMP/split-no-script.out"; then
  pass "verify names the missing test-rules.sh"
else
  bad "verify does not name the missing test-rules.sh"
fi

make_repo "$ROOT/test/fixtures/clean-repo" "$TMP/missing-guide"
mv "$TMP/missing-guide/docs/guides/app.md" "$TMP/missing-guide/docs/guides/app.removed"
git -C "$TMP/missing-guide" -c user.name=fixture -c user.email=fixture@example.com add -A
git -C "$TMP/missing-guide" -c user.name=fixture -c user.email=fixture@example.com commit -qm missing-guide
expect_verify missing-guide "$TMP/missing-guide" 1
if grep -q 'missing doc_ref: docs/guides/app.md' "$TMP/missing-guide.out"; then
  pass "verify names the missing doc_ref"
else
  bad "verify does not name the missing doc_ref"
fi

make_repo "$ROOT/test/fixtures/clean-repo" "$TMP/flat-guide"
cat > "$TMP/flat-guide/docs/guides/app.md" <<'MD'
# app guide

### Return errors, do not log them in handlers

A handler returns the error to the caller.
MD
git -C "$TMP/flat-guide" -c user.name=fixture -c user.email=fixture@example.com add -A
git -C "$TMP/flat-guide" -c user.name=fixture -c user.email=fixture@example.com commit -qm flat-guide
expect_verify flat-guide "$TMP/flat-guide" 1
if grep -q 'no ### rule under a ## heading' "$TMP/flat-guide.out"; then
  pass "verify names a guide whose ### rules have no ## heading"
else
  bad "verify does not name a guide whose ### rules have no ## heading"
fi

make_repo "$ROOT/test/fixtures/clean-repo" "$TMP/applies-empty"
cat > "$TMP/applies-empty/docs/guides/app.md" <<'MD'
# app guide

## Handlers

Return every error to the caller.

### Logging

A handler never logs a request body.

Applies to: the handler paths.
MD
git -C "$TMP/applies-empty" -c user.name=fixture -c user.email=fixture@example.com add -A
git -C "$TMP/applies-empty" -c user.name=fixture -c user.email=fixture@example.com commit -qm applies-empty
expect_verify applies-empty "$TMP/applies-empty" 0
if grep -q 'Applies to: line with no backticked path' "$TMP/applies-empty.out"; then
  pass "verify warns on an Applies to: line with no path"
else
  bad "verify does not warn on an Applies to: line with no path"
fi

make_repo "$ROOT/test/fixtures/clean-repo" "$TMP/h2-guide"
cat > "$TMP/h2-guide/docs/guides/app.md" <<'MD'
# app guide

## Return errors, do not log them in handlers

A handler returns the error to the caller and logs once at the edge.

## Never put request bodies in a log line

Request bodies carry customer data.
MD
git -C "$TMP/h2-guide" -c user.name=fixture -c user.email=fixture@example.com add -A
git -C "$TMP/h2-guide" -c user.name=fixture -c user.email=fixture@example.com commit -qm h2-guide
expect_verify h2-guide "$TMP/h2-guide" 0

out="$TMP/clean-repo.incomplete"
if "$VERIFY" --repo "$TMP/clean-repo" >"$out" 2>&1 && grep -q '^verify: INCOMPLETE' "$out"; then
  pass "verify reports INCOMPLETE without credentials"
else
  cat "$out"
  bad "verify reports INCOMPLETE without credentials"
fi

if "$VERIFY" --repo "$TMP/clean-repo" --strict >/dev/null 2>&1; then
  bad "verify --strict fails without credentials"
else
  pass "verify --strict fails without credentials"
fi

mkdir -p "$TMP/ignored-config"
printf '*.test\nconfig.yaml\n' > "$TMP/ignored-config/.gitignore"
cp -R "$ROOT/test/fixtures/clean-repo/." "$TMP/ignored-config/"
git -C "$TMP/ignored-config" init -q
git -C "$TMP/ignored-config" -c user.name=fixture -c user.email=fixture@example.com add -A
git -C "$TMP/ignored-config" -c user.name=fixture -c user.email=fixture@example.com commit -qm init
expect_verify ignored-config "$TMP/ignored-config" 1

make_repo "$ROOT/test/fixtures/clean-repo" "$TMP/legacy-rules"
mkdir -p "$TMP/legacy-rules/.github/talooner"
cp "$ROOT/test/fixtures/clean-repo/.talooner/rules.tln" "$TMP/legacy-rules/.github/talooner/rules.tln"
git -C "$TMP/legacy-rules" -c user.name=fixture -c user.email=fixture@example.com add -A
git -C "$TMP/legacy-rules" -c user.name=fixture -c user.email=fixture@example.com commit -qm legacy
expect_verify legacy-rules "$TMP/legacy-rules" 1

make_repo "$ROOT/test/fixtures/clean-repo" "$TMP/requires-without-require"
cat >> "$TMP/requires-without-require/.talooner/rules.tln" <<'TLN'

rule "Bad require" {
  for records where type == "pr"
  requires "review.owners"
  do block "pr.merge"
}
TLN
git -C "$TMP/requires-without-require" -c user.name=fixture -c user.email=fixture@example.com add -A
git -C "$TMP/requires-without-require" -c user.name=fixture -c user.email=fixture@example.com commit -qm bad-require
expect_verify requires-without-require "$TMP/requires-without-require" 1

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

make_repo "$ROOT/test/fixtures/clean-repo" "$TMP/missing-architecture"
rm -f "$TMP/missing-architecture/.talooner/architecture.yaml"
git -C "$TMP/missing-architecture" -c user.name=fixture -c user.email=fixture@example.com add -A
git -C "$TMP/missing-architecture" -c user.name=fixture -c user.email=fixture@example.com commit -qm remove-architecture
expect_verify missing-architecture "$TMP/missing-architecture" 1
if grep -q 'missing .talooner/architecture.yaml' "$TMP/missing-architecture.out"; then
  pass "verify names the missing architecture.yaml"
else
  bad "verify does not name the missing architecture.yaml"
fi

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

make_repo "$ROOT/test/fixtures/clean-repo" "$TMP/gitlab-ci"
rm -f "$TMP/gitlab-ci/.github/workflows/talooner.yml"
cat > "$TMP/gitlab-ci.yml" <<'YAML'
talooner-command:
  image:
    name: ghcr.io/talooner/talooner-runner:1.2.1
    entrypoint: [""]
  rules:
    - if: $CI_PIPELINE_SOURCE == "trigger"
  script:
    - talooner-step note-env "$TRIGGER_PAYLOAD" > talooner.env

talooner-rules:
  image:
    name: ghcr.io/talooner/talooner-runner:1.2.1
    entrypoint: [""]
  script:
    - tln test .talooner/

talooner-review:
  image:
    name: ghcr.io/talooner/talooner-runner:1.2.1-gh
    entrypoint: [""]
  needs: [talooner-rules]
  script:
    - talooner review
  variables:
    TALOONER_LICENSE_KEY: $TALOONER_LICENSE_KEY
    ANTHROPIC_API_KEY: $ANTHROPIC_API_KEY
    CDM_URL: $CDM_URL
    CDM_TOKEN: $CDM_TOKEN
YAML
cp "$TMP/gitlab-ci.yml" "$TMP/gitlab-ci/.gitlab-ci.yml"
git -C "$TMP/gitlab-ci" -c user.name=fixture -c user.email=fixture@example.com add -A
git -C "$TMP/gitlab-ci" -c user.name=fixture -c user.email=fixture@example.com commit -qm gitlab-ci
expect_verify gitlab-ci "$TMP/gitlab-ci" 0

make_repo "$ROOT/test/fixtures/clean-repo" "$TMP/gitlab-missing-model"
rm -f "$TMP/gitlab-missing-model/.github/workflows/talooner.yml"
grep -Ev 'ANTHROPIC_API_KEY|CDM_' "$TMP/gitlab-ci.yml" > "$TMP/gitlab-missing-model/.gitlab-ci.yml"
git -C "$TMP/gitlab-missing-model" -c user.name=fixture -c user.email=fixture@example.com add -A
git -C "$TMP/gitlab-missing-model" -c user.name=fixture -c user.email=fixture@example.com commit -qm gitlab-missing-model
expect_verify gitlab-missing-model "$TMP/gitlab-missing-model" 1

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
mkdir -p "$TMP/doctor-repo/.github/workflows" "$TMP/doctor-repo/.github/talooner"
printf '# target\n' > "$TMP/doctor-repo/README.md"
printf 'name: ci\n' > "$TMP/doctor-repo/.github/workflows/ci.yml"
printf 'rule "legacy" { for records where type == "pr" do comment "pr" "x" }\n' > "$TMP/doctor-repo/.github/talooner/rules.tln"
printf 'config.yaml\n' > "$TMP/doctor-repo/.gitignore"
git -C "$TMP/doctor-repo" init -q
git -C "$TMP/doctor-repo" -c user.name=fixture -c user.email=fixture@example.com add -A
git -C "$TMP/doctor-repo" -c user.name=fixture -c user.email=fixture@example.com commit -qm init
doctor_out="$TMP/doctor.out"
if ( cd "$TMP/doctor-repo" && "$TMP/installed-skill/scripts/doctor.sh" --repo "$TMP/doctor-repo" >"$doctor_out" 2>&1 ) \
  && grep -q 'legacy_talooner_files=.*\.github/talooner/rules\.tln' "$doctor_out" \
  && grep -q 'ignored_targets=.*\.talooner/config\.yaml' "$doctor_out" \
  && grep -q 'existing_ci_files=.*\.github/workflows/ci\.yml' "$doctor_out"; then
  pass "doctor runs from an unrelated cwd and reports legacy, ignored and existing CI"
else
  cat "$doctor_out"
  bad "doctor reports legacy, ignored and existing CI"
fi

if [ "$fail" -eq 0 ]; then
  printf 'fixtures: PASS\n'
  exit 0
fi
printf 'fixtures: FAIL\n'
exit 1
