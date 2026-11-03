# Post-merge check

Run this after the onboarding PR/MR is merged. It proves the base branch has the
policy and that the real CI path works.

## 1. Confirm the base branch

```sh
git fetch origin
git show origin/master:.talooner/config.yaml
git show origin/master:.talooner/rules.tln
git show origin/master:.talooner/rules.tln.test
```

`config.yaml` must be present. If the runner logged
`no config on the base branch, no check patterns`, `pr.tests_passing` and
`pr.lint_passing` stay unset and auto-approve never fires.

## 2. Open a throwaway PR

Create a branch and touch a sensitive path with a harmless file:

```sh
git checkout -b probe/talooner-check
mkdir -p internal/prompts
printf 'Throwaway probe. Close without merging.\n' > internal/prompts/onboarding-probe.md
git add internal/prompts/onboarding-probe.md
git commit -m "probe: touch a sensitive path"
git push -u origin probe/talooner-check
gh pr create --draft --base master --head probe/talooner-check \
  --title "probe: verify Talooner" \
  --body "Throwaway probe. Checks the sensitive-path rule, comment, block and assignment. Close without merging."
gh pr ready
```

Adjust the path and base branch to the repository.

## 3. Confirm the run

- `rules` is green and runs the rule tests.
- `review` is green.
- The `talooner` check is `success` in advice mode, with
  `Changes requested (advisory)`.
- A sticky review comment names the sensitive-path rule.
- The PR has an assignee. If it says `assign MR to nobody`, add CODEOWNERS or use
  a confirmed user target.
- The review log shows the ruleset from `.talooner/`, not the legacy path.
- If AI review is on, a documented unit is reviewed and the log shows
  `code units resolved` and `findings received`.
- If the decision model is configured, check the log for the decision call and
  the facts it wrote. A missing call means the decision path is still unproven.

## 4. Close it

```sh
gh pr close probe/talooner-check --comment "Probe verified; closing without merging."
git push origin --delete probe/talooner-check
git checkout master
git branch -D probe/talooner-check
```

Delete only the branch this probe created.

## 5. Then

- Leave advice mode only after the team has seen a few real reviews.
- Require the `talooner` check, not the `review` job, in branch protection.
- Keep `.talooner/config.yaml` and the rule tests on the base branch; the review
  reads them from there.
