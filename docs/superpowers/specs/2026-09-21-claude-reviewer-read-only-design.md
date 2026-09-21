# Claude reviewer read-only — design

Kata: jibot-code#x48m. Upstream: danshapiro/fresheyes#10. Date: 2026-09-21.

## Problem

`skills/fresheyes/fresheyes.sh` launches the Claude reviewer as `claude -p` with
`--allowedTools 'Bash(git diff:*,git show:*,git log:*,git status:*),Read,Glob,Grep'`
and `--dangerously-skip-permissions` (`run_claude_manual`, `run_claude_automatic`).
`--allowedTools` pre-approves tools; it removes none. With the bypass flag every
other tool is approved too. The reviewer can Edit, Write and run any shell
command in the repository it reviews, and it loads the user's hooks, plugins and
MCP servers. The GPT reviewer runs in `codex exec --sandbox read-only`.

## Measurement (2026-09-21, Claude Code 2.1.269, macOS, real CLI)

A scratch git repo; the prompt asks for a Write, `touch <file>`, `git status`, a
Read, and in a second run `git diff --output=<file>`, `git status && touch`,
`git log > file`, `git -c core.pager=cat diff`. The user settings on the test
machine carry `permissions.allow: [Bash, Write, Edit, ...]`, which is common.

| Launch | Write | `touch` | Notes |
|---|---|---|---|
| current (`--allowedTools` + bypass) | file created | file created | `--output`, chain and redirect all wrote files; 5 SessionStart hooks ran, 9 plugins and 5 MCP servers loaded |
| A: drop the bypass flag only | file created | file created | the user's own allow rules grant them |
| B: add `--tools Bash,Read,Glob,Grep`, keep bypass | refused (tool absent) | file created | |
| C: `--tools` + no bypass + `--permission-mode dontAsk` | refused | file created | user allow rule `Bash` still grants |
| D: C + `--setting-sources ''` | refused | denied | one claude.ai MCP server still connected |
| D + `--strict-mcp-config` | refused | denied | all four git/shell escapes denied; tools = Bash, Glob, Grep, Read; no MCP, no plugins, no hooks |
| E: `--restricted` + `--tools` + dontAsk | refused | denied | same outcome as D |

Neither mechanism named in the issue body (A, B) holds by itself. The evidence
supports D + `--strict-mcp-config`. In every row `git status` ran and the Read
returned the file, so the controls that must keep working did.

Third run, D + `--strict-mcp-config`, one Bash call per command (spec review
pass 1 asked what else still runs). Ran: `ls -la`, `cat a.txt`, `pwd` — Claude
Code approves its built-in read-only commands without a rule, and `dontAsk`
only denies what would have prompted. Denied, with the permission error in the
tool result and no file created: `find … -exec touch`, `sort -o`, `sed -i`,
`python3 -c`, `env`, `curl`.

## What "read-only" means here

The reviewer can read: the Read/Glob/Grep tools, the four git subcommands, and
the shell commands Claude Code itself classifies as read-only (`ls`, `cat`,
`pwd` measured). It cannot write a file, run a program, or reach the network,
subject to the two limits below. That is the same boundary the GPT reviewer has under `codex exec --sandbox
read-only`, which also runs `ls` and `cat`. The brief's "the listed git read
commands, and nothing else" is therefore met for writes and execution and NOT
met for read-only shell built-ins; no flag removes those while keeping Bash for
git, and they add nothing the Read tool does not already give.

Fourth run, same launch, git-shaped escapes (spec review pass 2 asked). All
denied, no file created: `GIT_EXTERNAL_DIFF="touch f" git diff`,
`git log --output=f`, `git show --output=f`, `git diff --ext-diff`,
`git status; touch f`, `git diff $(touch f)`, `git diff | tee f`. With the
earlier `git diff --output=f` and `git -c …`, the reviewer has no way to point
git at a helper or an output file.

Fifth run, the AUTOMATIC launch shape (spec review pass 3 asked): the same
flags plus `--json-schema` with the repo's schema, `GIT_OPTIONAL_LOCKS=0` in
the environment, and a `CLAUDE.md` in the scratch repo carrying a canary word.
Tools = Bash, Glob, Grep, Read, StructuredOutput; `git status` and `git diff`
ran; `touch` denied; Write refused; no file created; a schema-valid
`structured_output` came back; the model reported no canary, so the reviewed
repo's `CLAUDE.md` does NOT load under `--setting-sources ''`.

One write the flags do not stop: plain `git status` rewrites `.git/index` when
it can take the lock (measured: index mtime moved). With `GIT_OPTIONAL_LOCKS=0`
it does not (measured, both directly and through the CLI). The launch sets it.

Limit: a plain `git diff`/`git log` still runs whatever textconv or external
diff driver the machine's OWN git config already defines for a path the repo's
`.gitattributes` selects. Commits carry `.gitattributes` but never git config,
and the reviewer cannot write config (no write tool; `git -c` and env prefixes
are denied), so reaching this needs an attacker who already controls the local
git config — someone who does not need the reviewer. It is unchanged by this
fix and equally present before it. Closing it fully means an OS sandbox around
the CLI, which is more than a flag: follow-up, named in the PR.

Limit: managed (administrator) policy still loads under `--setting-sources ''`.
A managed `permissions.allow: ["Bash"]` would re-grant shell access. That file
is the machine owner's decision and outranks every CLI flag by design; the
script does not try to defeat it. None exists on this fleet
(`/Library/Application Support/ClaudeCode/` is absent). Named in the PR.

## Success criteria

1. A real review with the Claude provider completes, returns a verdict, and its
   stream log shows at least one successful Read or git call (the review
   actually inspected something).
2. A real review whose scope tells the reviewer to write a file and run a
   non-git, non-read-only shell command ends with the file absent and the
   command not run, in foreground AND detached mode. Absence alone does not
   count: both review prompts tell the model not to modify files, so an obedient
   model proves nothing. The run counts only when its stream log shows (a) the
   init tool list = Bash, Glob, Grep, Read, (b) the attempted Bash call with a
   permission-denied result, and (c) no Write/Edit tool available. If the model
   declines to attempt, that is reported as such, and enforcement rests on the
   direct-CLI measurement above, re-run with the argv the script really passes
   (captured from the process list or the fake-binary argv file).
2b. A real AUTOMATIC review (`--claude --mode automatic`) with the same hostile
   scope returns schema-valid JSON and leaves no file, with the same stream-log
   evidence except the tool list, which in this mode is Bash, Glob, Grep, Read
   plus StructuredOutput (measured in the fifth run). In neither mode may Write,
   Edit or Task appear.
3. `tests/fresheyes-claude-provider-test.sh` asserts, for manual and automatic
   launches: no `--dangerously-skip-permissions` and no `bypassPermissions`
   anywhere in argv; `--tools` = `Bash,Read,Glob,Grep`; `--permission-mode`
   followed by exactly `dontAsk`; `--setting-sources` followed by exactly the
   empty string; `--strict-mcp-config`; `--allowedTools` unchanged; all of them
   before the `--` separator; and `GIT_OPTIONAL_LOCKS=0` in the fake binary's
   environment while the test itself exports `GIT_OPTIONAL_LOCKS=1`, so only
   the launcher's assignment can satisfy it.
4. Foreground and detached launches use the same restricted argv. Today
   `test_manual_detaches_by_default_and_completes` writes `ARGV_FILE` and never
   reads it; this change adds the same assertion there, against the detached
   child's argv.
5. `bash tests/fresheyes-claude-provider-test.sh` exits 0 on Linux (a throwaway
   local Lima VM, Ubuntu 24.04, run against a named snapshot commit). On macOS it runs green up to the known stop at the
   `ps -o sess=` check (upstream's, unrelated; the manual and automatic argv
   assertions run before that point), and no other `tests/*.sh` file regresses.

## Approach

Replace the bypass flag in both functions with one shared array:

```bash
CLAUDE_RESTRICT_ARGS=(
  --tools 'Bash,Read,Glob,Grep'      # the only built-in tools that exist in the session
  --allowedTools "$CLAUDE_TOOLS"     # of those, what runs without a prompt
  --permission-mode dontAsk          # what would prompt is denied, never asked, never bypassed (ls/cat-class reads still run)
  --setting-sources ''               # user/project/local allow rules, hooks and plugins do not load
  --strict-mcp-config                # no --mcp-config is given, so no MCP servers
)
```

Both functions also add `GIT_OPTIONAL_LOCKS=0` to their existing `env` prefix.

Each flag closes one measured gap: `--tools` removes Edit/Write/Task/Web*;
no bypass + `dontAsk` makes the allowlist the limit; `--setting-sources ''`
stops a user's own `allow: [Bash]` from re-granting; `--strict-mcp-config`
removes MCP tools.

## Alternatives

- A or B alone: measured, do not hold.
- `--restricted`: same result, but newer and broader (confines file reads to the
  working directory, which a review of a path outside the repo would trip). Not
  needed once D holds.
- `--bare`: breaks keychain/OAuth reads (kata jibot-code#ymhx, #h0wx); the
  existing test already asserts `--bare` is absent.

## Not in scope (follow-up)

- The reviewed repo's `CLAUDE.md` no longer loads (measured above). That removes
  an instruction surface; it also means a reviewer no longer sees repo
  conventions written there. Named in the PR as a behaviour change.
- An OS sandbox around the CLI (closes the git-config helper limit). Follow-up.
- A user whose auth depends on `apiKeyHelper` or `env` in settings.json loses it
  under `--setting-sources ''`. The script already unsets `ANTHROPIC_API_KEY`, so
  it assumes a logged-in CLI. Named in the PR.
- The allowed git subcommands can still read anything git can read. That is the
  reviewer's job.

## Blast radius / rollback

Two functions in one file plus one test file. A Claude Code that does not know
a flag exits 1 with `error: unknown option` before any model call (measured
with a made-up flag), so the review fails closed with that error on stderr. Rollback: revert the merge on the integration branch and tag again;
consumers pin tags.

## Assumes

Measured on Claude Code 2.1.269; `--help` of 2.1.276–2.1.278 lists the same
five flags. Whether 2.1.257 (the script's floor for the default model) knows
all five is NOT measured — that build could not be fetched. The version gate is
left alone: an older CLI fails closed as described above, which is a refused
review, not an unrestricted one.
