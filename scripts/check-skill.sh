#!/usr/bin/env bash
set -uo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/talooner-onboard/scripts/common.sh"

private_paths_match() {
  perl -0777 -ne '
    my $t = $_;
    $t =~ s{(?:https?://)?ghcr\.io/talooner/talooner-runner(?::[A-Za-z0-9._-]+)?}{ALLOWED_IMAGE}g;
    $t =~ s{(?:https?://)?github\.com/Talooner/talooner-skills(?:\.git)?(?:[/?#][^\s]*)?}{ALLOWED_SKILLS}g;
    if ($t =~ m{(?:https?://)?github\.com/[Tt]alooner/(?:talooner|talooner-plugin|talooner-runner)(?:\.git)?(?:[/?#:\s]|$)} ||
        $t =~ m{\b[Tt]alooner/(?:talooner|talooner-plugin|talooner-runner)(?:\.git)?(?:[/?#:\s]|$)}) {
      print "forbidden private path\n";
      exit 1;
    }
    exit 0;
  '
}

fail=0
ok() { printf 'PASS %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

rep() {
  printf '%*s' "$2" '' | tr ' ' "$1"
}

expect_private_clean() {
  if printf '%s\n' "$1" | private_paths_match >/dev/null 2>&1; then ok "private path allowed: $1"; else bad "private path wrongly rejected: $1"; fi
}

expect_private_hit() {
  if printf '%s\n' "$1" | private_paths_match >/dev/null 2>&1; then bad "private path not rejected: $1"; else ok "private path rejected: $1"; fi
}

expect_secret_clean() {
  if printf '%s\n' "$1" | secret_shapes_match >/dev/null 2>&1; then ok "secret placeholder allowed: $1"; else bad "secret placeholder wrongly rejected: $1"; fi
}

expect_secret_hit() {
  if printf '%s\n' "$1" | secret_shapes_match >/dev/null 2>&1; then bad "secret shape not rejected: $2"; else ok "secret shape rejected: $2"; fi
}

skill=$ROOT/talooner-onboard
[ -d "$skill" ] || die "missing talooner-onboard/"
[ -f "$skill/SKILL.md" ] || die "missing talooner-onboard/SKILL.md"

fm=$(awk 'NR==1 && /^---$/{f=1; next} f && /^---$/{exit} f' "$skill/SKILL.md")
name=$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -1)
description=$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -1)
metadata=$(printf '%s\n' "$fm" | awk '/^metadata:/{f=1; next} f && /^[^ ]/{f=0} f')
metadata_version=$(printf '%s\n' "$metadata" | sed -n 's/^[[:space:]]*version:[[:space:]]*//p' | head -1)
runner_metadata=$(printf '%s\n' "$metadata" | sed -n 's/^[[:space:]]*runner_version:[[:space:]]*//p' | head -1)

if [ "$name" = "talooner-onboard" ]; then ok "frontmatter name matches folder"; else bad "frontmatter name is '${name:-empty}', want talooner-onboard"; fi

desc_len=$(printf '%s' "$description" | LC_ALL=C wc -c | tr -d ' ')
if [ "$desc_len" -ge 1 ] && [ "$desc_len" -le 1024 ]; then
  ok "description length ${desc_len}"
else
  bad "description length ${desc_len} is outside 1-1024"
fi
case "$description" in
  *onboard*|*Onboard*) ok "description names the trigger" ;;
  *) bad "description does not name the onboarding trigger" ;;
esac
case "$description" in
  *Talooner*) ok "description names Talooner" ;;
  *) bad "description does not name Talooner" ;;
esac

if [ -n "$metadata_version" ]; then ok "metadata.version is ${metadata_version}"; else bad "metadata.version is missing"; fi
if [ -n "$runner_metadata" ]; then ok "metadata.runner_version is ${runner_metadata}"; else bad "metadata.runner_version is missing"; fi

common_version=$(sed -n 's/^RUNNER_VERSION="\([^"]*\)"$/\1/p' "$skill/scripts/common.sh" | head -1)
if [ -n "$common_version" ] && [ "$common_version" = "$runner_metadata" ]; then
  ok "RUNNER_VERSION matches metadata.runner_version"
else
  bad "RUNNER_VERSION '${common_version:-missing}' does not match metadata.runner_version '${runner_metadata:-missing}'"
fi

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  if [ -e "$skill/$rel" ]; then
    ok "referenced file exists: $rel"
  else
    bad "referenced file missing: $rel"
  fi
done <<EOF
$(perl -ne 'while (m{(?:^|[\s`(])((?:references|scripts|assets)/[A-Za-z0-9._/-]+)}g) { print "$1\n" }' "$skill/SKILL.md" | sort -u)
EOF

for d in references scripts assets; do
  if [ -d "$skill/$d" ]; then ok "folder exists: $d/"; else bad "folder missing: $d/"; fi
done

if lint_rule_requires < "$skill/assets/rules.tln"; then
  ok "starter rules pair requires with do require"
else
  bad "starter rules use requires without do require"
fi

if grep -Fq 'starts_with ".talooner/"' "$skill/assets/rules.tln"; then
  ok "starter rules protect .talooner/"
else
  bad "starter rules do not protect .talooner/"
fi

for needle in 'under_review' 'review.human.approved' 'pr.files_changed'; do
  if grep -Fq "$needle" "$skill/assets/rules.tln"; then
    ok "starter rules use $needle"
  else
    bad "starter rules do not use $needle"
  fi
done

if grep -Fq 'rule "Auto-approve safe changes"' "$skill/assets/rules.tln"; then
  ok "starter rules have the auto-approve rule"
else
  bad "starter rules have no auto-approve rule"
fi

if perl -0777 -ne '
    my @defs = /\bdefine\s+"([A-Za-z_]+_pending)"/g;
    if (!@defs) { print "no _pending defines\n"; exit 1 }
    my ($body) = /\brule\s+"Auto-approve safe changes"\s*\{(.*?)\n\}/s;
    if (!$body) { print "no auto-approve rule\n"; exit 1 }
    for my $d (@defs) {
      if ($body !~ /\bnot\s+is\s+"\Q$d\E"/) { print "auto-approve does not negate $d\n"; exit 1 }
    }
    exit 0;
  ' < "$skill/assets/rules.tln"; then
  ok "auto-approve negates every PR-level gate"
else
  bad "auto-approve does not negate every PR-level gate"
fi

if grep -Eq 'mode[[:space:]]+"sections"' "$skill/assets/rules.tln"; then
  ok "starter rules ship the sections review"
else
  bad "starter rules have no sections review"
fi

if grep -Fq 'attr "unit.doc_content" != ""' "$skill/assets/rules.tln"; then
  ok "starter sections review skips doc-less units"
else
  bad "starter sections review has no doc guard"
fi

for f in assets/guide.md references/guide-prompts.md assets/test-rules.sh; do
  if [ -f "$skill/$f" ]; then ok "shipped file exists: $f"; else bad "shipped file missing: $f"; fi
done

expect_private_clean "https://github.com/Talooner/talooner-skills"
expect_private_clean "github.com/Talooner/talooner-skills.git"
expect_private_clean "ghcr.io/talooner/talooner-runner:1.2.1"
expect_private_hit "github.com/Talooner/talooner"
expect_private_hit "github.com/Talooner/talooner.git"
expect_private_hit "github.com/Talooner/talooner-plugin"
expect_private_hit "github.com/Talooner/talooner-runner"
expect_private_hit "Talooner/talooner"
expect_private_hit "https://github.com/Talooner/talooner-skills and github.com/Talooner/talooner-plugin"

expect_secret_clean "TLN1.<payload>.<signature>"
expect_secret_clean "<your-key>"
expect_secret_clean "risk-assessment and disk-usage"
expect_secret_hit "TLN1.$(rep A 40).$(rep B 40)" "a full Talooner key"
expect_secret_hit "sk-ant-api03-$(rep A 40)" "an Anthropic key"
expect_secret_hit "glpat-$(rep A 20)" "a GitLab token"
expect_secret_hit "ghp_$(rep A 36)" "a GitHub token"
expect_secret_hit "github_pat_$(rep A 24)" "a fine-grained GitHub token"
expect_secret_hit "xoxb-$(rep A 12)" "a Slack token"
expect_secret_hit "AKIA$(rep A 16)" "an AWS key"
expect_secret_hit "-----BEGIN ""RSA PRIVATE KEY-----" "a private key"

files=$(mktemp)
{
  find "$skill" -type f
  printf '%s\n' "$ROOT/README.md"
} | sort -u > "$files"

while IFS= read -r f; do
  [ -f "$f" ] || continue
  if ! private_paths_match < "$f"; then
    printf '  %s\n' "${f#"$ROOT"/}"
    bad "private path in ${f#"$ROOT"/}"
  fi
  if ! secret_shapes_match < "$f"; then
    printf '  %s\n' "${f#"$ROOT"/}"
    bad "secret shape in ${f#"$ROOT"/}"
  fi
  if ! removed_copy_match < "$f"; then
    printf '  %s\n' "${f#"$ROOT"/}"
    bad "removed command or setup phrase in ${f#"$ROOT"/}"
  fi
  if ! local_path_match < "$f"; then
    printf '  %s\n' "${f#"$ROOT"/}"
    bad "local absolute path in ${f#"$ROOT"/}"
  fi
done < "$files"
rm -f "$files"

if [ "$fail" -eq 0 ]; then
  printf 'check-skill: PASS\n'
  exit 0
fi
printf 'check-skill: FAIL\n'
exit 1
