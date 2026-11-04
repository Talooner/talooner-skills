#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"
RUNNER_IMAGE_GH="${RUNNER_IMAGE}-gh"

repo=$PWD
strict=no
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo=${2:-}; shift 2 ;;
    --strict) strict=yes; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done

cd "$repo" 2>/dev/null || die "cannot enter $repo"
git rev-parse --show-toplevel >/dev/null 2>&1 || die "not inside a git repository"

fail=0
skipped=0
ok() { printf 'PASS %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

image_re() {
  printf '%s' "$1" | sed 's/[.[\*^$/]/\\&/g'
}

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
      .talooner/*|docs/guides/*|.github/workflows/talooner.yml|.github/workflows/talooner.yaml|.gitlab-ci.yml|.gitignore) ;;
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

staged=$(git diff --cached --name-only 2>/dev/null)
if [ -z "$staged" ]; then
  ok "no staged files outside the onboarding set"
else
  unexpected=
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
      .talooner/*|docs/guides/*|.github/workflows/talooner.yml|.github/workflows/talooner.yaml|.gitlab-ci.yml|.gitignore) ;;
      *) unexpected="$unexpected $path" ;;
    esac
  done <<EOF
$staged
EOF
  if [ -z "$unexpected" ]; then
    ok "staged changes are limited to onboarding files"
  else
    bad "unexpected staged changes:$unexpected"
  fi
fi

if [ -f .talooner/onboarding.md ]; then ok "onboarding spec exists"; else bad "missing .talooner/onboarding.md"; fi

has_rules=no
[ -f .talooner/rules.tln ] && has_rules=yes
split=no
for f in .talooner/rules/*.tln; do
  [ -f "$f" ] || continue
  has_rules=yes
  split=yes
done
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

test_script=
if [ "$split" = yes ]; then
  if [ -f .talooner/test-rules.sh ]; then
    test_script=.talooner/test-rules.sh
    ok "split ruleset has .talooner/test-rules.sh"
  else
    bad "split ruleset needs .talooner/test-rules.sh: tln test .talooner/ compiles each pair alone and cannot see shared defines"
  fi
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

for f in .talooner/config.yaml .talooner/teams.yaml .talooner/review.md; do
  if [ -f "$f" ]; then
    ok "optional file exists: $f"
  fi
done

if [ -f .talooner/architecture.yaml ]; then
  ok "architecture.yaml exists"
  doc_refs=$(sed -n 's/^[[:space:]]*doc_ref:[[:space:]]*//p' .talooner/architecture.yaml | tr ',' '\n' | sed 's/^[[:space:]]*\[//;s/\]//;s/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    if [ -f "$ref" ]; then
      ok "doc_ref exists: $ref"
      sections=$(awk '
        function flush() {
          if (h2 != "" && prose && !h3) n++
          prose = 0; h3 = 0
        }
        /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
        fence { next }
        /^## / {
          flush()
          h = substr($0, 4)
          if (h == "Specs" || h == "Advice") { reserved = 1; h2 = "" } else { reserved = 0; h2 = h }
          next
        }
        /^### / {
          if (h2 != "") { h3 = 1; n++ }
          else if (!reserved) { orphan = 1 }
          next
        }
        /^[*_]*Applies to[*_]*:/ { if (h2 != "" && $0 !~ /`/) empty++; next }
        { if (h2 != "" && $0 ~ /[^ \t]/) prose = 1 }
        END { flush(); printf "%d %d %d\n", n, empty + 0, orphan + 0 }
      ' "$ref")
      found=$(printf '%s' "$sections" | cut -d' ' -f1)
      applies_empty=$(printf '%s' "$sections" | cut -d' ' -f2)
      orphan=$(printf '%s' "$sections" | cut -d' ' -f3)
      if [ "$found" -eq 0 ]; then
        bad "$ref has no ### rule under a ## heading; the sections review asks nothing and every unit falls back to the default review"
      elif [ "$orphan" -eq 1 ]; then
        warn "$ref has a ### heading with no ## heading above it; the sections review skips it"
      fi
      if [ "$applies_empty" -gt 0 ]; then
        warn "$ref has an Applies to: line with no backticked path; that section applies to every file"
      fi
    else
      bad "missing doc_ref: $ref (name the file, or drop doc_ref to make the entry rules-only)"
    fi
  done <<EOF
$doc_refs
EOF
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    warn "architecture entry without doc_ref is rules-only:${entry#- path:} (AI review reads nothing)"
  done <<EOF
$(awk '
  /^[[:space:]]*-[[:space:]]*path:/ { if (n && !d) print p; p=$0; d=0; n=1; next }
  /^[[:space:]]*doc_ref:/ { d=1 }
  END { if (n && !d) print p }
' .talooner/architecture.yaml)
EOF
else
  bad "missing .talooner/architecture.yaml: with no architecture rule Talooner sends no code units, so AI review never runs and no inline comment can be posted"
fi

legacy=
for f in .github/talooner/rules.tln .github/talooner/config.yaml .github/talooner/teams.yaml .github/talooner/architecture.yaml .github/talooner/review.md; do
  [ -e "$f" ] && legacy="$legacy $f"
done
for f in .github/talooner/rules/*.tln; do [ -f "$f" ] && legacy="$legacy $f"; done
if [ -z "$legacy" ]; then
  ok "no legacy Talooner path"
else
  bad "legacy Talooner path present:$legacy - migrate it to .talooner/"
fi

rule_lint_ok=yes
if [ -f .talooner/rules.tln ]; then
  if ! lint_rule_requires < .talooner/rules.tln; then rule_lint_ok=no; fi
fi
for f in .talooner/rules/*.tln; do
  [ -f "$f" ] || continue
  if ! lint_rule_requires < "$f"; then rule_lint_ok=no; fi
done
if [ "$rule_lint_ok" = yes ]; then
  ok "requires targets are requested with do require"
else
  bad "a rule declares requires without a matching do require"
fi

ignore_list=$(mktemp)
{
  [ -d .talooner ] && find .talooner -type f
  [ -n "$ci_github" ] && printf '%s\n' "$ci_github"
  [ -n "$ci_gitlab" ] && printf '%s\n' "$ci_gitlab"
  [ -d docs/guides ] && find docs/guides -type f
} | sort -u > "$ignore_list"
ignored=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  if ! git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    if git check-ignore -q "$f" 2>/dev/null; then
      printf '  %s\n' "$f"
      ignored=1
    fi
  fi
done < "$ignore_list"
rm -f "$ignore_list"
if [ "$ignored" -eq 0 ]; then
  ok "generated files are not ignored by git"
else
  bad "generated files are ignored by git; add negations to .gitignore"
fi

out=$(mktemp)
if [ "$split" = yes ]; then
  if [ -z "$test_script" ]; then
    bad "split ruleset test (missing .talooner/test-rules.sh)"
  elif docker run --rm --user "$(id -u):$(id -g)" \
    -v "$PWD:/repo" -w /repo --entrypoint sh \
    "$RUNNER_IMAGE" "$test_script" >"$out" 2>&1; then
    ok "$test_script"
  else
    cat "$out"
    bad "$test_script"
  fi
elif docker run --rm --user "$(id -u):$(id -g)" \
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
  if [ "$strict" = yes ]; then
    bad "runner config sanity (provider or forge token not set)"
  else
    printf 'SKIP runner config sanity (provider or forge token not set)\n'
    skipped=1
  fi
fi

if [ -n "$ci_github" ]; then
  if grep -Eq '^  rules:' "$ci_github"; then ok "GitHub rules job"; else bad "GitHub rules job missing"; fi
  if grep -Eq '^  review:' "$ci_github"; then ok "GitHub review job"; else bad "GitHub review job missing"; fi
  if grep -Eq "(^|[^0-9A-Za-z._-])$(image_re "$RUNNER_IMAGE_GH")([^0-9A-Za-z._-]|$)" "$ci_github"; then ok "GitHub review uses pinned -gh image"; else bad "GitHub review image is not $RUNNER_IMAGE_GH"; fi
  if [ "$split" = yes ]; then
    if grep -q -- 'test-rules.sh' "$ci_github" && grep -Eq "(^|[^0-9A-Za-z._-])$(image_re "$RUNNER_IMAGE")([^0-9A-Za-z._-]|$)" "$ci_github"; then ok "GitHub rules run .talooner/test-rules.sh on the pinned image"; else bad "GitHub rules do not run .talooner/test-rules.sh on $RUNNER_IMAGE"; fi
  elif grep -Eq -- "--entrypoint tln $(image_re "$RUNNER_IMAGE") test" "$ci_github"; then ok "GitHub rules use pinned image"; else bad "GitHub rules image is not $RUNNER_IMAGE"; fi
  if grep -q 'TALOONER_LICENSE_KEY' "$ci_github"; then ok "GitHub license key is wired"; else bad "GitHub license key is not wired"; fi
  if grep -Eq 'ANTHROPIC_API_KEY|OPENAI_API_KEY|TALOONER_MODEL_API_KEY|TALOONER_MODEL_BASE_URL' "$ci_github"; then ok "GitHub model env is wired"; else bad "GitHub model env is not wired"; fi
  if grep -q 'CDM_URL' "$ci_github" && grep -q 'CDM_TOKEN' "$ci_github"; then ok "GitHub decision-model env is wired"; else bad "GitHub decision-model env is not wired"; fi
fi

if [ -n "$ci_gitlab" ]; then
  if grep -Eq '^talooner-rules:' "$ci_gitlab"; then ok "GitLab rules job"; else bad "GitLab rules job missing"; fi
  if grep -Eq '^talooner-review:' "$ci_gitlab"; then ok "GitLab review job"; else bad "GitLab review job missing"; fi
  if grep -q 'entrypoint: \[""\]' "$ci_gitlab"; then ok "GitLab entrypoint is empty"; else bad "GitLab entrypoint is not empty"; fi
  if grep -Eq 'needs: \[talooner-rules\]' "$ci_gitlab"; then ok "GitLab review needs rules"; else bad "GitLab review does not need talooner-rules"; fi
  if grep -Eq "(^|[^0-9A-Za-z._-])$(image_re "$RUNNER_IMAGE")([^0-9A-Za-z._-]|$)" "$ci_gitlab"; then ok "GitLab uses pinned image"; else bad "GitLab does not use $RUNNER_IMAGE"; fi
  if [ "$split" = yes ]; then
    if grep -q -- 'test-rules.sh' "$ci_gitlab"; then ok "GitLab rules run .talooner/test-rules.sh"; else bad "GitLab rules do not run .talooner/test-rules.sh"; fi
  fi
  if grep -Eq '^talooner:' "$ci_gitlab"; then
    bad "GitLab has a job named talooner"
  else
    ok "GitLab has no job named talooner"
  fi
  if grep -q 'TALOONER_LICENSE_KEY' "$ci_gitlab"; then ok "GitLab license key is wired"; else bad "GitLab license key is not wired"; fi
  if grep -Eq 'ANTHROPIC_API_KEY|OPENAI_API_KEY|TALOONER_MODEL_API_KEY|TALOONER_MODEL_BASE_URL' "$ci_gitlab"; then ok "GitLab model env is wired"; else bad "GitLab model env is not wired"; fi
  if grep -q 'CDM_URL' "$ci_gitlab" && grep -q 'CDM_TOKEN' "$ci_gitlab"; then ok "GitLab decision-model env is wired"; else bad "GitLab decision-model env is not wired"; fi
fi

candidates=$(mktemp)
generated=$(mktemp)
{
  [ -d .talooner ] && find .talooner -type f
  [ -n "$ci_github" ] && printf '%s\n' "$ci_github"
  [ -n "$ci_gitlab" ] && printf '%s\n' "$ci_gitlab"
} | sort -u > "$generated"
{
  cat "$generated"
  [ -d docs/guides ] && find docs/guides -type f
} | sort -u > "$candidates"

secrets=0
copy=0
localpath=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  if ! secret_shapes_match < "$f"; then
    printf '  %s\n' "$f"
    secrets=1
  fi
done < "$candidates"
while IFS= read -r f; do
  [ -f "$f" ] || continue
  if ! removed_copy_match < "$f"; then
    printf '  %s\n' "$f"
    copy=1
  fi
  if ! local_path_match < "$f"; then
    printf '  %s\n' "$f"
    localpath=1
  fi
done < "$generated"
rm -f "$candidates" "$generated"

if [ "$secrets" -eq 0 ]; then ok "no token shapes in onboarding files"; else bad "token shapes in onboarding files"; fi
if [ "$copy" -eq 0 ]; then ok "no removed commands or setup phrases"; else bad "removed commands or setup phrases in onboarding files"; fi
if [ "$localpath" -eq 0 ]; then ok "no local absolute paths"; else bad "local absolute paths in onboarding files"; fi

if [ "$fail" -eq 0 ]; then
  if [ "$skipped" -eq 0 ]; then
    printf 'verify: PASS\n'
  else
    printf 'verify: INCOMPLETE (config sanity skipped; rerun with --strict and a real forge token)\n'
  fi
  exit 0
fi
printf 'verify: FAIL\n'
exit 1
