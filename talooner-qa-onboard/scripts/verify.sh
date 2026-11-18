#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

strict=0
repo=
while [ $# -gt 0 ]; do
  case "$1" in
    --strict) strict=1 ;;
    --repo) repo=${2:-}; shift ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done
[ -n "$repo" ] || repo=$PWD
cd "$repo" 2>/dev/null || die "cannot enter $repo"
root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
cd "$root" || die "cannot enter $root"

fail=0
incomplete=0
pass() { printf 'PASS %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
note() { printf 'WARN %s\n' "$1"; }

cfg=.talooner/qa/config.yaml
if [ -f "$cfg" ]; then pass "$cfg exists"; else bad "$cfg is missing"; fi

blocks=$(find .talooner/qa/blocks -name '*.feature' 2>/dev/null | sort)
if [ -n "$blocks" ]; then
  pass "$(printf '%s\n' "$blocks" | wc -l | tr -d ' ') feature files in .talooner/qa/blocks"
else
  bad "no .talooner/qa/blocks/<area>/*.feature: QA would report every change as not covered"
fi

# The catalog as talooner-qa reads it in CI: every problem with file:line.
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  out=$(docker run --rm -v "$root:/repo:ro" -w /repo --entrypoint talooner-qa "$RUNNER_IMAGE" catalog validate 2>&1)
  code=$?
  if [ "$code" -ne 0 ]; then
    printf '%s\n' "$out"
    bad "talooner-qa catalog validate"
  elif printf '%s\n' "$out" | grep -q 'no blocks'; then
    printf '%s\n' "$out"
    bad "talooner-qa catalog validate sees no blocks (with Docker Desktop, share the repository's folder)"
  else
    printf '%s\n' "$out" | tail -2
    pass "talooner-qa catalog validate"
  fi
else
  note "docker is unavailable; the catalog was not validated"
  incomplete=1
fi

if [ -f "$cfg" ]; then
  guide=$(sed -n 's/^guide:[[:space:]]*//p' "$cfg" | sed 's/[[:space:]]*#.*//; s/^["'\'']//; s/["'\'']$//' | head -1)
  if [ -z "$guide" ]; then
    bad "$cfg has no guide: every role question would come back unclear"
  elif [ -f "$guide" ]; then
    pass "guide $guide exists"
  else
    bad "guide $guide does not exist"
  fi
fi

# A block without a page opens nothing: compose cannot place it on the PR's page.
if [ -n "$blocks" ]; then
  # shellcheck disable=SC2016 # the variables are perl ones
  nopage=$(printf '%s\n' "$blocks" | xargs perl -ne '
    if (/^\s*Block:\s*(.+?)\s*$/) { print "$ARGV: $1\n" unless $tags =~ /\@page:/; $tags = "" }
    elsif (/^\s*\@/) { $tags .= $_ }
    elsif (/\S/) { $tags = "" }
    close ARGV if eof;
  ')
  if [ -z "$nopage" ]; then pass "every block has a @page:"; else printf '%s\n' "$nopage"; note "blocks without @page: open no page"; fi
fi

ci=
for f in $(ci_files); do
  if grep -Eq 'talooner-qa run' "$f"; then ci="$ci $f"; fi
done
if [ -z "$ci" ]; then
  bad "no CI job runs talooner-qa run"
else
  for f in $ci; do
    if grep -Eq 'talooner-step qa|talooner-runner:[^[:space:]]+[[:space:]]+qa[[:space:]]' "$f"; then pass "$f composes (talooner-step qa)"; else bad "$f runs scenarios but composes none (talooner-step qa)"; fi
    if grep -q 'catalog validate' "$f"; then pass "$f validates the catalog"; else bad "$f does not run talooner-qa catalog validate"; fi
    if grep -Fq "$RUNNER_IMAGE" "$f"; then pass "$f pins $RUNNER_IMAGE"; else bad "$f does not use $RUNNER_IMAGE"; fi
    if grep -Fq "$QA_IMAGE" "$f"; then pass "$f pins $QA_IMAGE"; else bad "$f does not use $QA_IMAGE"; fi
    if grep -Eq 'talooner-(runner|qa):latest' "$f"; then bad "$f uses a :latest Talooner image"; fi
    if grep -q 'TALOONER_QA_PREVIEW_URL' "$f"; then pass "$f sets TALOONER_QA_PREVIEW_URL"; else bad "$f never sets TALOONER_QA_PREVIEW_URL"; fi
    if grep -q 'TALOONER_QA_CACHE_DIR' "$f"; then pass "$f caches compositions"; else note "$f has no TALOONER_QA_CACHE_DIR: every rebase calls the model again"; fi
  done
fi

tokfiles=$( { ci_files; git ls-files -- '*.yml' '*.yaml' '*.env' '*.rb' '*.sh' 2>/dev/null; } | sort -u)
# shellcheck disable=SC2086 # one argument per file
if [ -n "$tokfiles" ] && ! hardcoded_hook_token $tokfiles; then
  bad "a literal TALOONER_QA_HOOK_TOKEN is committed: build it from the run's ids or use a masked variable"
else
  pass "no literal TALOONER_QA_HOOK_TOKEN"
fi

if [ -f Gemfile ] && grep -q 'talooner-qa-rails' Gemfile; then
  if grep -Eq "^gem ['\"]talooner-qa-rails" Gemfile; then
    bad "talooner-qa-rails is in every group; put it in a test or preview group"
  else
    pass "talooner-qa-rails is in a group"
  fi
  if grep -q 'TaloonerQa::Engine' config/routes.rb 2>/dev/null; then
    if grep 'TaloonerQa::Engine' config/routes.rb | grep -q 'enabled?'; then
      pass "the engine is mounted behind TaloonerQa.enabled?"
    else
      bad "config/routes.rb mounts TaloonerQa::Engine without TaloonerQa.enabled?"
    fi
  else
    bad "config/routes.rb does not mount TaloonerQa::Engine"
  fi
elif git grep -q '__qa' -- ':!.talooner' ':!*.md' 2>/dev/null; then
  pass "the app references /__qa"
else
  note "no /__qa hooks found in the app; QA needs them (references/hooks.md)"
fi

files=$( { find .talooner/qa -type f 2>/dev/null; ci_files; } | sort -u)
for f in $files; do
  if ! secret_shapes_match < "$f" >/dev/null; then bad "secret shape in $f"; fi
done

if [ "$fail" -ne 0 ]; then
  printf 'verify: FAIL\n'
  exit 1
fi
if [ "$incomplete" -ne 0 ]; then
  printf 'verify: INCOMPLETE\n'
  [ "$strict" -eq 1 ] && exit 1
  exit 0
fi
printf 'verify: PASS\n'
