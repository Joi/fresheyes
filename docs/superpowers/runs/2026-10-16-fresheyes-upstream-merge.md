# Run: fresheyes-upstream-merge

Instruction: Work jibot-code#samy (Joi/fresheyes is the fleet's maintained fork) as /do-it, rung floored at medium. The owed work found on 2026-10-16: upstream 9997894 ("Default reviewers to Claude Opus 5.5 and GPT-6 Sol", 2026-09-26) is not on feat/fleet-snapshot (tag fleet-2026.10.01 = bb76547), and the merge conflicts. Merge it per docs/FLEET.md "When upstream moves", re-merge the rebased fix/gpt61-codex-floor, tag, pin the fleet.

Stage: code-review:branch
Rung: heavy (start-floor heavy: hard-trigger live deploy path — the run ends by moving the fleet's fresheyes pin (fresheyes-fleet-tag set/apply); BR2 REV1 NOV0 INT2 FC1 = 6; Lens: none). The dispatch brief floored it at medium; the evaluator floored it higher.
Spec: docs/superpowers/specs/2026-10-16-fresheyes-upstream-merge-design.md
Plan: docs/superpowers/plans/2026-10-16-fresheyes-upstream-merge.md
Agency project: 01a14234-48d8-7403-958b-4b5b01c4faa4 (tasks chunk1-merge 01a14234-5b76-7ee7-a515-d0f05926e9e6, chunk2-docs-tests 01a14234-5b77-78a5-a4c5-3a82ffa73b1a)
Kata: jibot-code#3vnz (child of jibot-code#samy)
Last reviewed: —
Pre-handoff review: — (repo is NOT repoman-managed; ending is docs/FLEET.md: fast-forward push of feat/fleet-snapshot + tag; dotfiles-private pin)

## Scorecards
Pass 1 [spec]: 3B/0S/0C/1R · fixed -/- · velocity = (—→4, escalation no)
  fresheyes --gpt gpt-5.6-sol high, snapshot 3bedca6, run 20261016-064533-f4dc54. Fixed: (1) the Claude-default decision contradicted routing.toml `astra_built_reviewer_model = "claude-fable-5-1"` (g0rk) and routing-project's literal-line drift check; decision reversed, the fork keeps Fable 5.1. Its claim that do-it injects Fable under Codex is wrong (the watchdog injects only FRESHEYES_PROVIDER=claude), which makes the fix more necessary, not less. (2) Linux run added (FLEET.md "Tests"). (3) rollback now `set --allow-older` + commit + push + pull + apply + check. Rebutted (R): "snapshot commit message vague" — 3bedca6 is a dangling `commit-tree` review snapshot that no branch ever holds.
Pass 1 [plan]: 3B/5S/0C/0R · fixed -/- · velocity = (—→8, escalation no)
  fresheyes --gpt gpt-5.6-sol high, snapshot 3bedca6, run 20261016-064537-2478ba. Fixed all: stage resolved paths before committing; the "nothing else" diff now names SKILL.md's fork paragraph; `git pull --ff-only`; Linux run; tag on origin/feat/fleet-snapshot with a real message and the ls-remote check; `set fleet-2026.10.16` by name; rollback propagates to the live checkout. Rebutted: the snapshot commit message (as above).
Pass 2 [spec]: 0B/1S/0C/0R · fixed 3/3 prior · velocity ↓ (4→1, escalation no)
  heavy's one delta, 3bedca6→2de653b, run 20261016-065046-49fed6. Fixed (no further pass): upstream's two Opus gate tests reach Opus through the default; the spec now converts them to explicit overrides.
  spec: passes 2
Pass 2 [plan]: 2B/4S/0C/0R · fixed 8/8 prior · velocity ↓ (8→6, escalation no)
  heavy's one delta, 3bedca6→2de653b, run 20261016-065052-b29518. Fixed (no further pass, ruling jibot-code#41e2): the Opus default-reliant tests (same as the spec finding); rollback's bare `check`; the routing check now compares against $D/routing/routing.toml; `env -u ... bash "$t"` per file; `git fetch origin` before the rebase retry. Rebutted: "a behaviour-changing SUBSTANTIVE fix gets no independent review / falling-count rule" — ruling jibot-code#41e2 decision 4 gives a delta only to a behaviour-changing BLOCKER fix and retired the falling-count rule; the code pass and roborev's patrol are the later looks.
  plan: passes 2

## Chunks
- [x] merge — ece38e8 upstream merge + c1e04dd fix-branch re-merge (no file changes); ancestry ok; routing-ok; macOS 8/8 rc=0
- [x] docs — FLEET.md, spec, plan, this manifest; Linux (Lima Ubuntu 24.04, bash 5.2.21) 8/8 rc=0 twice at c1e04dd
- [ ] land — fast-forward feat/fleet-snapshot, tag fleet-2026.10.16, dotfiles-private pin, apply + check on macct

## Notes
- 2026-10-16: the plan-delta fixes were applied with a python str.replace that asserted each needle occurred exactly once (not the Edit tool the skill names); same failure-loud property.
- 2026-10-16: first conflict pass used `git checkout --ours` on two files, which drops upstream's clean hunks too; caught before staging and undone with `git checkout -m`, then resolved inside the markers only.
- 2026-10-16: origin/fix/gpt61-codex-floor is already rebased onto 9997894 (c3e395a); rule 2's rebase is done, only the re-merge is owed.
- 2026-10-16: on macct the non-interactive shell PATH resolves `claude` to /opt/homebrew/bin/claude = 2.1.269 (an npm-global install), while login shells resolve ~/.local/bin/claude = 2.1.301. Opus 5.5's gate is 2.1.280, so a Claude review launched from a shell with the Homebrew path first fails the version check by name.
