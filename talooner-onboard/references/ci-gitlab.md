# GitLab CI

Generate the base from the pinned image:

```sh
docker run --rm -e TALOONER_IMAGE=ghcr.io/talooner/talooner-runner:1.2.1 \
  ghcr.io/talooner/talooner-runner:1.2.1 snippet gitlab
```

Add `talooner-command`, `talooner-rules` and `talooner-review` to
`.gitlab-ci.yml`.

## Shape

- `talooner-command` runs only on `$CI_PIPELINE_SOURCE == "trigger"` and turns
  the webhook payload into `REVIEW_MR_IID` / `REVIEW_NOTE_ID` with
  `talooner-step note-env`, passed on as a dotenv artifact. A trigger that is not
  a `!talooner` comment on a merge request yields an empty artifact and the
  review job exits 0.
- `talooner-rules` checks out the repository and runs `tln test .talooner/` on
  `ghcr.io/talooner/talooner-runner:1.2.1`. For a split ruleset, run
  `sh .talooner/test-rules.sh` instead; it joins the files like Talooner does.
- `talooner-review` needs `talooner-rules` and, optionally, `talooner-command`,
  runs the review on the same pinned image, and sets `GIT_STRATEGY: none`
  because it does not need a checkout.
- Both `talooner-rules` and `talooner-review` also run on the `trigger` source,
  so the review has a rules check in a comment-command pipeline too.
- Keep `entrypoint: [""]` in every job. Without it GitLab runs the image
  entrypoint instead of the shell.
- Do not set `GIT_STRATEGY: none` on the rules job; it needs the checkout.
- Never name a job exactly `talooner`. The commit status uses that name.

## Comment commands

`!talooner /review` and `!talooner /stop` in a merge request note start a trigger
pipeline: merge request pipelines cannot see notes. Add one project webhook
(Settings → Webhooks, trigger: Comments) whose URL is

```
https://<gitlab host>/api/v4/projects/<project id>/ref/<default branch>/trigger/pipeline?token=<pipeline trigger token>
```

Create the token under Settings → CI/CD → Pipeline trigger tokens; it lives in
the webhook URL and nowhere in the YAML. Without the webhook the jobs still run
on merge request events, and comment commands do nothing.

## Stages

`pr.checks_pending` counts the commit statuses on the merge request's head: the
project's own CI jobs. A job in the same stage runs beside them, so the review
starts while their statuses are pending and the base ruleset refuses to pass it.

Put `talooner-review` after the check jobs:

- the last declared stage, not `test` when the project's tests run there; or
- if the pipeline already uses `needs:`, add every test/lint job to
  `talooner-review`'s `needs` (`needs: [talooner-rules, test, lint]`).

Keep `talooner-rules` a separate earlier job and keep
`needs: [talooner-rules]` on the review. If stages come only from an `include`,
stop and give the user the two jobs to add by hand.

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

## Reviewer requests

A team `do require "review.<name>"` works on GitLab. Map the name in
`.talooner/teams.yaml` to a group path, or to a list of users that needs no host
lookup. `do assign "pr" attr "user.owner"` also works when CODEOWNERS or a
confirmed user exists.

## Existing file

If `talooner-*` jobs already exist, show them and ask before changing them. If
the file does not exist, create it from the snippet.
