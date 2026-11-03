# GitHub Actions

Generate the base from the pinned image, then adapt it:

```sh
docker run --rm -e TALOONER_IMAGE=ghcr.io/talooner/talooner-runner:1.1.2 \
  ghcr.io/talooner/talooner-runner:1.1.2 snippet github
```

Write the result to `.github/workflows/talooner.yml`.

## Jobs

- `rules` checks out the repository and runs `tln test .talooner/` on the pinned
  non-root image `ghcr.io/talooner/talooner-runner:1.1.2`.
- `review` needs `rules`, uses the root `-gh` image
  `ghcr.io/talooner/talooner-runner:1.1.2-gh`, and runs the review.
- `resolve` needs `review` and only flips review threads. It gets
  `contents: write`; the Talooner image never does.

Keep the snippet's `rules` → `review` → `resolve` structure.

## Split ruleset

When `.talooner/rules/*.tln` exists, the rules job joins them exactly like
Talooner before testing:

```yaml
      - run: docker run --rm -v "$PWD:/repo" -w /repo --entrypoint sh ghcr.io/talooner/talooner-runner:1.1.2 .talooner/test-rules.sh
```

Keep the `pull_request_review` trigger (`types: [submitted]`) alongside
`pull_request`: it re-runs the review after a human approval, which is what
releases a sensitive PR.

## Run after the other checks

`pr.checks_pending` is true while any check run or commit status on the head
commit is still running, and the base strict ruleset refuses to approve a
moving target. Nothing re-runs the review when CI finishes — GitHub does not
deliver `check_suite` for check suites GitHub Actions created — so a review
that starts with the push is blocked until someone pushes again or comments
`!talooner /review`.

The review job waits for the commit's other checks. Add `actions: read` to the
review job's `permissions:`, and this step after `rules passed on the head
commit` and before `id: talooner`:

```yaml
      - name: wait for the other checks on this commit
        if: >-
          github.event.action != 'closed' &&
          (github.event_name != 'pull_request' || !github.event.pull_request.draft)
        env:
          GH_TOKEN: ${{ github.token }}
          PR: ${{ github.event.pull_request.number || github.event.issue.number }}
        run: |
          sha=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR" --jq .head.sha)
          suite=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" --jq .check_suite_id)
          for _ in $(seq 1 60); do
            pending=$(gh api "repos/$GITHUB_REPOSITORY/commits/$sha/check-runs?per_page=100" \
              --jq "[.check_runs[] | select(.status != \"completed\" and .check_suite.id != $suite)] | length")
            statuses=$(gh api "repos/$GITHUB_REPOSITORY/commits/$sha/status" \
              --jq '[.statuses[] | select(.state == "pending")] | length')
            if [ "$pending" -eq 0 ] && [ "$statuses" -eq 0 ]; then
              echo "no checks pending on $sha"
              exit 0
            fi
            echo "waiting on $pending check run(s) and $statuses status(es)"
            sleep 10
          done
          echo "::warning::checks are still running on $sha after 10 minutes; reviewing without them"
```

The predicate excludes the run's own check suite by id, so `rules`, `review`,
`resolve` and the `talooner` check run never count; everything the repository's
CI started does. Ten minutes is the ceiling: past it the review runs anyway and
the visible comment says to re-run with `!talooner /review`.

The pinned 1.1.2 snippet predates this step. Add it when it is missing; a runner
release that ships it will make the snippet correct on its own, but a generated
workflow without a wait step is not ready.

## Environment

Keep `TALOONER_LICENSE_KEY`, `TALOONER_CHECK_RUN_ID` and `GITHUB_TOKEN`.

Add the chosen model:

- Anthropic: `ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}`.
- OpenAI: `OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}` and
  `TALOONER_MODEL: ${{ vars.TALOONER_MODEL }}`.
- OpenAI-compatible: `TALOONER_MODEL_BASE_URL`, `TALOONER_MODEL`,
  `TALOONER_MODEL_API_KEY`.

Use the provider's exact model id. Do not infer it from another provider's
catalog; the runner's config check does not call the model.

Add the decision model: `CDM_URL`, `CDM_TOKEN`, optional `CDM_MODEL`, optional
`TALOONER_CDM_MIN_CONFIDENCE`.

Add `TALOONER_ADVICE_MODE: "1"` to the review step when advice mode was chosen.

Do not add `TALOONER_APPROVE_WITHOUT_RULESET`.

## Secrets and variables

Secrets:

- `TALOONER_LICENSE_KEY`
- `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` or `TALOONER_MODEL_API_KEY`
- `CDM_TOKEN`

Variables:

- `TALOONER_MODEL_BASE_URL` (OpenAI-compatible only)
- `TALOONER_MODEL`
- `CDM_URL`
- `CDM_MODEL` (optional)
- `TALOONER_CDM_MIN_CONFIDENCE` (optional; default 0.9)

## Settings

- Settings → Actions → General → allow GitHub Actions to create and approve pull
  requests.
- After leaving advice mode, require the `talooner` check in branch protection,
  not the `review` job.

## Fork PRs

A workflow run from a fork gets no secrets, so Talooner cannot review it. A
member's `!talooner` comment can start a review. Comments from other authors are
ignored.

## Team review requests

A team `do require` made with `GITHUB_TOKEN` fails with
`POST /pulls/N/requested_reviewers: 422 Validation Failed`; the whole review run
fails and the `talooner` check comes back neutral. Advice mode does not help
because runtime errors still exit non-zero.

Use `do assign "pr" attr "user.owner"` (with CODEOWNERS or a confirmed user) or a
user target in `teams.yaml`. A team `do require` works with a PAT or GitHub App
token that has organization team visibility. Requesting the same team by hand
with a user token succeeds, so the slug and mapping can be correct and the
Actions token still fails.

## Verifying before the first PR

Run the runner's config check with a real forge token, without printing it:

```sh
TALOONER_PROVIDER=github GITHUB_TOKEN="$(gh auth token)" \
  "$SKILL_DIR/scripts/verify.sh" --repo "$PWD" --strict
```

`verify: INCOMPLETE` means config sanity was skipped; do not call it ready.

## Existing workflow

If `.github/workflows/talooner.yml` exists and is already a Talooner workflow,
show it and ask before changing it. If it is a different workflow, stop and let
the user choose another file.
