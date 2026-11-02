#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"
RUNNER_IMAGE_GH="${RUNNER_IMAGE}-gh"

repo=$PWD
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo=${2:-}; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

cd "$repo" 2>/dev/null || die "cannot enter $repo"
git rev-parse --show-toplevel >/dev/null 2>&1 || die "not inside a git repository"

fail=0
ok() { printf 'PASS %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

dirty=$(git status --porcelain 2>/dev/null)
if [ -z "$dirty" ]; then
  ok "working tree is clean"
else
  unexpected=
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    path=${line#?? }
    path=${path#* -> }
    case "$path" in
      .talooner/*|docs/guides/*|.github/workflows/talooner.yml|.github/workflows/talooner.yaml|.gitlab-ci.yml) ;;
      *) unexpected="$unexpected $path" ;;
    esac
  done <<EOF
$dirty
EOF
  if [ -z "$unexpected" ]; then
    ok "working tree changes are limited to onboarding files"
  else
    bad "unexpected working tree changes:$unexpected"
  fi
fi

if [ -f .talooner/onboarding.md ]; then ok "onboarding spec exists"; else bad "missing .talooner/onboarding.md"; fi

has_rules=no
[ -f .talooner/rules.tln ] && has_rules=yes
for f in .talooner/rules/*.tln; do [ -f "$f" ] && has_rules=yes; done
if [ "$has_rules" = yes ]; then
  ok "rules exist"
else
  bad "missing .talooner/rules.tln or .talooner/rules/*.tln"
fi

has_tests=no
[ -f .talooner/rules.tln.test ] && has_tests=yes
for f in .talooner/rules/*.tln.test; do [ -f "$f" ] && has_tests=yes; done
if [ "$has_tests" = yes ]; then
  ok "rule tests exist"
else
  bad "missing rule tests"
fi

ci_github=
for f in .github/workflows/talooner.yml .github/workflows/talooner.yaml; do
  [ -f "$f" ] && ci_github=$f
done
ci_gitlab=
[ -f .gitlab-ci.yml ] && ci_gitlab=.gitlab-ci.yml
if [ -n "$ci_github" ] || [ -n "$ci_gitlab" ]; then
  ok "CI file exists"
else
  bad "missing .github/workflows/talooner.yml or .gitlab-ci.yml"
fi

for f in .talooner/config.yaml .talooner/teams.yaml .talooner/architecture.yaml .talooner/review.md; do
  if [ -f "$f" ]; then
    ok "optional file exists: $f"
  fi
done

out=$(mktemp)
if docker run --rm --user "$(id -u):$(id -g)" \
  -v "$PWD:/repo" -w /repo --entrypoint tln \
  "$RUNNER_IMAGE" test .talooner/ >"$out" 2>&1; then
  ok "tln test .talooner/"
else
  cat "$out"
  bad "tln test .talooner/"
fi
rm -f "$out"

provider=${TALOONER_PROVIDER:-}
token=
case "$provider" in
  github) token=${GITHUB_TOKEN:-} ;;
  gitlab) token=${GITLAB_TOKEN:-} ;;
esac
if [ -n "$provider" ] && [ -n "$token" ]; then
  out=$(mktemp)
  if docker run --rm \
    -e TALOONER_LICENSE_KEY -e TALOONER_PROVIDER \
    -e GITHUB_TOKEN -e GITLAB_TOKEN \
    -e TALOONER_MODEL_BASE_URL -e TALOONER_MODEL -e TALOONER_MODEL_API_KEY \
    -e ANTHROPIC_API_KEY -e OPENAI_API_KEY \
    -e CDM_URL -e CDM_TOKEN -e CDM_MODEL \
    "$RUNNER_IMAGE" config >"$out" 2>&1; then
    ok "runner config sanity"
  else
    cat "$out"
    bad "runner config sanity"
  fi
  rm -f "$out"
else
  printf 'SKIP runner config sanity (provider or forge token not set)\n'
fi

if [ -n "$ci_github" ]; then
  if grep -Eq '^  rules:' "$ci_github"; then ok "GitHub rules job"; else bad "GitHub rules job missing"; fi
  if grep -Eq '^  review:' "$ci_github"; then ok "GitHub review job"; else bad "GitHub review job missing"; fi
  if grep -q "docker://$RUNNER_IMAGE_GH" "$ci_github"; then ok "GitHub review uses pinned -gh image"; else bad "GitHub review image is not $RUNNER_IMAGE_GH"; fi
  if grep -q -- "--entrypoint tln $RUNNER_IMAGE test" "$ci_github"; then ok "GitHub rules use pinned image"; else bad "GitHub rules image is not $RUNNER_IMAGE"; fi
  if grep -q 'TALOONER_LICENSE_KEY' "$ci_github"; then ok "GitHub license key is wired"; else bad "GitHub license key is not wired"; fi
fi

if [ -n "$ci_gitlab" ]; then
  if grep -Eq '^talooner-rules:' "$ci_gitlab"; then ok "GitLab rules job"; else bad "GitLab rules job missing"; fi
  if grep -Eq '^talooner-review:' "$ci_gitlab"; then ok "GitLab review job"; else bad "GitLab review job missing"; fi
  if grep -q 'entrypoint: \[""\]' "$ci_gitlab"; then ok "GitLab entrypoint is empty"; else bad "GitLab entrypoint is not empty"; fi
  if grep -Eq 'needs: \[talooner-rules\]' "$ci_gitlab"; then ok "GitLab review needs rules"; else bad "GitLab review does not need talooner-rules"; fi
  if grep -q "$RUNNER_IMAGE" "$ci_gitlab"; then ok "GitLab uses pinned image"; else bad "GitLab does not use $RUNNER_IMAGE"; fi
  if grep -Eq '^talooner:' "$ci_gitlab"; then
    bad "GitLab has a job named talooner"
  else
    ok "GitLab has no job named talooner"
  fi
fi

candidates=$(mktemp)
{
  [ -d .talooner ] && find .talooner -type f
  [ -n "$ci_github" ] && printf '%s\n' "$ci_github"
  [ -n "$ci_gitlab" ] && printf '%s\n' "$ci_gitlab"
  [ -d docs/guides ] && find docs/guides -type f
} | sort -u > "$candidates"

secrets=0
private=0
copy=0
localpath=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  if ! secret_shapes_match < "$f"; then
    printf '  %s\n' "$f"
    secrets=1
  fi
  if ! private_paths_match < "$f"; then
    printf '  %s\n' "$f"
    private=1
  fi
  if ! removed_copy_match < "$f"; then
    printf '  %s\n' "$f"
    copy=1
  fi
  if ! local_path_match < "$f"; then
    printf '  %s\n' "$f"
    localpath=1
  fi
done < "$candidates"
rm -f "$candidates"

if [ "$secrets" -eq 0 ]; then ok "no token shapes in onboarding files"; else bad "token shapes in onboarding files"; fi
if [ "$private" -eq 0 ]; then ok "no private paths in onboarding files"; else bad "private paths in onboarding files"; fi
if [ "$copy" -eq 0 ]; then ok "no removed commands or setup phrases"; else bad "removed commands or setup phrases in onboarding files"; fi
if [ "$localpath" -eq 0 ]; then ok "no local absolute paths"; else bad "local absolute paths in onboarding files"; fi

if [ "$fail" -eq 0 ]; then
  printf 'verify: PASS\n'
  exit 0
fi
printf 'verify: FAIL\n'
exit 1
