#!/usr/bin/env bash
RUNNER_VERSION="1.2.2"
RUNNER_IMAGE="ghcr.io/talooner/talooner-runner:${RUNNER_VERSION}"
export RUNNER_VERSION RUNNER_IMAGE

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || die "not inside a git repository"
}

absolute_dir() {
  CDPATH='' cd -- "$1" && pwd
}

lint_rule_requires() {
  perl -0777 -ne '
    while (/\brule\s+"([^"]+)"\s*\{(.*?)\n\}/sg) {
      my ($name, $body) = ($1, $2);
      while ($body =~ /\brequires\s+"([^"]+)"/g) {
        my $target = $1;
        if ($body !~ /\bdo\s+require\s+"\Q$target\E"/) {
          print "rule \"$name\": requires \"$target\" without do require\n";
          exit 1;
        }
      }
    }
    exit 0;
  '
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
      qr/xox[baprs]-[A-Za-z0-9-]{10,}/,
      qr/AKIA[0-9A-Z]{16}/,
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

removed_copy_match() {
  perl -0777 -ne '
    my @p = (
      "talooner "."onboard",
      "onboard "."--pr",
      "onboard "."--repo",
      "onboard "."command",
      "one onboard "."command",
      "one "."command",
      "with one "."command",
      "in one "."command",
      "talooner "."init",
      "opentalon"."_host",
      "opentalon"."_api_key",
    );
    my $t = lc $_;
    for my $p (@p) {
      if ($t =~ /\Q$p\E(?![a-z])/) {
        print "forbidden phrase\n";
        exit 1;
      }
    }
    exit 0;
  '
}

local_path_match() {
  perl -0777 -ne '
    my $users = "/" . "Users/";
    my $tmp = "/private/var/" . "folders/";
    if (index($_, $users) >= 0 || index($_, $tmp) >= 0) {
      print "forbidden local absolute path\n";
      exit 1;
    }
    exit 0;
  '
}
