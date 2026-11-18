# Interview

One question per call. Record each answer in the plan; nothing is written before
the plan is confirmed.

## 1. License

"Does your Talooner license include QA?" Without the `qa` feature,
`talooner-step qa` reports `skipped` and exits 0: the jobs would run and do
nothing. If the user is unsure, the first compose log says so; offer to continue
and check then.

## 2. Where the app runs

QA needs a running copy of the PR's app that both QA jobs can reach.

- **Inside the CI job (recommended).** The PR's image runs as a service of
  the job (GitLab `services:`, or `docker compose up` in a GitHub job), with its
  database and a seed. Nothing outside the job sees it, so the hook token can be
  a throwaway value per job.
- **A deployed preview.** A review app per PR (Heroku, Vercel, Kubernetes).
  Ask how the job learns its URL, and confirm the hooks are reachable there but
  never on production. The token is a masked CI variable.

Ask which image the PR builds and whether the app has a health URL. If neither
exists, stop: the app has to start in CI before QA can.

## 3. Hooks

Rails ≥ 7.2: `talooner-qa-rails` (`references/hooks.md`). Other stacks: the
app implements the contract itself; ask who owns that work and whether the
user wants a stub now (roles, pages, seeds, login) or to stop here.

## 4. Roles

"Which areas does a user have a role in, and which roles are there in each?"
Read the role definitions in the approved folders and propose the map, for
example `inventory: user_reduced, user_extended, admin`. A single-role app is
one area with one role. Areas are also the block folders.

Ask how a test user with exactly those roles is made (`user_for`): a factory, a
seed helper, or a fixed user per role.

## 5. Seeds

"Which records does a page need to open?" Every page with an `:id` needs a seed
name that creates one. Prefer what exists: FactoryBot factories and traits, or a
seed script that names what it builds. A world seeded once per run and read by
every scenario is fine; a scenario that changes data seeds its own record.

## 6. Roles guide

"Is there a doc that says which role may view, create, edit and delete each
record?" Reuse it if it names roles and pages; otherwise propose
`docs/guides/roles.md` (`assets/roles.md`). Then: "Do PRs change roles together
with this doc?" Yes → `guide_from: head`; no → `guide_from: base`.

## 7. Areas and first blocks

Propose one block per main page of each area, from the router: open it, see a
heading only that page shows. Ask which flows matter beyond opening pages
(create, approve, delete) and add those as their own blocks. Keep the first
catalog small: it grows with the PRs that need it.

## 8. Smoke and time budget

"Which two or three pages should every PR check?" Usually the main list of the
busiest area. `time_budget` defaults to `10m`; scenarios past it are `not_run`,
never passed.

## 9. Login page

"What is the route name of the sign-in page?" (`new_user_session` in Devise.)
It is what a guest who may not open a page lands on, and what `I am on "login"`
checks.

## 10. Metrics

"Does the review push metrics (`TALOONER_METRICS_PUSH_URL`)?" If yes, set the
same variable on both QA jobs; the dashboard's QA row reads them.

## 11. PR and commit

Branch name, draft PR/MR, or leave local only.
