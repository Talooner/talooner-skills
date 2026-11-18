#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

repo=$(repo_arg "$@")
cd "$repo" 2>/dev/null || die "cannot enter $repo"

fail=0
root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
cd "$root" || die "cannot enter $root"
branch=$(git branch --show-current 2>/dev/null || true)
remote=$(git remote get-url origin 2>/dev/null || echo "none")
host="unknown"
case "$remote" in
  *github.com*) host="github" ;;
  *gitlab*) host="gitlab" ;;
  none) host="none" ;;
  *) host="self-managed" ;;
esac
dirty=no
[ -n "$(git status --porcelain 2>/dev/null)" ] && dirty=yes

printf 'repo=%s\n' "$root"
printf 'remote=%s\n' "$remote"
printf 'host=%s\n' "$host"
printf 'branch=%s\n' "${branch:-(detached)}"
printf 'dirty=%s\n' "$dirty"
[ "$dirty" = no ] || { warn "working tree is dirty; commit or stash before onboarding"; fail=1; }

found=
for f in Gemfile package.json go.mod pyproject.toml requirements.txt composer.json pom.xml build.gradle build.gradle.kts Cargo.toml; do
  [ -f "$f" ] && found="$found $f"
done
printf 'manifests=%s\n' "${found:-none}"

stack=other
if [ -f Gemfile ] && grep -Eq "^[[:space:]]*gem ['\"]rails['\"]" Gemfile; then stack=rails; fi
printf 'stack=%s\n' "$stack"

review=none
if [ -f .talooner/rules.tln ] || [ -d .talooner/rules ]; then review=rules; fi
for f in $(ci_files); do
  if grep -Eq 'talooner-runner:|talooner-step' "$f"; then review="$review+ci($f)"; fi
done
printf 'talooner_review=%s\n' "$review"

if [ -d .talooner/qa ]; then
  blocks=$(find .talooner/qa/blocks -name '*.feature' 2>/dev/null | wc -l | tr -d ' ')
  areas=$(find .talooner/qa/blocks -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's#.*/##' | tr '\n' ' ')
  printf 'qa_catalog=.talooner/qa (%s feature files; areas: %s)\n' "$blocks" "${areas:-none}"
  [ -f .talooner/qa/config.yaml ] && printf 'qa_config=.talooner/qa/config.yaml\n' || printf 'qa_config=none\n'
else
  printf 'qa_catalog=none\n'
fi

hooks=none
if [ -f Gemfile ] && grep -q 'talooner-qa-rails' Gemfile; then hooks="talooner-qa-rails"; fi
mount=$(grep -rln '__qa' config/routes.rb app src lib internal 2>/dev/null | head -3 | tr '\n' ' ')
[ -n "$mount" ] && hooks="$hooks; /__qa in: $mount"
printf 'qa_hooks=%s\n' "$hooks"

guides=$(find docs -maxdepth 3 -name '*.md' 2>/dev/null | grep -Ei 'role|permission|access|authori' | head -5 | tr '\n' ' ')
printf 'role_docs=%s\n' "${guides:-none}"

qa_ci=none
for f in $(ci_files); do
  if grep -Eq 'talooner-qa run|talooner-step qa| qa --out' "$f"; then qa_ci="$f"; fi
done
printf 'ci_files=%s\n' "$(ci_files | tr '\n' ' ')"
printf 'qa_ci=%s\n' "$qa_ci"

for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml Dockerfile; do
  [ -f "$f" ] && printf 'container_file=%s\n' "$f"
done

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  printf 'docker=ok\n'
  if docker run --rm --entrypoint talooner-qa "$RUNNER_IMAGE" version >/dev/null 2>&1; then
    printf 'runner_image=%s ok\n' "$RUNNER_IMAGE"
  else
    printf 'runner_image=%s unavailable\n' "$RUNNER_IMAGE"
    fail=1
  fi
else
  printf 'docker=missing\n'
  fail=1
fi
printf 'qa_image=%s (linux/amd64; used by the CI run job only)\n' "$QA_IMAGE"

for v in TALOONER_LICENSE_KEY TALOONER_QA_HOOK_TOKEN TALOONER_QA_PREVIEW_URL TALOONER_METRICS_PUSH_URL; do
  if [ -n "${!v:-}" ]; then printf 'env_%s=set\n' "$v"; else printf 'env_%s=unset\n' "$v"; fi
done

exit "$fail"
