# GitLab CI

Generate the base from the pinned image:

```sh
docker run --rm -e TALOONER_IMAGE=ghcr.io/talooner/talooner-runner:1.1.2 \
  ghcr.io/talooner/talooner-runner:1.1.2 snippet gitlab
```

Add `talooner-rules` and `talooner-review` to `.gitlab-ci.yml`.

## Shape

- `talooner-rules` checks out the repository and runs `tln test .talooner/` on
  `ghcr.io/talooner/talooner-runner:1.1.2`.
- `talooner-review` needs `talooner-rules`, runs the review on the same pinned
  image, and sets `GIT_STRATEGY: none` because it does not need a checkout.
- Keep `entrypoint: [""]` in both jobs. Without it GitLab runs the image
  entrypoint instead of the shell.
- Do not set `GIT_STRATEGY: none` on the rules job; it needs the checkout.
- Never name a job exactly `talooner`. The commit status uses that name.

## Stages

Choose `test` if it is declared. Otherwise use the last declared stage. If stages
come only from an `include`, stop and give the user the two jobs to add by hand.

Preserve `stages`, `include`, `default` and unrelated jobs.

## Variables

Set these as project or group CI/CD variables. Do not hardcode them in YAML.

Masked:

- `TALOONER_LICENSE_KEY`
- `GITLAB_TOKEN` — Developer role, `api` scope
- `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` or `TALOONER_MODEL_API_KEY`
- `CDM_TOKEN`

Plain:

- `TALOONER_MODEL_BASE_URL`
- `TALOONER_MODEL`
- `CDM_URL`
- `CDM_MODEL`
- `TALOONER_CDM_MIN_CONFIDENCE`

Add `TALOONER_ADVICE_MODE: "1"` under the review job's `variables:` when advice
mode was chosen.

## Self-managed

Inside GitLab CI, `CI_API_V4_URL` is already set. Outside CI the user sets
`GITLAB_API_URL`. Confirm the host with the user.

## Runner tags

If the project uses tagged runners, ask and add `tags:`.

## Settings

- Settings → Merge requests → "Pipelines must succeed" only after leaving advice
  mode.
- Require the `talooner` status, not a job name.

## Existing file

If `talooner-*` jobs already exist, show them and ask before changing them. If
the file does not exist, create it from the snippet.
