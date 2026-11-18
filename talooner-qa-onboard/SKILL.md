---
name: talooner-qa-onboard
description: Onboard the current repository to Talooner QA — interview the user, wire the app's test-only /__qa hooks, write the .talooner/qa/ catalog (config.yaml and blocks/<area>/*.feature), a roles guide, and the GitLab CI or GitHub Actions jobs that compose and run a PR's browser scenarios, verify the catalog with the pinned runner image, and prepare a draft PR/MR. Use when the user asks to onboard this repo to Talooner QA, set up QA blocks, or add browser QA to Talooner reviews.
metadata:
  version: 1.3.0
  runner_version: 1.3.2
  qa_version: 0.0.10
---

# Onboard a repository to Talooner QA

After the review, Talooner QA checks a PR in a browser. `talooner-step qa`
narrows the PR to the pages, blocks and roles it touches and composes one
scenario (`qa-out/scenario.feature`); `talooner-qa run` executes it in Chromium
against a running copy of the app and writes `qa-out/qa-facts.json` and
`qa-out/junit.xml`. QA decides nothing on its own: the facts are for the gate.

The repository supplies three things, and this skill writes them with the user:

1. **Hooks** — the app's test-only `/__qa/*` API: roles, pages, seeds, login.
2. **Catalog** — `.talooner/qa/config.yaml` and `.talooner/qa/blocks/<area>/*.feature`.
3. **CI** — a running app the jobs can reach, a compose job and a run job.

Docs: `https://talooner.dev/automated-qa/` · hooks for Rails:
`https://github.com/Talooner/talooner-qa-rails`

## Paths

Resolve the installed folder once and use absolute paths:

```sh
SKILL_DIR="$HOME/.claude/skills/talooner-qa-onboard"
"$SKILL_DIR/scripts/doctor.sh" --repo "$PWD"
"$SKILL_DIR/scripts/verify.sh" --repo "$PWD"
```

Use the real install location for the user's agent. Never `cd` into the skill
folder.

## Hard rules

- This is interactive. Ask one question at a time and wait for the answer.
- Never ask for, print, log, commit or pass a secret value.
- `TALOONER_QA_HOOK_TOKEN` guards `/__qa/login`, which signs in as any role.
  Never hardcode a reusable value: in CI it is a masked variable, or a throwaway
  value built from the pipeline and job ids for an app that lives only inside the
  job. Never mount the hooks in production or where real users' data lives.
- Commit explicit paths only. Never `git add -A` or `git add .`.
- Never commit, push, open a PR/MR or install software without an explicit yes.
- Work only in the repository root. If the tree is dirty, stop and ask the user
  to commit or stash.
- Do not read source files before the analysis-consent step.
- Do not claim success until `"$SKILL_DIR/scripts/verify.sh" --strict` passes.
- Pin `ghcr.io/talooner/talooner-runner:1.3.2` for compose and
  `ghcr.io/talooner/talooner-qa:0.0.10` for run, never `latest`.
- Never invent a page, role or seed name. Blocks use only the names the app's
  hooks answer (`/__qa/pages`, `/__qa/roles`, `/__qa/seeds`), or names the user
  confirms the hooks will answer once wired.
- A block's `Then` is its success check. Never write a block without one, and
  never a `Then` that would pass on any page (`I see "OK"`, a site-wide header).
- QA starts advisory: `allow_failure: true` on GitLab, `continue-on-error: true`
  on GitHub, until several PRs are green.

## Step 0 — preflight

```sh
"$SKILL_DIR/scripts/doctor.sh" --repo "$PWD"
```

It prints the repo root, forge, clean/dirty state, the stack (manifests), the
Talooner review setup (`.talooner/`, the review job), an existing `.talooner/qa/`,
an existing hooks mount, existing guides, CI files, Docker and the pinned images.

Stop if the tree is dirty or Docker is missing. If `talooner_review=none`, say
that QA runs after a Talooner review and offer the `talooner-onboard` skill
first; QA can still be written, but the compose job needs the review's license,
model and decision-model settings. If `qa_catalog` is not `none`, read it and
extend it; never start a parallel catalog.

No writes in this step.

## Step 1 — consent and scope

Same levels as `talooner-onboard`: layout only, targeted (default), deep. QA
needs the router (pages), the permission model (roles) and the seeds or
factories (data), so ask for targeted at least, naming those folders. The
analysis goes to the user's agent and its model, not to Talooner. In CI, compose
calls the user's own model and decision model, and run talks only to the app
inside the job.

## Step 2 — interview

Follow `references/interview.md`. The order:

1. License has the `qa` feature.
2. Where the app runs for QA: started inside the CI job, or a deployed preview.
3. Hooks: the stack and how they are served.
4. Roles: the areas and the roles in each.
5. Seeds: the records a page needs.
6. Roles guide: an existing doc, or a new one.
7. Areas and first blocks.
8. Smoke blocks and the time budget.
9. Login page.
10. Metrics push (optional).
11. PR and commit choices.

Stop conditions:

- The license has no `qa` feature (compose reports `skipped`; say so and stop).
- No way to run the app reachable from CI.
- The user does not want test-only hooks in the app.

## Step 3 — plan confirmation

Show the files to create or change, the hooks wiring, each area and its blocks
in one line, the CI jobs and their order, the variables the user must set (names
only), and what will be committed. Ask for an explicit "yes, proceed".

## Step 4 — wire the hooks

Follow `references/hooks.md`.

- Rails: add `talooner-qa-rails` to a non-production group, mount the engine
  behind `TaloonerQa.enabled?`, and write `config/initializers/talooner_qa.rb`
  from `assets/talooner_qa.rb`: `roles`, `user_for`, the seeds (FactoryBot or
  a seed script that names what it builds), `exclude_pages` for admin and API
  routes.
- Other stacks: implement the contract in `references/hooks.md` under the
  app's test or preview mode only. Every hook refuses a call without the
  bearer token with `401`, a hook not implemented answers `404`, and nothing
  redirects to a login page.

If the app can run locally, start it with `TALOONER_QA_HOOK_TOKEN` set and
check `GET /__qa/roles`, `/__qa/pages` and `/__qa/seeds` with the token, and
that each answers `401` without it. Report the counts, not the bodies.

## Step 5 — write the roles guide

`config.yaml`'s `guide:` is the page compose reads to decide which roles may
open a page and which must be denied. It is read from the base branch unless
`guide_from: head`. Without a guide every role question comes back unclear.

Reuse an existing permissions doc when it names the roles and the pages they
may use. Otherwise write `docs/guides/roles.md` in the shape of
`assets/roles.md`: one section per area, the roles lowest to highest, and a
table of records with their page names and who may view, create, edit, delete.
Write it from the role definitions and policies the user approved; never from
guesses. Use the exact role and page names the hooks answer.

Ask whether PRs change roles together with the guide (`guide_from: head`) or
whether the base branch's guide must hold (`guide_from: base`, the default).

## Step 6 — write the catalog

Follow `references/catalog.md`. Start from `assets/config.yaml` and
`assets/block.feature`.

- `.talooner/qa/config.yaml`: `time_budget`, `smoke`, `guide`, `guide_from`,
  `login`. Unknown keys are errors.
- One folder per area under `blocks/`, named like the hooks' areas where they
  match. One file per record or page group.
- Start with one block per main page: open it, `Then I see` text only that page
  shows. Add actions (click, fill in, confirm) only for flows the user names.
- Every block has one `@page:` from `/__qa/pages`, and a `@data:` from
  `/__qa/seeds` when the page has a `:param`.
- Block names are unique across the catalog: they are the questions compose
  asks ("does the PR need *open an item*?").
- `smoke`: two or three blocks every PR runs, on the busiest pages.

## Step 7 — write CI

GitLab: `references/ci-gitlab.md`. GitHub Actions: `references/ci-github.md`.

- Two jobs after the review: `talooner-qa` (compose, runner image) then
  `talooner-qa-run` (run, qa image). Never in the stage of the repository's
  own tests: compose waits for the pipeline's other jobs and skips when they
  fail or the review blocks.
- Both jobs reach the same app at `TALOONER_QA_PREVIEW_URL` with the same
  `TALOONER_QA_HOOK_TOKEN`, and wait for its health URL before they start.
- Run `talooner-qa catalog validate` first in the compose job.
- Cache `$TALOONER_QA_CACHE_DIR` per PR so a rebase is answered without a model
  call.
- Keep `qa-out/` as an artifact; publish `qa-out/junit.xml` as the test report.
- `talooner-qa run --fail` makes a failed or not-run scenario fail the job while
  QA is advisory.

## Step 8 — verify

```sh
"$SKILL_DIR/scripts/verify.sh" --repo "$PWD" --strict
```

It validates the catalog with the pinned runner image, checks that the guide
exists, that every block has a `@page:` and a `Then`, that the CI file has
both jobs on pinned images, that no hook token value is committed, and that
the hooks are mounted behind the token. `verify: INCOMPLETE` means not ready.
Never delete a block or a check to make it pass.

## Step 9 — variables checklist

Names only. Compose reuses the review's: `TALOONER_LICENSE_KEY`, the model key,
`TALOONER_MODEL`, `CDM_URL`, `CDM_TOKEN`, the forge token. QA adds:

- `TALOONER_QA_PREVIEW_URL` — the app as the jobs reach it.
- `TALOONER_QA_HOOK_TOKEN` — masked; or a per-job throwaway value when the app
  lives only inside the job.
- `TALOONER_QA_CACHE_DIR` — a path inside the checkout, cached per PR.
- `TALOONER_METRICS_PUSH_URL` (optional) — the same gateway as the review; the
  dashboard's QA row reads `talooner_qa_*`.

Tell the user: "Do not paste these values into this chat."

## Step 10 — commit and PR

Branch `talooner/qa-onboard` unless the user chose another. Show `git status`
and the diff, stage explicit paths, ask before pushing, open a draft PR/MR with
what it adds, the areas and blocks, the variables checklist, and the note that
QA is advisory until several PRs are green.

## Step 11 — handoff

Summarize the hooks wiring, each area with its block count, the smoke blocks,
the guide, the CI jobs, and the variables still to set. Then the first-run
check from `references/troubleshooting.md`: open a PR that changes one page's
view, and confirm compose names that page, the run job signs in and passes,
and the JUnit report shows each role as its own scenario.

## Token economy

- Load a reference only when its step is reached.
- Run scripts without reading their source.
- Read the router, policies and seeds only in approved folders.
- Write the first blocks from the pages list, not from reading every view.
- Ask one question per call.
