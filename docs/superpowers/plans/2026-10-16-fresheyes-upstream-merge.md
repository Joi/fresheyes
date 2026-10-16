# Plan: merge upstream 9997894 into the fleet fork

Spec: docs/superpowers/specs/2026-10-16-fresheyes-upstream-merge-design.md
Kata: jibot-code#3vnz. Worktree: /Users/joi/repos/.worktrees/fresheyes-integrate-upstream-20261016,
branch integrate-upstream-20261016 from origin/feat/fleet-snapshot (bb76547).
`W=/Users/joi/repos/.worktrees/fresheyes-integrate-upstream-20261016`,
`D=/Users/joi/repos/.worktrees/samy-joi-fresheyes-is-the-fleet-s-maintained-` (dotfiles-private worktree).

## Chunk 1 — merge

- [ ] `git merge upstream/main` (already started; conflicts in three files).
- [ ] `skills/fresheyes/fresheyes.sh`: GPT line (82) keep `gpt-5.6-sol`; Claude line (86), which
      auto-merged to `claude-opus-5-5`, set back to `claude-fable-5-1`. Keep upstream's
      `claude-opus-5-5*` gate arm (2.1.280) above the Fable arms.
- [ ] `tests/fresheyes-gpt-provider-test.sh`: all three hunks take ours (`gpt-5.6-sol` manual and
      automatic assertions; the boundary case's explicit `gpt-6-astra` env line and assertion).
- [ ] `tests/fresheyes-claude-provider-test.sh` (merged cleanly): `test_opus_5_5_rejects_old_claude_code`
      and `test_opus_5_5_accepts_exact_minimum` set `FRESHEYES_CLAUDE_MODEL=` and reach Opus through
      the default; change both to `FRESHEYES_CLAUDE_MODEL=claude-opus-5-5` and reword their
      "default" comments and messages. Then `grep -n 'opus-5-5\|fable-5-1'` over tests/: every
      assertion on the DEFAULT model expects `claude-fable-5-1`.
- [ ] `README.md:33`: upstream's paragraph with the fork's GPT-6.1 clause after "GPT-6 Sol requires
      Codex CLI 0.153.1 or newer". Upstream's Claude paragraph unchanged (it describes upstream).
- [ ] `grep -rn '^<<<<<<<\|^=======$\|^>>>>>>>' README.md skills tests` prints nothing;
      `git add README.md skills/fresheyes/fresheyes.sh tests/`; `git diff --cached --name-only
      --diff-filter=U` empty; `git commit --no-edit`.
- [ ] `git merge --no-ff origin/fix/gpt61-codex-floor`; on conflict resolve to the content already on
      the branch (bb76547 is the same change), `git add` the paths, commit.
- [ ] Verify: `git merge-base --is-ancestor upstream/main HEAD && git merge-base --is-ancestor
      origin/fix/gpt61-codex-floor HEAD`; `git diff upstream/main HEAD -- skills tests` is the two
      default lines, the `gpt-6.1*` arm, SKILL.md's fork GPT paragraph and those tests' hunks.
- [ ] Routing check, a real comparison:
      `g=$(sed -n 's/^ *MODEL="${FRESHEYES_GPT_MODEL:-${FRESHEYES_MODEL:-\([^}]*\)}}"$/\1/p' skills/fresheyes/fresheyes.sh)`,
      `c=$(sed -n 's/^ *MODEL="${FRESHEYES_CLAUDE_MODEL:-${FRESHEYES_MODEL:-\([^}]*\)}}"$/\1/p' skills/fresheyes/fresheyes.sh)`;
      `grep -q "^fresheyes_gpt_model = \"$g\"" $D/routing/routing.toml && grep -q "^astra_built_reviewer_model = \"$c\"" $D/routing/routing.toml && echo routing-ok`.

## Chunk 2 — docs and tests

- [ ] `docs/FLEET.md`: "Where the fork differs" — upstream's defaults are now `gpt-6-sol` and
      `claude-opus-5-5` (9997894); the fork keeps `gpt-5.6-sol` and `claude-fable-5-1` because
      dotfiles-private `routing/routing.toml` pins them (g0rk) and routing-project checks the literal
      lines; the Claude line is a fork difference since this merge. Intro paragraph: since
      `fleet-2026.10.16` the branch also carries `fix/gpt61-codex-floor` (PR #29). Tests section:
      2026-10-16 macOS and Linux results.
- [ ] Commit FLEET.md, spec, plan, manifest as one docs commit.
- [ ] macOS: FLEET.md loop, each file run as `env -u FRESHEYES_GPT_MODEL -u FRESHEYES_MODEL -u
      FRESHEYES_CLAUDE_MODEL -u FRESHEYES_PROVIDER -u FRESHEYES_REASONING bash "$t"`, logs to the
      scratchpad; all 8 rc=0.
- [ ] Linux: FLEET.md's Lima recipe against `git archive HEAD`; all 8 rc=0; `limactl delete -f fe-test`.
      A failure re-runs once before it is read as a regression (FLEET.md's flake note, jibot-code#3t12).

## Chunk 3 — review and land

- [ ] One fresheyes pass (watchdog, Sol/high, the vendored snapshot under ~/dotfiles-private — never
      this worktree's script) over `git diff origin/feat/fleet-snapshot...HEAD` at the committed
      head. Fix every BLOCKER; fix or rebut every SUBSTANTIVE in the kata comment; a BLOCKER fix
      that changes behaviour gets the one delta pass.
- [ ] `git push origin upstream/main:refs/heads/main` (mirror; fast-forward).
- [ ] `git push origin HEAD:refs/heads/feat/fleet-snapshot` (refused unless fast-forward).
- [ ] `git fetch origin`; `git tag -a fleet-2026.10.16 -m "fleet-2026.10.16: upstream 9997894
      merged (README, Opus 5.5 gate arm, test fakes); fork keeps gpt-5.6-sol and claude-fable-5-1
      per routing.toml; fix/gpt61-codex-floor re-merged (PR #29)" origin/feat/fleet-snapshot`;
      `git push origin fleet-2026.10.16`; `git fetch origin`; `git ls-remote --tags origin
      'refs/tags/fleet-2026.10.16^{}'` equals `git rev-parse origin/feat/fleet-snapshot`.
- [ ] In `$D`: `scripts/fresheyes-fleet-tag set fleet-2026.10.16`; `git add codex/skills/fresheyes
      codex/skills/fresheyes.tag claude/config/settings.json`; commit; `git push origin HEAD:main`
      (fast-forward; if refused, `git fetch origin && git rebase origin/main`, then push again).
- [ ] In `~/dotfiles-private`: `git pull --ff-only`; `scripts/fresheyes-fleet-tag apply`;
      `scripts/fresheyes-fleet-tag check` prints nothing.
- [ ] Close-out comment on jibot-code#3vnz; close with evidence; coordinator note on jibot-code#samy.

## Rollback

In `$D`: `scripts/fresheyes-fleet-tag set --allow-older fleet-2026.10.01`; stage the three pin paths;
commit; `git push origin HEAD:main`. In `~/dotfiles-private`: `git pull --ff-only`;
`scripts/fresheyes-fleet-tag apply`; `scripts/fresheyes-fleet-tag check`. The integration branch and its older tags are never
rewritten.
