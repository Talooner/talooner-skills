---
name: talooner-onboard
description: Onboard the current repository to Talooner — interview the user, write .talooner/onboarding.md, write tested tln rules and guides, add GitHub Actions or GitLab CI, verify with the pinned runner image, and prepare a draft PR/MR. Use when the user asks to onboard this repo to Talooner, set up Talooner rules, or add a Talooner PR guard.
metadata:
  version: 1.2.0
  runner_version: 1.1.2
---

# Onboard a repository to Talooner

Talooner reviews every pull request against the policy in `.talooner/rules.tln`.
This skill runs in the user's coding agent. It asks a few questions, writes the
spec, writes rules and tests, writes guides and CI, verifies everything with the
pinned runner image, and prepares a draft PR/MR.

Docs: `https://talooner.dev/onboard/` · rules: `https://talooner.dev/rules/` ·
language: `https://tln-lang.org/`

## Paths

The skill is installed somewhere outside the target repository. Resolve the
installed folder once and use absolute paths:

```sh
SKILL_DIR="$HOME/.claude/skills/talooner-onboard"
```

Use the real install location for the user's agent. Then run every script as:

```sh
"$SKILL_DIR/scripts/doctor.sh"
"$SKILL_DIR/scripts/decode-license.sh"
"$SKILL_DIR/scripts/verify.sh" --repo "$PWD"
```

Never `cd` into the skill folder. The scripts take the target repository from
`--repo` or from the current directory, and they do not depend on the current
directory being the skill folder.

## Hard rules

- This is interactive. Never run the whole flow automatically.
- Ask one question at a time and wait for the answer. Use one question object
  per call; silence is not consent.
- Never ask for, print, log, commit or pass a secret value. The user sets secrets
  in their shell or the CI UI.
- Never write a secret to the repository.
- Commit explicit paths only. Never use `git add -A` or `git add .`.
- Never delete a branch you did not create in this run. List other branches and
  let the user decide.
- Never commit, push, open a PR/MR, change branch protection or install software
  without an explicit yes.
- Work only in the repository root confirmed by `git rev-parse --show-toplevel`.
  If the working tree is dirty, stop and ask the user to commit or stash.
- Do not read source files before the analysis-consent step.
- Do not claim success until `"$SKILL_DIR/scripts/verify.sh" --strict` passes.
  `verify: INCOMPLETE` means not ready.
- Use the pinned runner image `ghcr.io/talooner/talooner-runner:1.1.2`, never
  `latest`, for generated CI and local validation.
- The review runs last. Generated CI starts it only after the repository's own
  tests and lints have finished: the wait step on GitHub, a later stage or
  `needs:` on GitLab. A review that races CI sees `pr.checks_pending == true`,
  the base ruleset refuses to approve a moving target, and nothing re-runs it
  when CI ends (`references/ci-github.md`, `references/ci-gitlab.md`).
- If a required prerequisite is missing, stop and explain how to get it; do not
  improvise.

## Step 0 — preflight

Run:

```sh
"$SKILL_DIR/scripts/doctor.sh" --repo "$PWD"
```

It prints the repo root, remote host, branch, clean/dirty state, existing
Talooner files, existing CI, legacy Talooner files, target paths that the repo
would ignore, tool availability, pinned image status, which credential names are
present (never values), and the number of `.tln.test` files.

Stop if the tree is dirty, Docker is missing, or the pinned image cannot run.
If `legacy_talooner_files` is not `none`, read those files and plan a migration;
do not create a parallel `.talooner/` ruleset. If `ignored_targets` is not `none`,
plan the `.gitignore` negations before writing. Read `AGENTS.md` or `CLAUDE.md` if
present, but do not modify them.

No writes in this step.

## Step 1 — consent and scope

Ask the user to confirm the repository path and remote, then choose an analysis
level:

- **Layout only** — folder names, manifests, CI, CODEOWNERS, README.
- **Targeted (default)** — layout plus approved sensitive folders, dependency
  manifests, CI, and existing docs.
- **Deep** — source and tests in the approved folders.

Say that the user's own coding agent reads the code locally, only with consent,
and that the analysis goes to the agent and its model, not to Talooner. Talooner
still never receives code. Explain what leaves the repo in CI: forge API calls,
the user's own model provider where a rule asks, the license check, and the run
summary.

Get an explicit yes before reading anything beyond layout.

## Step 2 — interview

Follow `references/interview.md`. The order:

1. License and AI review.
2. AI review provider.
3. Context decision model.
4. Forge and token.
5. Advice mode.
6. Sensitive paths and reviewers.
7. Extra rules.
8. Auto-approve.
9. Reviewer mapping.
10. Check names.
11. AI review units and guides.
12. Repo-wide guidelines.
13. PR and commit choices.
14. Anything else.

Stop conditions:

- No license key, or the key does not include AI review.
- No AI review key.
- No decision model key. Both AI review and a decision model are required.
- Dirty tree.
- Ambiguous remote.

The agent's shell may not see variables exported in an interactive shell. Ask the
user to put credentials in `~/.zshenv`, or start the agent from the shell that has
them. Never print a value.

Reviewer mapping: on GitHub Actions, a team review request made with
`GITHUB_TOKEN` fails with a 422, so default to `do assign "pr" attr "user.owner"`
when CODEOWNERS or a confirmed user exists. Use a team `do require` only on
GitLab or with a PAT/GitHub App. Write `.talooner/teams.yaml` only when a rule
actually uses `do require`.

Run the license decode only after the user exports the key:

```sh
"$SKILL_DIR/scripts/decode-license.sh"
```

Read only `ai_review`, `expired` and `expires`. The local decode is a hint. An old
key can look expired after a renewal, and a revoked key can still decode as valid.
The online check on the first CI run is authoritative.

## Step 3 — plan confirmation

Before writing anything, show:

- The files to create or modify.
- Each rule in one line.
- The CI file and job names.
- The secrets the user must set (names only).
- The commands that will run.
- What will be committed.

Ask for an explicit "yes, proceed". Do not continue on ambiguity.

## Step 4 — write the spec

Write `.talooner/onboarding.md` in this shape:

```markdown
# Talooner onboarding spec

## Sensitive paths

Changes here wait for a review before merge.

- `.talooner/` — the review policy — owner assigned for review
- `billing/` — payments — owner assigned for review

## Extra rules

- PRs need a description

## AI review

on — provider: <anthropic|openai|openai-compatible>, model: <id>

## Decision model

on — SubQ Snap (or Jev)

## AI review units

- `app/` — no guide
- `billing/` — docs/guides/payments.md

## Guides

- `billing/` — docs/guides/payments.md

## Notes

…
```

Show it and ask for a yes. Do not generate rules until the spec is approved.

If `.talooner/onboarding.md` already exists, show it and ask whether to use it,
update it, or start over. Never overwrite silently.

## Step 5 — write rules and tests

Start from `assets/rules.tln` and `assets/rules.tln.test`. Keep only the rules the
user confirmed, and adapt paths, reviewers and thresholds.

Baseline rules, when they apply:

- Block PRs with no description.
- Always put `.talooner/` in the critical path: the policy file itself must not be
  editable without review.
- Critical-path review for each sensitive area: `do block "pr.merge"`,
  `do assign "pr" attr "user.owner"` when CODEOWNERS or a confirmed user exists,
  and `do comment "pr" "…"`. On GitLab, or with a PAT/GitHub App, you may use
  `do require "review.<team>"` plus a `teams.yaml` mapping instead.
- Oversized PR needs a human review, with boundary tests at the threshold.
- Pending checks leave a visible comment (`pr.checks_pending == true`).
- New dependencies need a security review, only if a manifest exists.
- Migrations need a DBA review, only if migrations exist.
- AI review inconclusive and AI review failed: require a human or comment. Never
  leave `unclear` or `error` silent.
- Auto-approve only if chosen, gated on `pr.tests_passing`, optional
  `pr.lint_passing`, non-sensitive paths, non-draft, and a description.
- Decision-model rules for risk and description quality, gated at
  `>= 0.85`.

Do not write:

- `strict` rules. The base ruleset already ships them.
- `do notify`. It has no executor.
- `do llm_review`. Use an `enrich` block with `tool "llm" "review"`.
- A path substring without a trailing slash.
- A `require` target with no mapping in `.talooner/teams.yaml`.
- `requires "review.…"` without a matching `do require`. A verdict on its own
  requests nobody; `verify.sh` rejects it.
- A team `do require` on GitHub Actions with `GITHUB_TOKEN`; it fails with a 422.
  Use assignment or a user target.

Tests:

- One matching and one non-matching record per rule.
- Boundary values for thresholds.
- Unset facts: `pr.tests_passing` absent, `pr.changed_files` empty,
  `user.owner` absent.
- Path lookalikes for each path predicate.
- Confident, unsure and error decisions, with `mock tool "cdm" "decide"`.
- Every test passes with the pinned image.

If existing rules exist, read them first, show them, and propose a diff. Keep
existing names. Never delete or rename a rule without explicit approval. If
`.talooner/rules/` exists, tailor those files; do not add a shadowing
`.talooner/rules.tln`.

Syntax reference: `references/tln-rules.md`.

## Step 6 — write AI review units and guides

Always write `.talooner/architecture.yaml`, even when the user chose no guides.
It is not a docs index: it is what turns AI review on. With no architecture rule
at all, Talooner sends no `code_units`, so `llm_review` never reads the change and
no inline comment can ever be posted, however many rules the repo has.

Write one entry per top-level code root the analysis found — `src/`, `lib/`,
`app/`, `internal/`, `pkg/`, `services/` and so on — not only the sensitive ones.
Without an entry, a folder is invisible to AI review: it is neither a code unit
nor a place an inline comment can land. `kind` is required; `doc_ref` is only for
a folder the user interviewed:

```yaml
- path: internal/
  kind: service
- path: pkg/
  kind: service
- path: app/services/payments/
  kind: service
  doc_ref: docs/guides/payments.md
```

`kind` is `model`, `controller` or `service`.

Only folders with a `doc_ref` need a guide. Write or extend that guide:

- One `###` section per checkable rule; the heading names the rule.
- Concrete: a call, a check, a name, a number.
- A `> **Gotcha**:` with the typical wrong code where the user has one.
- A `## Specs` section with `### <file path>` and one bullet per required case.
- Judgement calls under `## Advice`; they inform, they do not block.

Check each section against the current code and report violations. Never fix them
silently. Keep the repository's docs style; extend an existing doc rather than
creating a duplicate.

## Step 7 — write CI

Generate the base from the pinned image:

```sh
docker run --rm -e TALOONER_IMAGE=ghcr.io/talooner/talooner-runner:1.1.2 \
  ghcr.io/talooner/talooner-runner:1.1.2 snippet github
```

Use `snippet gitlab` for GitLab.

GitHub Actions:

- Write `.github/workflows/talooner.yml`.
- If it exists and is already a Talooner workflow, show it and ask before
  changing it. If it is a different workflow, stop; do not overwrite.
- Keep the `rules` → `review` → `resolve` structure.
- Keep the wait step (`wait for the other checks on this commit`) between the
  rules check and the review. It is what makes `pr.checks_pending` false; the
  pinned 1.1.2 snippet predates it, so add it when it is missing. It needs
  `actions: read` in the review job's permissions.
- Rules use `ghcr.io/talooner/talooner-runner:1.1.2`; review uses
  `ghcr.io/talooner/talooner-runner:1.1.2-gh`.
- Add the chosen model and decision-model env. Use the provider's exact model id;
  do not infer it from another provider's catalog.
- Do not use a team `do require` with `GITHUB_TOKEN`; it fails with a 422. Use
  `do assign` or a user target, unless the user supplies a PAT/GitHub App.
- Add `TALOONER_ADVICE_MODE: "1"` when chosen.
- Keep `TALOONER_LICENSE_KEY`, `TALOONER_CHECK_RUN_ID` and `GITHUB_TOKEN`.
- Do not add `TALOONER_APPROVE_WITHOUT_RULESET`.

GitLab CI:

- Add `talooner-rules` and `talooner-review` to `.gitlab-ci.yml`.
- If the file does not exist, create it from the snippet.
- Preserve `stages`, `include`, `default` and unrelated jobs.
- If `talooner-*` jobs exist, show them and ask before changing them.
- Put `talooner-review` in a stage after every job that checks the merge
  request: the last declared stage, never the stage the repository's own tests
  and lints run in. Jobs in one stage run concurrently, so a review placed
  beside them starts while their statuses are still pending and is blocked.
  If the pipeline already uses `needs:`, adding the test/lint jobs to
  `talooner-review`'s `needs` is the equivalent ordering. If stages come only
  from an include, stop and ask the user to add the jobs by hand.
- Keep `entrypoint: [""]` and `needs: [talooner-rules]`.
- Set `GIT_STRATEGY: none` on the review job only; the rules job needs the
  checkout.
- Never name a job exactly `talooner`.
- Add `TALOONER_ADVICE_MODE: "1"` under the review job when chosen.
- Model, decision-model and license values are CI/CD variables; do not hardcode
  them.

Details: `references/ci-github.md` and `references/ci-gitlab.md`.

## Step 8 — verify

Run:

```sh
"$SKILL_DIR/scripts/verify.sh" --repo "$PWD" --strict
```

It checks the tree, required files, ignored generated files, legacy Talooner
paths, `requires`/`do require` pairing, `tln test` with the pinned image, config
sanity, CI wiring and token shapes, plus removed commands and local absolute
paths in the files it generated. It exits non-zero on any failure.

`--strict` fails when config sanity is skipped. To run the real config check,
supply the provider and a forge token without printing either:

```sh
TALOONER_PROVIDER=github GITHUB_TOKEN="$(gh auth token)" \
  "$SKILL_DIR/scripts/verify.sh" --repo "$PWD" --strict
```

`verify: INCOMPLETE` means not ready.

If a test fails, fix the rule or the test, or ask the user. Never delete a failing
test to make the suite green.

## Step 9 — secrets checklist

The skill never handles secret values. Give the user the exact checklist.

GitHub Actions secrets:

- `TALOONER_LICENSE_KEY`
- `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` or `TALOONER_MODEL_API_KEY`
- `CDM_TOKEN`

GitHub Actions variables:

- `TALOONER_MODEL_BASE_URL` (OpenAI-compatible only)
- `TALOONER_MODEL`
- `CDM_URL`
- `CDM_MODEL` (optional)
- `TALOONER_CDM_MIN_CONFIDENCE` (optional)

GitHub settings:

- Allow GitHub Actions to create and approve pull requests.
- After leaving advice mode, require the `talooner` check, not the `review` job.

GitLab masked variables:

- `TALOONER_LICENSE_KEY`
- `GITLAB_TOKEN` (Developer role, `api` scope)
- `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` or `TALOONER_MODEL_API_KEY`
- `CDM_TOKEN`

GitLab variables:

- `TALOONER_MODEL_BASE_URL`
- `TALOONER_MODEL`
- `CDM_URL`
- `CDM_MODEL`
- `TALOONER_CDM_MIN_CONFIDENCE`

GitLab settings:

- "Pipelines must succeed" only after leaving advice mode.
- Runner tags if the project uses tagged runners.

Tell the user: "Do not paste these values into this chat. Set them in the shell or
the CI UI."

## Step 10 — commit and PR

- Show `git status` and `git diff` for the intended files.
- Ask for explicit approval.
- Create branch `talooner/onboard` unless the user chose another name. Record
  every branch you create.
- Stage explicit paths only. Never `git add -A` or `git add .`.
- Commit only the intended files; no `.env`, no secrets, no unrelated changes.
- Ask before pushing.
- If `gh` or `glab` is available and authenticated, open a draft PR/MR with:
  - what this adds,
  - a one-line summary of each rule and guide,
  - the secrets checklist,
  - a note that the onboarding PR itself has no ruleset on the base branch, so
    Talooner will not review it; after merge, open a small test PR,
  - the advice-mode note and how to switch to blocking.
- If the CLI is unavailable, print the push command and the PR/MR URL to open
  manually.
- Offer "leave local only" at the confirmation step.
- If the user asks for cleanup, delete only the branches this run created. List
  every other Talooner-looking branch for the user to decide.

## Step 11 — handoff

Summarize:

- Each rule in one line.
- Each `architecture.yaml` entry in one line: the code an inline comment can
  land on. Name the code roots with no entry, and say they get no AI review.
- Each guide in one line: code covered, number of sections and spec cases,
  current-code violations found.
- CI file and jobs.
- Secrets the user still needs to set.
- How to run the rules test locally.
- How to leave advice mode and turn on blocking.
- What the first review will show, and what it will not show on the onboarding
  PR.
- The post-merge probe in `references/post-merge-check.md`: confirm
  `.talooner/config.yaml` and `.talooner/architecture.yaml` are on the base
  branch, open a throwaway PR touching a sensitive path and a mapped code root,
  check the comment, block, assignment and `code units resolved`, then close it.

Links: `https://talooner.dev/rules/`, `https://talooner.dev/install/`,
`https://tln-lang.org/`, `https://github.com/Talooner/feedback`.

## Token economy

- Load a reference only when its step is reached.
- Run scripts without reading their source.
- Analyze layout first, then only approved folders. Skip `vendor/`,
  `node_modules/`, `dist/`, `build/`, generated files, lockfiles and binaries.
- Start rules and CI from templates; adapt rather than regenerate.
- Ask one question per call.
- Summarize long files; never echo a whole file unless asked.
- When something is ambiguous, ask instead of guessing.
