# Privacy and the public boundary

## Local analysis

The user's own coding agent reads the repository, and only after the user
chooses an analysis level. The analysis goes to that agent and its model. It does
not go to Talooner.

Talooner never receives code. In CI it sends:

- forge API calls to read the PR and write the check and comment,
- the user's own model provider calls where a rule asks for them,
- the license check: key, nonce and version,
- one telemetry run summary: versions, verdict, counts, token counts, timings and
  stop reason, with repository and run ids hashed.

No telemetry tier sends code, diffs or comment text.

## Secrets

- Never ask for, print, log, commit or pass a secret value.
- Ask the user to export values in their shell or set them in the CI UI.
- Never write a secret to the repository.
- Check only presence: `[ -n "$VAR" ]`.
- Do not paste a secret into chat. If the user does, tell them to rotate it.

## The skill's boundary

Published skill files contain only public information:

- the public image `ghcr.io/talooner/talooner-runner`,
- `talooner.dev`, `tln-lang.org`, `github.com/opentalon/tln-language`,
- `github.com/Talooner/feedback`, `github.com/Talooner/talooner-skills`,
- public provider sites.

They contain no private source repository, internal path, internal email, token,
cluster credential, or old cluster setup variable.

## Repository safety

- Require a clean tree.
- Never force-push, reset, stash or overwrite user changes.
- Never commit `.env`, keys, credentials or generated secrets.
- Never change branch protection, repository settings or secrets automatically.
  Give the user a checklist.
