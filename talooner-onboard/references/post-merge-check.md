# Post-merge check

Run this after the onboarding PR/MR is merged. It proves the base branch has the
policy and that the real CI path works.

## 1. Confirm the base branch

```sh
git fetch origin
base=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
[ -n "$base" ] || base=$(git rev-parse --abbrev-ref HEAD)
git show "origin/$base:.talooner/config.yaml"
git show "origin/$base:.talooner/rules.tln"
git show "origin/$base:.talooner/rules.tln.test"
```

`config.yaml` must be present. If the runner logged
`no config on the base branch, no check patterns`, `pr.tests_passing` and
`pr.lint_passing` stay unset and auto-approve never fires.

## 2. Open a throwaway PR

Create a branch and touch a sensitive path with a harmless file. `.talooner/` is
in the starter critical path, so the probe uses that:

```sh
git checkout -b probe/talooner-check
printf 'Throwaway probe. Close without merging.\n' > .talooner/onboarding-probe.md
git add .talooner/onboarding-probe.md
git commit -m "probe: touch a sensitive path"
git push -u origin probe/talooner-check
gh pr create --draft --base "$base" --head probe/talooner-check \
  --title "probe: verify Talooner" \
  --body "Throwaway probe. Checks the sensitive-path rule, comment, block and assignment. Close without merging."
gh pr ready
```

Use the default branch you found in step 1. If the ruleset uses another critical
path, touch that instead.

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
git checkout "$base"
git branch -D probe/talooner-check
```

Delete only the branch this probe created.

## 5. Then

- Leave advice mode only after the team has seen a few real reviews.
- Require the `talooner` check, not the `review` job, in branch protection.
- Keep `.talooner/config.yaml` and the rule tests on the base branch; the review
  reads them from there.
