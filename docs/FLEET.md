# The fleet fork

`Joi/fresheyes` is the fork of `danshapiro/fresheyes` that Joi's machines run.
Joi decided on 2026-09-21 to maintain it (kata jibot-code#samy): fresheyes is
the required review before every repoman handoff, and several open upstream
issues are defects in that review.

This file exists only on the integration branch. It is not offered upstream.

## Branches

| Ref | What it is |
|-----|------------|
| `upstream/main` | Dan Shapiro's `main`. Read-only for us. |
| `origin/main` | A mirror of `upstream/main`. Fast-forward only; nothing of ours is committed there. |
| `origin/feat/fleet-snapshot` | The integration branch: `upstream/main` plus our patches. The only branch a machine runs. |
| `origin/fix/*`, `origin/feat/*` | One branch per fix, each cut from `upstream/main`, each with its own upstream PR. `fix/sol-review-default` is the exception (below). |
| `fleet-YYYY.MM.DD` | Annotated tags on the integration branch. Consumers pin a tag. |

The remotes are `origin` = `git@github.com:Joi/fresheyes.git` and
`upstream` = `https://github.com/danshapiro/fresheyes.git`. A clone that lacks
`upstream` adds it with `git remote add upstream <url>`. Fetch each remote by
name (`git fetch origin && git fetch upstream`); `git fetch origin upstream`
reads `upstream` as a refspec and fails.

## The four rules

1. There is one integration branch, `feat/fleet-snapshot`. It is
   `upstream/main` plus our patches, tagged `fleet-YYYY.MM.DD`. Consumers pin a
   tag, never a working tree (kata jibot-code#knpg, jibot-code#112s).
2. Every fix is its own small branch cut from `upstream/main`, with its own
   pull request against `danshapiro/fresheyes` `main`. The same branch is then
   merged into the integration branch. When Dan pushes, rebase the fix branch.
3. The fork is for fleet use only until a LICENSE lands upstream (kata
   jibot-code#psha). Do not redistribute it and do not put it in the
   mujin-public path.
4. It is not a rename and not a rewrite. The diff from upstream stays small
   enough that Dan can take every piece of it.

## Where the fork differs from the README

The default GPT reviewer is `gpt-5.6-sol`, not `gpt-6-astra`. Upstream made
Astra the default in 2f8e2b3; the fork keeps Sol through
`fix/sol-review-default` because of the fleet's review cost ruling (kata
jibot-code#g0rk). The lookup order in `skills/fresheyes/fresheyes.sh` is
`FRESHEYES_GPT_MODEL`, then the older `FRESHEYES_MODEL`, then `gpt-5.6-sol`, so
a Mac with neither variable set runs Sol, and a Mac that still sets
`FRESHEYES_MODEL` runs whatever that names. The README's sentences about Astra
being the default describe upstream, not this branch. To use Astra for one
review, set the variable on that command alone, so it does not stay in the
shell for the next review:

```bash
FRESHEYES_GPT_MODEL=gpt-6-astra bash skills/fresheyes/fresheyes.sh --gpt "<scope>"
```

`fix/sol-review-default` is fleet policy, not a fix, so it has no upstream pull
request and is the one branch outside rule 2. It was cut before
`fix/codex-skip-git-repo-check` was merged and still carries a copy of that fix
(12a2ff2, the same change as fd5e85b). Nothing is lost by that on the
integration branch; do not open a pull request from it as it stands.

The Claude reviewer default is upstream's, `claude-fable-5-1`.

## Making a fix

```bash
git fetch origin && git fetch upstream
git switch -c fix/<short-name> upstream/main
# change, test, commit
git push -u origin fix/<short-name>
gh pr create -R danshapiro/fresheyes --base main --head Joi:fix/<short-name>
```

Then merge it into the integration branch, from a worktree and never from a
machine's running checkout:

```bash
git switch -c integrate-<short-name> origin/feat/fleet-snapshot
git merge --no-ff origin/fix/<short-name>
# run the tests (below), get an independent review, then:
git push origin HEAD:refs/heads/feat/fleet-snapshot    # must be a fast-forward
```

Merge the branch; do not cherry-pick its commits. A cherry-pick puts the change
on the integration branch under new hashes, so git can no longer say which fix
branches are in it. `fix/version-probe-timeout` is in that state today: its
four commits are on the integration branch under different hashes.

The fix tasks mostly edit `skills/fresheyes/fresheyes.sh`, so do them one at a
time.

## When upstream moves

```bash
git fetch origin && git fetch upstream
git push origin upstream/main:refs/heads/main           # fast-forward the mirror
git switch -c integrate-upstream origin/feat/fleet-snapshot
git merge upstream/main
# read the default-model line (next paragraph), run the tests, get a review, then:
git push origin HEAD:refs/heads/feat/fleet-snapshot    # must be a fast-forward
```

After the merge, read the default-model lines in
`skills/fresheyes/fresheyes.sh` (`MODEL="${FRESHEYES_GPT_MODEL:-...}"`) and
confirm the GPT default is still `gpt-5.6-sol`. An upstream change to that line
merges without a conflict only when it does not touch it, so a clean merge is
not evidence.

A fix branch is rebased onto the new `upstream/main` only when its pull request
no longer applies there. Force-push it with `--force-with-lease`, then merge the
rewritten head into the integration branch again: the rebase gave the commits
new hashes, so without that second merge the branch reads as unmerged. The
merge changes no files when the rebase changed none. The integration branch
itself is never rebased or force-pushed, because tags and consumers point into
it.

## Tests

```bash
failed=0
for t in tests/*.sh; do
  bash "$t" >"/tmp/$(basename "$t").log" 2>&1 </dev/null
  rc=$?; echo "$t rc=$rc"; [ "$rc" -eq 0 ] || failed=1
done
[ "$failed" -eq 0 ]    # the loop's own status says nothing; this line does
```

Unset `FRESHEYES_GPT_MODEL`, `FRESHEYES_MODEL`, `FRESHEYES_CLAUDE_MODEL`,
`FRESHEYES_PROVIDER` and `FRESHEYES_REASONING` first, or the fleet's shell pins
hide what the defaults are. The tests use fake `codex` and `claude` binaries
and start no real review.

Never run `fresheyes.sh --help`, or any flag it does not know: it takes the
flag as the review scope and launches a real review (upstream #6).

On macOS three files fail on unmodified `upstream/main` as well, so a failure
there is not a regression from our patches (measured 2026-09-21, macOS 26.6.2,
Homebrew `setsid` installed):

- `fresheyes-claude-provider-test.sh`: the session check reads
  `ps -o sess=`, which prints `0` for every process on macOS.
- `fresheyes-detach-test.sh`: the literal `${HOME}` / `$PATH` scope case.
- `fresheyes-progress-test.sh`: BSD `wc -l` pads its output with spaces.

On a Mac without `setsid` more of them fail (upstream #16).

Each test file stops at its first failed assertion, so on macOS the assertions
after those three points do not run at all. A macOS run therefore proves less
than it appears to: a file counts as a known failure only when its `FAIL` line
is the one listed above, and a change that touches what those files cover is
also run on Linux, where upstream develops them, before it is tagged. The Linux
result has not been measured by us yet.

## Tagging

Tag the commit that was pushed to `feat/fleet-snapshot`, with an annotated tag
named for the day:

```bash
git tag -a fleet-YYYY.MM.DD -m "<what changed since the previous tag>" origin/feat/fleet-snapshot
git push origin fleet-YYYY.MM.DD
git describe --tags --exact-match origin/feat/fleet-snapshot    # prints the tag, or fails
```

Without `--exact-match`, `git describe` succeeds on an untagged head by naming
an older tag plus a distance.

A second tag on the same day takes a suffix: `fleet-YYYY.MM.DD.2`. A pushed tag
is never moved. Push nothing to `danshapiro/fresheyes`: fix branches are pushed
to `origin`, and a pull request is how they reach Dan.
