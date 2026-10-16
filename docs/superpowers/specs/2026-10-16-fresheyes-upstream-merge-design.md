# Merge upstream 9997894 into the fleet fork — design

Kata: jibot-code#3vnz (parent jibot-code#samy). Date: 2026-10-16.

## Problem

On 2026-09-26 Dan Shapiro pushed 9997894 to `danshapiro/fresheyes` `main`:
the Claude reviewer default moves from `claude-fable-5-1` to `claude-opus-5-5`
(with its own Claude Code floor, 2.1.280), and the GPT default moves from
`gpt-6-astra` to `gpt-6-sol`. The fleet's integration branch
`feat/fleet-snapshot` (tag `fleet-2026.10.01` = bb76547) does not carry it, so
the fork is one upstream commit behind and rule 1 of `docs/FLEET.md`
("`upstream/main` plus our patches") no longer holds. `git merge upstream/main`
conflicts in three files: `README.md`, `skills/fresheyes/fresheyes.sh` (the GPT
default line) and `tests/fresheyes-gpt-provider-test.sh` (three assertions on
the default model). The Claude default line merges without a conflict, to
upstream's `claude-opus-5-5`.

Since then `origin/fix/gpt61-codex-floor` (upstream PR #29, open) has been
rebased onto 9997894 as c3e395a. Rule 2 asks for that rewritten head to be
merged into the integration branch again.

## Decisions

Both defaults are fleet routing, and the routing source of truth is
dotfiles-private `routing/routing.toml` `[review]` (ruling jibot-code#g0rk):
`fresheyes_gpt_model = "gpt-5.6-sol"` and
`astra_built_reviewer_model = "claude-fable-5-1"`. `scripts/routing/routing-project`
compares fresheyes.sh's literal default lines against those two fields, so the
merged script must keep both values or the routing board reports drift.

1. **GPT default stays `gpt-5.6-sol`** (the existing `fix/sol-review-default`
   patch). Rejected: upstream's `gpt-6-sol`, which changes the fleet's reviewer
   under g0rk without a measurement.
2. **Claude default stays `claude-fable-5-1`.** The auto-merged line is set back
   by hand. g0rk's rule is "Astra-built -> Fable": a Codex executor's do-it
   review sets only `FRESHEYES_PROVIDER=claude` (do-it's watchdog injects the
   provider, not a model), so the fresheyes default IS that reviewer's model.
   Rejected: taking upstream's `claude-opus-5-5`, which would move every
   Astra-built review to Opus 5.5 and raise its Claude Code floor to 2.1.280 as
   a side effect of a merge. Whether that reviewer should be Opus 5.5 (jibot-code#fx33
   made Opus 5.5 the default dispatch lane) is a routing change to
   `routing.toml` first; this fork then follows it. Filed as a follow-up.
   This reverses the first `decided:` comment on jibot-code#3vnz, made before
   the spec review found the routing pin; posted as `notice:`.
   Cost: the fork now carries two default-model lines that differ from
   upstream. They live in the same fleet-policy patch, `fix/sol-review-default`'s
   territory, and the diff stays a few lines (rule 4). Upstream's
   `claude-opus-5-5*` version-gate arm (2.1.280) is kept: it applies only when
   a caller names Opus 5.5.
3. **README** takes upstream's paragraphs (FLEET.md: the README describes
   upstream) and keeps the fork's GPT-6.1 floor sentence from
   `fix/gpt61-codex-floor`.
4. **Tests.** `tests/fresheyes-gpt-provider-test.sh` keeps the fork's
   `gpt-5.6-sol` default assertions and the fork's boundary-version case (it
   sets `FRESHEYES_GPT_MODEL=gpt-6-astra` and asserts it). Upstream's
   `tests/fresheyes-claude-provider-test.sh` (fakes at 2.1.283, Opus gate cases)
   merges cleanly, but its two new Opus gate cases
   (`test_opus_5_5_rejects_old_claude_code`, `test_opus_5_5_accepts_exact_minimum`)
   reach Opus through the DEFAULT (`FRESHEYES_CLAUDE_MODEL=` empty). With the
   default back on Fable they are converted to explicit overrides
   (`FRESHEYES_CLAUDE_MODEL=claude-opus-5-5`) and their comments and messages
   say so; any other assertion on the default Claude model expects
   `claude-fable-5-1`.

## Approach

`docs/FLEET.md` "When upstream moves", "Tests" and "Tagging":

- Fast-forward `origin/main` to `upstream/main`.
- `integrate-upstream-20261016` from `origin/feat/fleet-snapshot`;
  `git merge upstream/main`, resolve as above, stage, commit.
- `git merge --no-ff origin/fix/gpt61-codex-floor` (rule 2 re-merge).
- `docs/FLEET.md`: both default paragraphs (upstream now `gpt-6-sol` and
  `claude-opus-5-5`; the fork keeps `gpt-5.6-sol` and `claude-fable-5-1` per
  routing.toml), the tag paragraph, the 2026-10-16 test results.
- Tests on macOS (macct) and on Linux (Lima Ubuntu 24.04 against the named
  commit, FLEET.md's recipe), `FRESHEYES_*` unset.
- One independent review of the whole branch, fast-forward push, annotated tag
  `fleet-2026.10.16` on `origin/feat/fleet-snapshot`, verified by
  `git ls-remote` against the remote branch.
- dotfiles-private: `scripts/fresheyes-fleet-tag set fleet-2026.10.16`, commit,
  push to `origin/main`; in `~/dotfiles-private` `git pull --ff-only`, then
  `scripts/fresheyes-fleet-tag apply` and `check`.

## Success criteria

- `git merge-base --is-ancestor upstream/main fleet-2026.10.16` and
  `git merge-base --is-ancestor origin/fix/gpt61-codex-floor fleet-2026.10.16`
  are both true.
- At the tag, `fresheyes.sh` defaults are `gpt-5.6-sol` and `claude-fable-5-1`.
  `git diff upstream/main fleet-2026.10.16 -- skills tests` is: the two default
  lines, the `gpt-6.1*` arm, the fork's GPT-review paragraph in
  `skills/fresheyes/SKILL.md` (from `fix/sol-review-default`), and the test
  hunks for those. Nothing else.
- `scripts/routing/routing-project` reports no fresheyes default drift against
  the new snapshot (or the same check by hand: both default lines equal the
  routing.toml values).
- All 8 test files rc=0 on macOS (macct) and on Linux (Lima Ubuntu 24.04).
- `fresheyes-fleet-tag check` prints nothing on macct; the pin commit is on
  dotfiles-private `origin/main`.

## Blast radius and rollback

Every fleet fresheyes consumer pins a tag. With both defaults kept, a fleet Mac
sees no reviewer-model change: what moves is upstream's README text, the
Opus 5.5 gate arm (used only when named), the test fakes, and the re-merged
GPT-6.1 floor, which was already on `fleet-2026.10.01`.

Rollback, the same path as the forward pin: in a dotfiles-private worktree
`scripts/fresheyes-fleet-tag set --allow-older fleet-2026.10.01` (an older tag
is refused without the flag), commit the three pin paths, push to `origin/main`;
in `~/dotfiles-private` `git pull --ff-only`, `scripts/fresheyes-fleet-tag apply`,
`check`. The integration branch is never rewritten, so the old tag stays valid.

## Open questions

None blocking. Moving the Astra-built reviewer to Opus 5.5, and the fleet GPT
reviewer to `gpt-6-sol`, are routing.toml decisions under g0rk.
