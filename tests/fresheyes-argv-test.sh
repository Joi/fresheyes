#!/usr/bin/env bash
# Probing the launcher must never launch a review (jibot-code#ryf1): -h/--help
# prints usage, an unknown option or a blank scope is refused, and in every one
# of those cases no provider CLI runs and no log or handle is written.
# Standalone: bash tests/fresheyes-argv-test.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT_DIR/skills/fresheyes/fresheyes.sh"

TEST_TMP="$(mktemp -d)"
FAKE_BIN="$TEST_TMP/bin"
LOGS="$TEST_TMP/logs"
CALLS="$TEST_TMP/calls"
mkdir -p "$FAKE_BIN" "$LOGS"
cleanup() {
  rm -rf "$TEST_TMP"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# Any invocation of a fake provider CLI is recorded; the tests assert none happens.
for name in codex claude; do
  cat > "$FAKE_BIN/$name" <<SH
#!/usr/bin/env bash
echo "$name \$*" >> "$CALLS"
exit 1
SH
  chmod +x "$FAKE_BIN/$name"
done

run_runner() {
  local status=0
  OUT="$(PATH="$FAKE_BIN:$PATH" FRESHEYES_GLOBAL_LOG_DIR="$LOGS" FRESHEYES_LOG_DIR="$LOGS" \
    bash "$RUNNER" "$@" 2>&1)" || status=$?
  STATUS=$status
}

assert_nothing_launched() {
  local label="$1"
  [[ ! -e "$CALLS" ]] || fail "$label: a provider CLI ran: $(cat "$CALLS")"
  [[ -z "$(ls -A "$LOGS")" ]] || fail "$label: the log dir was written: $(ls -A "$LOGS")"
  [[ "$OUT" != *"FRESHPID="[0-9]* ]] || fail "$label: printed a FRESHPID: $OUT"
}

for flag in -h --help; do
  run_runner "$flag"
  [[ "$STATUS" -eq 0 ]] || fail "$flag: exit $STATUS, want 0: $OUT"
  [[ "$OUT" == *Usage:* ]] || fail "$flag: no usage text: $OUT"
  assert_nothing_launched "$flag"
done

# Help wins wherever it appears among the options.
run_runner --claude --help 'review HEAD'
[[ "$STATUS" -eq 0 && "$OUT" == *Usage:* ]] || fail "--claude --help: exit $STATUS: $OUT"
assert_nothing_launched "--claude --help"

for args in "--version" "-x" "--gpt --verbose review HEAD" "review --bogus"; do
  # shellcheck disable=SC2086
  run_runner $args
  [[ "$STATUS" -eq 2 ]] || fail "'$args': exit $STATUS, want 2: $OUT"
  [[ "$OUT" == *"unknown option"* ]] || fail "'$args': no unknown-option error: $OUT"
  assert_nothing_launched "'$args'"
done

for scope in "" "   "; do
  run_runner --claude "$scope"
  [[ "$STATUS" -eq 2 ]] || fail "scope '$scope': exit $STATUS, want 2: $OUT"
  [[ "$OUT" == *"scope text is empty"* ]] || fail "scope '$scope': no empty-scope error: $OUT"
  assert_nothing_launched "scope '$scope'"
done

# After '--', a leading dash is scope text, so the run gets past argument
# parsing to the provider's version check (the fake CLI fails it).
run_runner --claude --foreground -- '--help is the scope'
[[ "$OUT" != *"unknown option"* && "$OUT" != *Usage:* ]] \
  || fail "'-- --help ...' was parsed as an option: $OUT"
[[ -e "$CALLS" ]] || fail "'-- --help ...' never reached the provider: $OUT"

echo "PASS: fresheyes argv"
