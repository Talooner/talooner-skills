# Troubleshooting

## Docker

- `docker: command not found` — install Docker or start Docker Desktop.
- Image pull fails — check network access to `ghcr.io`; retry the pinned tag.
- Permission errors on written files — run the container with
  `--user "$(id -u):$(id -g)"`.

## `tln test` fails

- Compile error — fix the rule or the test. Read the line number in the error.
- Unknown action — check the verb. `llm_review` is not a verb; use an `enrich`
  block. `notify` has no executor.
- Duplicate `strict` rule — remove it; the base ruleset already provides it.
- A `require` target does not resolve — add it to `.talooner/teams.yaml` or use a
  real user.
- A split ruleset shares `define`s across files — `tln test .talooner/` tests each
  file on its own. Keep shared definitions in a file that starts with `_`.

## Generated files are ignored

- `.talooner/config.yaml` is missing from CI — a bare `config.yaml` pattern in
  `.gitignore` matches it at any depth. Add `!.talooner/config.yaml` after that
  pattern.
- `.talooner/rules.tln.test` is missing — a `*.test` pattern (for Go test
  binaries) matches it. Add `!.talooner/*.tln.test`.
- `verify.sh` reports "generated files are ignored by git"; fix the negation and
  rerun. A file that only exists on disk never reaches CI.

## Legacy Talooner path

`verify.sh` reports a legacy `.github/talooner/` path. The runtime still reads it,
but only when `.talooner/` is absent; a parallel ruleset makes the two disagree.
Read the legacy rules, propose a merge, and migrate them. `doctor.sh` reports
`legacy_talooner_files` before anything is written.

## Review requests

- `POST /pulls/N/requested_reviewers: 422` on GitHub Actions — `GITHUB_TOKEN`
  cannot request a team review. Use `do assign` or a user target; use a
  PAT/GitHub App for a team.
- `assignee_unresolved` — `user.owner` is unset for a new file with no CODEOWNERS
  and no last toucher. Add CODEOWNERS or use a confirmed user.
- `requires "review.…"` without `do require` — the verdict requests nobody.
  Remove `requires`, or add the matching `do require`.

## Readiness

- `verify: INCOMPLETE` — config sanity was skipped. Rerun with `--strict` and a
  real forge token; do not call it ready before that passes.
- Credentials exported in an interactive shell are invisible to the agent's
  shell. Put them in `~/.zshenv` or start the agent from that shell.
- A check says "1 rule fired" but there is no comment — the base strict rule that
  blocks while checks are pending has no comment action. Add a tenant rule that
  comments on `pr.checks_pending == true`.

## License

- `TALOONER_LICENSE_KEY is not set` — set the masked variable. Protected variables
  are not available on unprotected branches.
- "Talooner license inactive" — the license is expired or revoked, or the runner
  cannot reach the license server. Allow outbound HTTPS.
- Local decode says expired — it may be an old key. Get the current key from the
  license page and decode again.
- Local decode says no AI review — the key does not include `ai_review`. Get the
  current key after upgrading.
- Local decode says valid — that is not proof. The online check is authoritative.

## Decision model

- `CDM_URL` without `CDM_TOKEN` (or the reverse) — set both.
- A decision rule never fires — check `pr.risk_certainty`; the gate is 0.85.
- A failed decision returns `chosen: "error"` and certainty 0, so confident rules
  do not fire. Add a rule that handles the error if the user wants one.
- SubQ retention — enable zero data retention before real code reaches it.

## GitHub

- `TAL-E-REVIEW-PERM` — Settings → Actions → General → allow GitHub Actions to
  create and approve pull requests.
- No review on a fork PR — fork runs get no secrets. A member's `!talooner`
  comment can start a review.
- `pr.tests_passing` never true — set the real check names in
  `.talooner/config.yaml`.
- The check is advisory — remove `TALOONER_ADVICE_MODE` to block.
- The model id looks wrong only on the first real PR — config sanity does not call
  the model. Use the provider's exact id.
- No review on the onboarding PR — the base branch has no ruleset yet. Merge
  first, then open a small test PR.

## GitLab

- 403 from the API — the token needs the Developer role and `api` scope.
- Job does not start — keep `entrypoint: [""]`.
- A job named `talooner` conflicts with the commit status. Rename it.
- `pr.tests_passing` never true — set the real job keys in
  `.talooner/config.yaml`.
- Self-managed host — set `GITLAB_API_URL` outside CI; inside CI GitLab sets
  `CI_API_V4_URL`.
- "Pipelines must succeed" blocks everything — enable it only after leaving
  advice mode.

## CI wiring

- `verify.sh` says the review image is wrong — use the pinned `-gh` image on
  GitHub and the pinned non-root image for rules and on GitLab.
- `verify.sh` says a job is missing — regenerate from `snippet` and merge the jobs
  into the existing file.

## Still stuck

Open an issue at `https://github.com/Talooner/feedback` with the command, the
error and the versions from `docker run --rm ghcr.io/talooner/talooner-runner:1.1.2 version`.
Never include a key, token or code.
