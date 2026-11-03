#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

repo=${1:-}
if [ "$repo" = "--repo" ]; then
  repo=${2:-}
fi
[ -n "$repo" ] || repo=$PWD
cd "$repo" 2>/dev/null || die "cannot enter $repo"

fail=0
root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
branch=$(git branch --show-current 2>/dev/null || true)
[ -n "$branch" ] || branch="(detached)"

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
printf 'branch=%s\n' "$branch"
printf 'dirty=%s\n' "$dirty"
[ "$dirty" = no ] || { warn "working tree is dirty; commit or stash before onboarding"; fail=1; }

printf 'talooner_files='
found=
for f in .talooner/rules.tln .talooner/onboarding.md .talooner/config.yaml .talooner/teams.yaml .talooner/architecture.yaml .talooner/review.md; do
  [ -f "$f" ] && found="$found $f"
done
if [ -d .talooner/rules ]; then
  for f in .talooner/rules/*.tln; do [ -f "$f" ] && found="$found $f"; done
fi
printf '%s\n' "${found:-none}"

split=no
for f in .talooner/rules/*.tln; do [ -f "$f" ] && split=yes; done
printf 'split_ruleset=%s\n' "$split"
if [ -f .talooner/test-rules.sh ]; then
  printf 'rules_test_script=.talooner/test-rules.sh\n'
else
  printf 'rules_test_script=none\n'
fi

printf 'manifests='
found=
for f in go.mod package.json Gemfile pyproject.toml requirements.txt Cargo.toml pom.xml build.gradle build.gradle.kts composer.json; do
  [ -f "$f" ] && found="$found $f"
done
printf '%s\n' "${found:-none}"

printf 'ci_files='
found=
for f in .github/workflows/talooner.yml .github/workflows/talooner.yaml .gitlab-ci.yml; do
  [ -f "$f" ] && found="$found $f"
done
printf '%s\n' "${found:-none}"

printf 'existing_ci_files='
found=
for f in .github/workflows/*.yml .github/workflows/*.yaml .gitlab-ci.yml; do
  [ -f "$f" ] && found="$found $f"
done
printf '%s\n' "${found:-none}"

printf 'legacy_talooner_files='
found=
for f in .github/talooner/rules.tln .github/talooner/config.yaml .github/talooner/teams.yaml .github/talooner/architecture.yaml .github/talooner/review.md; do
  [ -f "$f" ] && found="$found $f"
done
for f in .github/talooner/rules/*.tln; do [ -f "$f" ] && found="$found $f"; done
printf '%s\n' "${found:-none}"

printf 'ignored_targets='
found=
for f in .talooner/onboarding.md .talooner/rules.tln .talooner/rules.tln.test .talooner/test-rules.sh .talooner/rules/_predicates.tln .talooner/rules/example.tln .talooner/config.yaml .talooner/teams.yaml .talooner/architecture.yaml .talooner/review.md .github/workflows/talooner.yml docs/guides/example.md; do
  if git check-ignore -q --no-index "$f" 2>/dev/null; then found="$found $f"; fi
done
printf '%s\n' "${found:-none}"

for cmd in git docker gh glab; do
  if command -v "$cmd" >/dev/null 2>&1; then printf '%s=yes\n' "$cmd"; else printf '%s=no\n' "$cmd"; fi
done

command -v docker >/dev/null 2>&1 || { warn "docker is required"; fail=1; }

printf 'runner_image=%s\n' "$RUNNER_IMAGE"
if command -v docker >/dev/null 2>&1; then
  if docker run --rm "$RUNNER_IMAGE" version >/dev/null 2>&1; then
    printf 'runner_image_status=ok\n'
  else
    printf 'runner_image_status=failed\n'
    warn "cannot run $RUNNER_IMAGE"
    fail=1
  fi
fi

[ -n "${TALOONER_LICENSE_KEY:-}" ] && printf 'license_key=present\n' || printf 'license_key=absent\n'
model=absent
[ -n "${ANTHROPIC_API_KEY:-}" ] && model=present
[ -n "${OPENAI_API_KEY:-}" ] && model=present
[ -n "${TALOONER_MODEL_API_KEY:-}" ] && model=present
printf 'model_key=%s\n' "$model"
cdm=absent
[ -n "${CDM_URL:-}" ] && [ -n "${CDM_TOKEN:-}" ] && cdm=present
printf 'cdm=%s\n' "$cdm"

count=0
if [ -d .talooner ]; then
  count=$(find .talooner -name '*.tln.test' -type f | wc -l | tr -d ' ')
fi
printf 'tln_test_files=%s\n' "$count"

exit "$fail"
