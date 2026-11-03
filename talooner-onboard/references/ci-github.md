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
