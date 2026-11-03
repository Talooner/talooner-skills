#!/bin/sh
# Talooner joins .talooner/rules/ as one ruleset: _ files first, then by name.
# tln test pairs foo.tln with foo.tln.test and compiles each pair alone, so it
# cannot see shared defines. Join exactly like Talooner, then test the result.
set -eu
src=$(dirname "$0")/rules
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export LC_ALL=C

for f in "$src"/_*.tln "$src"/[!_]*.tln; do
  [ -f "$f" ] || continue
  cat "$f"
  printf '\n'
done >"$tmp/rules.tln"

for f in "$src"/*.tln.test; do
  [ -f "$f" ] || continue
  cat "$f"
  printf '\n'
done >"$tmp/rules.tln.test"

tln test "$tmp/"
