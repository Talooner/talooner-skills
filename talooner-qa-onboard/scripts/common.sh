#!/usr/bin/env bash
RUNNER_VERSION="1.3.2"
QA_VERSION="0.0.10"
RUNNER_IMAGE="ghcr.io/talooner/talooner-runner:${RUNNER_VERSION}"
QA_IMAGE="ghcr.io/talooner/talooner-qa:${QA_VERSION}"
export RUNNER_VERSION QA_VERSION RUNNER_IMAGE QA_IMAGE

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

repo_arg() {
  repo=${1:-}
  if [ "$repo" = "--repo" ]; then
    repo=${2:-}
  fi
  [ -n "$repo" ] || repo=$PWD
  printf '%s\n' "$repo"
}

# The CI files a QA job can live in.
ci_files() {
  [ -f .gitlab-ci.yml ] && printf '%s\n' .gitlab-ci.yml
  for f in .github/workflows/*.yml .github/workflows/*.yaml; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
  return 0
}

secret_shapes_match() {
  perl -0777 -ne '
    my @p = (
      qr/TLN1\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}/,
      qr/sk-ant-[A-Za-z0-9_-]{20,}/,
      qr/sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{20,}/,
      qr/glpat-[A-Za-z0-9_-]{20,}/,
      qr/ghp_[A-Za-z0-9]{36}/,
      qr/github_pat_[A-Za-z0-9_]{20,}/,
      qr/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,
    );
    for my $re (@p) {
      if ($_ =~ $re) {
        print "forbidden token shape\n";
        exit 1;
      }
    }
    exit 0;
  '
}

# A TALOONER_QA_HOOK_TOKEN given a literal value: no variable in it, so it is the
# same on every run and anyone who reads the file can sign in as any role.
hardcoded_hook_token() {
  perl -ne '
    if (/TALOONER_QA_HOOK_TOKEN\s*[:=]\s*["\x27]?([^"\x27\s#]+)/) {
      my $v = $1;
      next if $v =~ /[\$]/;
      print "$ARGV:$.: TALOONER_QA_HOOK_TOKEN has a literal value\n";
      $bad = 1;
    }
    END { exit($bad ? 1 : 0) }
  ' "$@"
}
