#!/usr/bin/env bash
# The prerequisite version check must never hang. It runs before the log
# directory and the handle exist, so a CLI that does not answer would leave the
# caller with no FRESHPID, no tracker and an empty output file.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT_DIR/skills/fresheyes/fresheyes.sh"

TEST_TMP="$(mktemp -d)"
FAKE_BIN="$TEST_TMP/bin"
mkdir -p "$FAKE_BIN"

cleanup() {
  rm -rf "$TEST_TMP"
}
trap cleanup EXIT

PROBE_LIMIT=3

# The fake CLI answers --version according to FRESHEYES_FAKE_VERSION_BEHAVIOR:
#   hang        – never returns (the failure this test exists for)
#   hang_ignore – never returns AND ignores SIGTERM, so the KILL escalation runs
#   hang_exit   – never returns, then HANDLES SIGTERM and exits non-zero on its
#                 own; it never dies by signal, so only the marker can tell the
#                 runner this was a timeout
#   stdin       – reads stdin to EOF first, then answers; only a launcher that
#                 closes stdin gets an answer at all
#   exit124     – fails immediately with status 124 of its own accord; it must
#                 not read back as the watchdog's timeout
#   ok          – answers immediately
# Anything else it is asked to do just fails, which is enough: every assertion
# here is about whether the launch got past the version gate.
write_fake() {
  local name="$1" version="$2"
  cat > "$FAKE_BIN/$name" <<PY
#!/usr/bin/env python3
import os, signal, sys, time

if sys.argv[1:] == ["--version"]:
    behavior = os.environ.get("FRESHEYES_FAKE_VERSION_BEHAVIOR", "ok")
    if behavior == "hang_ignore":
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
    if behavior == "hang_exit":
        signal.signal(signal.SIGTERM, lambda *_: sys.exit(3))
    if behavior in ("hang", "hang_ignore", "hang_exit"):
        while True:
            time.sleep(3600)
    if behavior == "exit124":
        raise SystemExit(124)
    if behavior == "stdin":
        sys.stdin.read()
    print("$version")
    raise SystemExit(0)

raise SystemExit("fake $name cannot run a review")
PY
  chmod +x "$FAKE_BIN/$name"
}

write_fake codex "codex-cli 0.153.4"
write_fake claude "2.1.257 (Claude Code)"

# Runs the launcher and echoes "<status> <elapsed-seconds>"; the caller asserts.
# The outer timeout is the regression guard: without the watchdog in the runner
# a hanging probe blocks forever, and this test has to fail rather than hang.
run_launch() {
  local provider="$1" behavior="$2" limit="$3" stdout_file="$4" stderr_file="$5"
  local started status=0 outer=40
  # $limit is deliberately non-numeric in the bad-configuration case.
  [[ "$limit" =~ ^[0-9]+$ ]] && outer=$(( limit + 20 ))
  started="$(date +%s)"
  set +e
  PATH="$FAKE_BIN:$PATH" \
    FRESHEYES_FAKE_VERSION_BEHAVIOR="$behavior" \
    FRESHEYES_VERSION_PROBE_TIMEOUT="$limit" \
    FRESHEYES_LOG_DIR="$TEST_TMP/logs" \
    FRESHEYES_GLOBAL_LOG_DIR="$TEST_TMP/global-logs" \
    FRESHEYES_GPT_MODEL= FRESHEYES_CLAUDE_MODEL= FRESHEYES_MODEL= \
    FRESHEYES_REASONING= FRESHEYES_CODEX_IGNORE_USER_CONFIG= \
    FRESHEYES_MODE=manual \
    timeout "${outer}s" bash "$RUNNER" --foreground "$provider" --manual "Review README.md." \
      > "$stdout_file" 2> "$stderr_file"
  status=$?
  set -e
  printf '%s %s\n' "$status" "$(( $(date +%s) - started ))"
}

assert_hang_is_named() {
  local provider="$1" cli="$2" behavior="$3"
  local stdout_file="$TEST_TMP/$cli-$behavior-stdout.txt"
  local stderr_file="$TEST_TMP/$cli-$behavior-stderr.txt"
  local result status elapsed

  result="$(run_launch "$provider" "$behavior" "$PROBE_LIMIT" "$stdout_file" "$stderr_file")"
  status="${result% *}"
  elapsed="${result#* }"

  if [[ "$status" -eq 0 ]]; then
    printf 'a %s --version that never answers (%s) did not fail the launch\n' "$cli" "$behavior" >&2
    exit 1
  fi
  if ! grep -q "'$cli --version' did not answer within ${PROBE_LIMIT}s" "$stderr_file"; then
    printf 'a hanging %s --version (%s) did not produce the named timeout error:\n' "$cli" "$behavior" >&2
    cat "$stderr_file" >&2
    exit 1
  fi
  # The KILL escalation adds 2s on top of the limit; anything near the old
  # behavior (no bound at all) is a regression.
  if [[ "$elapsed" -gt $(( PROBE_LIMIT + 15 )) ]]; then
    printf 'a hanging %s --version (%s) took %ss to fail with a %ss limit\n' \
      "$cli" "$behavior" "$elapsed" "$PROBE_LIMIT" >&2
    exit 1
  fi
}

assert_hang_is_named --gpt codex hang
assert_hang_is_named --gpt codex hang_ignore
assert_hang_is_named --gpt codex hang_exit
assert_hang_is_named --claude claude hang
assert_hang_is_named --claude claude hang_exit

# A probe that reads stdin must still answer: the launcher closes it. Getting
# past the gate is the assertion — "review starting" is printed only after the
# gate, and the fake cannot run a review, so the launch fails right after it.
assert_stdin_probe_passes_the_gate() {
  local provider="$1" cli="$2"
  local stdout_file="$TEST_TMP/$cli-stdin-stdout.txt"
  local stderr_file="$TEST_TMP/$cli-stdin-stderr.txt"

  run_launch "$provider" stdin "$PROBE_LIMIT" "$stdout_file" "$stderr_file" > /dev/null

  if grep -q "did not answer within" "$stderr_file"; then
    printf 'a %s --version that reads stdin was reported as a timeout:\n' "$cli" >&2
    cat "$stderr_file" >&2
    exit 1
  fi
  if ! grep -qh 'review starting' "$stdout_file" "$stderr_file"; then
    printf 'a %s --version that reads stdin did not get past the version gate:\n' "$cli" >&2
    cat "$stdout_file" "$stderr_file" >&2
    exit 1
  fi
}

assert_stdin_probe_passes_the_gate --gpt codex
assert_stdin_probe_passes_the_gate --claude claude

# A probe that picks 124 for its own reasons is not our timeout: the watchdog
# never fired, so the launch must fall back to the ordinary "unable to
# determine" path rather than blame a hang it did not observe.
exit124_stdout="$TEST_TMP/exit124-stdout.txt"
exit124_stderr="$TEST_TMP/exit124-stderr.txt"
exit124_result="$(run_launch --gpt exit124 "$PROBE_LIMIT" "$exit124_stdout" "$exit124_stderr")"
if [[ "${exit124_result% *}" -eq 0 ]]; then
  printf 'a codex --version that exits 124 was accepted as a version\n' >&2
  exit 1
fi
if grep -q 'did not answer within' "$exit124_stderr"; then
  printf 'a codex --version that exits 124 on its own was reported as a timeout:\n' >&2
  cat "$exit124_stderr" >&2
  exit 1
fi
if ! grep -q 'unable to determine the Codex CLI version' "$exit124_stderr"; then
  printf 'a codex --version that exits 124 did not take the ordinary failure path:\n' >&2
  cat "$exit124_stderr" >&2
  exit 1
fi

# The watchdog must reap the sleep it is waiting on. Left alone it outlives
# every fast probe by the full limit, in the caller's process group. The limit
# here is long enough that a surviving sleep is still there to be counted.
NAP_LIMIT=$(( PROBE_LIMIT * 20 ))
count_naps() {
  # pgrep exits 1 when nothing matches, which pipefail would turn into a test
  # failure; an empty match is the answer we want, not an error.
  local matches
  matches="$(pgrep -f "^sleep $NAP_LIMIT\$" 2>/dev/null || true)"
  [[ -z "$matches" ]] && { printf '0\n'; return 0; }
  printf '%s\n' "$matches" | wc -l | tr -d ' '
}
sleeps_before="$(count_naps)"
ok_stdout="$TEST_TMP/ok-stdout.txt"
ok_stderr="$TEST_TMP/ok-stderr.txt"
run_launch --gpt ok "$NAP_LIMIT" "$ok_stdout" "$ok_stderr" > /dev/null
sleeps_after="$(count_naps)"
if [[ "$sleeps_after" -gt "$sleeps_before" ]]; then
  printf 'the watchdog left its sleep behind after a fast probe (%s -> %s)\n' \
    "$sleeps_before" "$sleeps_after" >&2
  exit 1
fi
if grep -q 'did not answer within' "$ok_stderr"; then
  printf 'a fast probe was reported as a timeout\n' >&2
  cat "$ok_stderr" >&2
  exit 1
fi

# A bad limit is a configuration error, not a timeout: it must say so rather
# than fire at t=0 and send the operator after syspolicyd.
bad_stdout="$TEST_TMP/bad-limit-stdout.txt"
bad_stderr="$TEST_TMP/bad-limit-stderr.txt"
bad_result="$(run_launch --gpt ok abc "$bad_stdout" "$bad_stderr")"
if [[ "${bad_result% *}" -eq 0 ]]; then
  printf 'a non-numeric FRESHEYES_VERSION_PROBE_TIMEOUT was accepted\n' >&2
  exit 1
fi
if ! grep -q 'FRESHEYES_VERSION_PROBE_TIMEOUT must be a positive whole number' "$bad_stderr"; then
  printf 'a non-numeric FRESHEYES_VERSION_PROBE_TIMEOUT was not reported as a config error:\n' >&2
  cat "$bad_stderr" >&2
  exit 1
fi

printf 'fresheyes-version-probe tests passed\n'
