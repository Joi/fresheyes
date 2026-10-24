#!/usr/bin/env bash
# Tests for fresheyes-git-guard.sh, the Claude reviewer's `git`, against the
# real git in a throwaway repository whose own config names an external diff,
# a textconv driver and an fsmonitor hook, each of which leaves a marker file
# when it runs.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$REPO_DIR/skills/fresheyes/fresheyes-git-guard.sh"
REAL_GIT="$(command -v git)"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fresheyes-git-guard-test.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

REPO="$TMP_DIR/repo"
MARK="$TMP_DIR/marks"
mkdir -p "$REPO" "$MARK"
helper() { # helper <name>: a program that leaves $MARK/<name> when it runs
  printf '#!/bin/sh\ntouch %q\n' "$MARK/$1" > "$TMP_DIR/$1"
  chmod +x "$TMP_DIR/$1"
}
helper ext-diff
helper textconv
helper fsmonitor
helper env-ext-diff
(
  cd "$REPO"
  git init -q
  git config user.email t@example.com
  git config user.name t
  printf 'one\n' > f.txt
  printf '*.txt diff=marker\n' > .gitattributes
  git add f.txt .gitattributes
  git commit -qm init
  printf 'two\n' >> f.txt
  git config diff.external "$TMP_DIR/ext-diff"
  git config diff.marker.textconv "$TMP_DIR/textconv"
  git config core.fsmonitor "$TMP_DIR/fsmonitor"
)

guard() { # runs the guard in the repo; prints stdout, returns git's status
  (cd "$REPO" && bash "$GUARD" "$REAL_GIT" "$@" 2>"$TMP_DIR/stderr")
}

no_marks() { [[ -z "$(ls -A "$MARK")" ]]; }

expect_ok() {
  local name="$1"; shift
  rm -f "$MARK"/*
  local out rc=0
  out="$(guard "$@")" || rc=$?
  if [[ "$rc" -eq 0 ]] && no_marks; then
    pass "$name"
  else
    fail "$name (rc=$rc marks=$(ls "$MARK" | tr '\n' ' ') stderr=$(cat "$TMP_DIR/stderr"))"
  fi
  LAST_OUT="$out"
}

expect_refused() {
  local name="$1"; shift
  rm -f "$MARK"/* "$TMP_DIR"/pwned*
  local rc=0
  guard "$@" >/dev/null || rc=$?
  if [[ "$rc" -eq 128 ]] && no_marks && ! ls "$TMP_DIR"/pwned* "$REPO"/pwned* >/dev/null 2>&1 \
    && grep -q 'fresheyes: refused' "$TMP_DIR/stderr"; then
    pass "$name"
  else
    fail "$name (rc=$rc marks=$(ls "$MARK" | tr '\n' ' ') stderr=$(cat "$TMP_DIR/stderr"))"
  fi
}

# The fixture is live: without the guard, the repo's own config runs helpers.
rm -f "$MARK"/*
(cd "$REPO" && git diff >/dev/null 2>&1 || true)
[[ -e "$MARK/ext-diff" ]] && pass "fixture: plain git diff runs the configured external diff" \
  || fail "fixture: plain git diff did not run the configured external diff"

# Read-only commands run, with every helper off.
expect_ok "diff runs" diff
[[ "$LAST_OUT" == *"+two"* ]] && pass "diff shows the change itself, not a helper's output" \
  || fail "diff output was: $LAST_OUT"
expect_ok "diff --text (an exact option, not an abbreviation of --textconv)" diff --text
expect_ok "diff --stat with a pathspec" diff --stat -- f.txt
expect_ok "diff with --output= after -- is a pathspec" diff -- --output="$TMP_DIR/pwned"
expect_ok "show HEAD" show HEAD
expect_ok "log -p -1" log -p -1
expect_ok "status" status
expect_ok "-C <dir> diff" -C "$REPO" diff
expect_ok "Claude Code's own -c settings" -c core.hooksPath=/dev/null -c core.fsmonitor= \
  -c hook.pre-commit.enabled=false --no-optional-locks log --oneline -n 5
expect_ok "config <key> reads" config user.name
[[ "$LAST_OUT" == "t" ]] && pass "config <key> prints the value" || fail "config user.name printed: $LAST_OUT"
expect_ok "remote with no arguments" remote
expect_ok "ls-files" ls-files
expect_ok "--version" --version

# Writing options and helper switches are refused, abbreviations included.
expect_refused "diff --output=<file>" diff --output="$TMP_DIR/pwned"
expect_refused "diff --output <file>" diff --output "$TMP_DIR/pwned"
expect_refused "diff --outp=<file> (abbreviation)" diff --outp="$TMP_DIR/pwned"
expect_refused "log -p --output=<file>" log -p --output="$TMP_DIR/pwned"
expect_refused "show --output=<file>" show --output="$TMP_DIR/pwned" HEAD
expect_refused "diff --ext-diff" diff --ext-diff
expect_refused "diff --ext (abbreviation)" diff --ext
expect_refused "log -p --textconv" log -p --textconv
expect_refused "log --show-signature" log --show-signature
expect_refused "-c diff.external=<program>" -c diff.external="$TMP_DIR/ext-diff" diff
expect_refused "--config-env" --config-env=diff.external=X diff
expect_refused "--exec-path" --exec-path="$TMP_DIR" diff
expect_refused "-p (paginate)" -p diff
expect_refused "config <key> <value> writes" config user.name x
expect_refused "config --unset" config --unset user.name
expect_refused "remote add" remote add x "$TMP_DIR"
expect_refused "commit" commit -qam x
expect_refused "checkout" checkout -- f.txt
expect_refused "fetch" fetch
expect_refused "no subcommand"

# Environment that names a helper or a file to write is scrubbed.
rm -f "$MARK"/*
rc=0
(cd "$REPO" && GIT_EXTERNAL_DIFF="$TMP_DIR/env-ext-diff" GIT_TRACE="$TMP_DIR/pwned-trace" \
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=diff.external GIT_CONFIG_VALUE_0="$TMP_DIR/env-ext-diff" \
  bash "$GUARD" "$REAL_GIT" diff >/dev/null 2>&1) || rc=$?
if [[ "$rc" -eq 0 ]] && no_marks && [[ ! -e "$TMP_DIR/pwned-trace" ]]; then
  pass "GIT_EXTERNAL_DIFF, GIT_TRACE and GIT_CONFIG_* are scrubbed"
else
  fail "environment scrub (rc=$rc marks=$(ls "$MARK" | tr '\n' ' '))"
fi

# A guard started without a real git refuses everything.
rc=0
(cd "$REPO" && bash "$GUARD" "" diff >/dev/null 2>&1) || rc=$?
[[ "$rc" -eq 128 ]] && pass "no real git: refused" || fail "no real git: rc=$rc"

# Nothing above wrote to the repository's tracked files or config.
if [[ -z "$(cd "$REPO" && git -c core.fsmonitor=false status --porcelain --untracked-files=all | grep -v '^ M f.txt$' || true)" ]] \
  && [[ "$(cd "$REPO" && git config user.name)" == "t" ]] \
  && ! (cd "$REPO" && git remote | grep -q .); then
  pass "the repository is unchanged"
else
  fail "the repository changed: $(cd "$REPO" && git status --porcelain --untracked-files=all)"
fi

echo
echo "$PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]]
