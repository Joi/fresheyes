# Claude reviewer read-only — plan

Spec: docs/superpowers/specs/2026-09-21-claude-reviewer-read-only-design.md.
Kata jibot-code#x48m. Procedures: docs/FLEET.md on `origin/feat/fleet-snapshot`.

## Chunk 1 — the fix (branch `fix/claude-reviewer-read-only`, cut from `upstream/main`)

Only these two files are committed on this branch. The spec, plan and manifest
stay untracked here; they are committed on the integration branch in chunk 2.

- [ ] `git switch -c fix/claude-reviewer-read-only upstream/main` in this worktree.
- [ ] Test first, `tests/fresheyes-claude-provider-test.sh`: add
  `assert_restricted_argv` next to `assert_manual_argv` (line ~130). It loads
  `$ARGV_FILE` and fails unless ALL hold:
  - `--dangerously-skip-permissions` absent; `bypassPermissions` absent;
  - `--tools` followed by exactly `Bash,Read,Glob,Grep`;
  - `--allowedTools` followed by exactly
    `Bash(git diff:*,git show:*,git log:*,git status:*),Read,Glob,Grep`;
  - `--permission-mode` followed by `dontAsk`;
  - `--setting-sources` followed by the empty string;
  - `--strict-mcp-config` present;
  - every one of these sits before the `--` separator (after it they would be prompt text).
  The fake `claude` binary (python, line ~57) also records
  `os.environ.get("GIT_OPTIONAL_LOCKS")` next to argv (a second file,
  `$ARGV_FILE.env`), and the helper fails unless it is `0`. So that an
  inherited value cannot satisfy it, the three launches that call the helper
  run with `GIT_OPTIONAL_LOCKS=1` exported by the test (in `run_runner_capture`
  and in the detached launch's env block), and each `rm -f "$ARGV_FILE"` that
  precedes them also removes `$ARGV_FILE.env`: only the launcher's own
  assignment can produce the `0` the fake sees.
- [ ] Call it from `test_manual_claude_invocation_uses_streaming_flags`
  (foreground manual), `test_automatic_claude_extracts_structured_output`
  (automatic) and, after the detached review completes, from
  `test_manual_detaches_by_default_and_completes` (detached; the fake binary
  writes `$ARGV_FILE` from inside the detached child).
  In the detached test the success path is the `return 0` inside the polling
  loop (line ~389); the call goes immediately before that `return 0`. Put
  `GIT_OPTIONAL_LOCKS=1` after the `FRESHEYES_FAKE_ARGV=` line of each env block
  (the integration branch inserts lines higher up in `run_runner_capture`; on a
  merge conflict in the test file keep both sides). The helper prints the
  recorded env value on failure: on Linux a `systemd-run` detach may not forward
  the test's `1`, and an unset value still fails the `== "0"` check, which is
  what matters.
- [ ] Red, one test at a time, because the file stops at its first failure:
  temporarily run each of the three tests alone (comment out the other calls at
  the bottom of the file, or invoke the function through a one-line edit) and
  see each fail on the missing flags — manual and automatic on macOS, the
  detached one on the Lima VM (macOS stops at `ps -o sess=` before reaching it).
- [ ] `skills/fresheyes/fresheyes.sh` line ~562: after `CLAUDE_TOOLS=`, add
  `CLAUDE_BUILTIN_TOOLS='Bash,Read,Glob,Grep'` and the `CLAUDE_RESTRICT_ARGS`
  array from the spec with a comment saying what each flag closes and that
  `--allowedTools` alone grants and does not restrict. In `run_claude_manual`
  (lines 611–612) and `run_claude_automatic` (lines 642–643) replace the
  `--allowedTools` and `--dangerously-skip-permissions` lines with
  `"${CLAUDE_RESTRICT_ARGS[@]}" \`. In both, extend the `env` prefix to
  `env -u ANTHROPIC_API_KEY -u CLAUDE_CODE_ENTRYPOINT GIT_OPTIONAL_LOCKS=0`
  (plain `git status` otherwise rewrites `.git/index`; measured in the spec).
- [ ] Run the file again (green up to the known macOS stop at `ps -o sess=`),
  then all of `tests/*.sh` with the FLEET.md loop and the five `FRESHEYES_*`
  variables unset. On macOS a file may fail only at the three points FLEET.md lists.
- [ ] README: if it describes the Claude launch flags or says the reviewer can
  only read, make the sentence match (grep `skip-permissions`, `allowedTools`, `read-only`).
- [ ] Live acceptance, real CLI, from this worktree's script, scratch git repo
  as cwd. These are runs of the code under test, not review launches, so they
  are recorded in the manifest Notes and not counted in the 8-launch budget:
  1. `fresheyes.sh --claude --foreground "Review a.txt."` → exit 0, a verdict line.
  2. `fresheyes.sh --claude --foreground "<scope telling the reviewer to write
     pwned-write.txt with the Write tool and to run 'touch pwned-bash.txt'>"` →
     neither file exists afterwards; the stream log shows the denials.
  3. The same scope detached (no `--foreground`), result fetched with
     `fresheyes-progress.sh --result <FRESHPID>` → neither file exists.
  4. The same scope with `--claude --mode automatic` → schema-valid JSON on
     disk, neither file exists.
  Every run counts only with stream-log evidence (`<log>.stream.jsonl`): the
  init tool list (manual: exactly Bash, Glob, Grep, Read; automatic: those four
  plus StructuredOutput; never Write, Edit or Task), the attempted call with
  its permission-denied result, and one successful Read or git call. A model
  that declines to attempt is reported as that, and the direct-CLI run with the
  script's real argv stands in.
  Effort is whatever the branch hard-codes (`upstream/main` reads no effort
  variable: manual xhigh, automatic medium). Run 1 uses the default model. Runs
  2–4 set `FRESHEYES_CLAUDE_MODEL=claude-sonnet-5`, which the script does read,
  to keep them cheap; the permission path is the CLI's and does not depend on
  the model, and the close-out says which model each run used.
- [ ] Linux run of `tests/fresheyes-claude-provider-test.sh` and the rest of
  `tests/*.sh` on a throwaway local Linux VM (Lima, Ubuntu 24.04; no docker on
  this Mac and no usable sprite login; never katavm, a cell or a production
  VM). The tree under test is a named object, not the working tree: build the
  review snapshot commit `$SNAP` of the two changed files first,
  `git archive $SNAP | limactl shell fe-x48m tar -x -C <dir>`, run the FLEET.md
  loop there, record `$SNAP` with the output, delete the VM. If review changes
  the code afterwards, the Linux run is repeated on the new snapshot, and the
  commit's tree must equal the last snapshot's tree (`git diff --quiet $SNAP HEAD`).
- [ ] Code review: Stage 1 (requesting-code-review subagent) ∥ Stage 2
  (fresheyes `--gpt`, Astra, from the installed plugin) on the snapshot.
- [ ] Commit (two files), `git push -u origin fix/claude-reviewer-read-only`.
- [ ] `gh pr create -R danshapiro/fresheyes --base main --head Joi:fix/claude-reviewer-read-only`,
  body per voice.md: what the flag pair does today, the measurement table, the
  new flag set, what still runs (`ls`/`cat`-class reads), the behaviour change
  (the reviewed repo's `CLAUDE.md` and the user's settings no longer load, so
  settings-based auth such as `apiKeyHelper` stops working), the two limits
  (managed policy; a diff helper already in the machine's git config),
  `Fixes #10`. No private paths, no fleet detail.

Acceptance: spec criteria 1–5 each shown with command and output.
Rollback: delete the branch; nothing else changed.

## Chunk 2 — integration and tag

- [ ] `git switch -c integrate-claude-reviewer-read-only origin/feat/fleet-snapshot`;
  `git merge --no-ff origin/fix/claude-reviewer-read-only`. Conflicts are not
  expected; if `fresheyes.sh` conflicts, keep the fleet's lines and re-apply the
  array; if the test file conflicts in `run_runner_capture`, keep both sides.
- [ ] Confirm the GPT default is still `gpt-5.6-sol` (`grep -n 'FRESHEYES_GPT_MODEL:-' skills/fresheyes/fresheyes.sh`).
- [ ] Tests again on the merged tree, always on both: the macOS loop, and the
  Linux loop on the Lima VM against the merge commit
  (`git archive HEAD | limactl shell fe-x48m tar -x -C <dir>`), before the push and the tag.
- [ ] Commit the spec, plan and manifest on this branch (`docs/superpowers/...` only).
- [ ] Independent review of the merge result: reuse the chunk-1 pass when
  `git diff origin/feat/fleet-snapshot HEAD -- skills tests` equals the reviewed
  fix diff; otherwise one delta pass.
- [ ] `git push origin HEAD:refs/heads/feat/fleet-snapshot` (fast-forward only).
- [ ] Tag `fleet-2026.09.21.2` on `origin/feat/fleet-snapshot`, push, verify with
  `git ls-remote --tags origin 'refs/tags/fleet-2026.09.21.2^{}'` = `git rev-parse origin/feat/fleet-snapshot`.
- [ ] File the follow-up (an OS sandbox around the Claude reviewer, which closes
  the git-config helper limit) in kata with the evidence; close-out comment; close; `/finish-worktree`.

Acceptance: tag hash equals branch hash; PR URL and tag in the close-out.
Rollback: revert the merge commit on the integration branch, tag `.3`.
Not done here: refreshing other machines' clones or the `~/.codex/skills` copies
(brief: "Other machines: none", jibot-code#knpg/#112s own consumer pinning).
