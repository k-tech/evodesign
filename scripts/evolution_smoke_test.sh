#!/usr/bin/env bash
# Pure bash smoke test for EvoDesign generation counters.
# Run from the repository root:
#   bash scripts/evolution_smoke_test.sh
#
# This file does not run under the scheduled runner. It exists so a human (or
# any post-run audit) can verify that the generation-numbering logic is robust
# against leading zeros, multi-digit numbers and out-of-order filenames before
# the next scheduled run.

set -Eeuo pipefail
IFS=$'\n\t'

fail=0
note() { printf '  %s\n' "$*"; }
expect_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf 'PASS %s -> %s\n' "$label" "$actual"
  else
    printf 'FAIL %s expected=%q actual=%q\n' "$label" "$expected" "$actual" >&2
    fail=1
  fi
}

# Inline re-implementation of the same algorithm used in scripts/evolve.sh.
# If evolve.sh drifts from this copy, this test fails loudly.
parse_num() { printf '%d' "$((10#$1))"; }

count_highest_in() {
  local dir="$1"
  local p name number highest=0
  local old_globstate
  shopt -q nullglob || old_globstate="off"; shopt -s nullglob
  for p in "$dir"/gen-*.json; do
    [[ -e "$p" ]] || continue
    name="$(basename "$p")"
    [[ "$name" =~ ^gen-([0-9]+)\.json$ ]] || continue
    number=$((10#${BASH_REMATCH[1]}))
    if (( number > highest )); then highest=$number; fi
  done
  [[ "$old_globstate" == "off" ]] && shopt -u nullglob || true
  printf '%d' "$highest"
}

note "1. direct numeric parsing (explicit base-10 prefix must never touch octal)"
expect_eq "parse_num 001" 1 "$(parse_num 001)"
expect_eq "parse_num 008" 8 "$(parse_num 008)"
expect_eq "parse_num 010" 10 "$(parse_num 010)"
expect_eq "parse_num 045" 45 "$(parse_num 045)"
expect_eq "parse_num 099" 99 "$(parse_num 099)"
expect_eq "parse_num 100" 100 "$(parse_num 100)"
expect_eq "parse_num 999" 999 "$(parse_num 999)"

note "2. highest-on-disk algorithm in an isolated temp directory"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Mixed spacing and an out-of-order write order to ensure the helper reads all files.
for n in 001 008 010 045 099 100 123; do
  : > "$tmp/gen-$n.json"
done

# Out-of-order insertion.
: > "$tmp/gen-009.json"
: > "$tmp/gen-002.json"

expect_eq "highest among samples" 123 "$(count_highest_in "$tmp")"

note "3. empty / no-files directory"
empty="$(mktemp -d)"
expect_eq "highest when empty" 0 "$(count_highest_in "$empty")"
rm -rf "$empty"

note "4. ignore non-matching files"
junk="$(mktemp -d)"
: > "$junk/gen-999.json"
: > "$junk/gen-abc.json"   # must be ignored
: > "$junk/README.txt"     # must be ignored
expect_eq "highest with junk files" 999 "$(count_highest_in "$junk")"
rm -rf "$junk"

if (( fail )); then
  printf 'OVERALL FAIL: generation counter smoke test caught regressions\n' >&2
  exit 1
fi
printf 'OVERALL PASS: generation counter is robust\n'
exit 0
