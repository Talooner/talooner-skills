# First run and troubleshooting

## First-run check

After merge, open a small PR that changes one page's view (a heading, a label).
In the compose job log:

- `talooner-qa catalog validate` lists the blocks and `N blocks ok`.
- compose names the page the view belongs to and the roles it tests; the
  composed `scenario.feature` is printed.

In the run job log, every scenario is printed with its steps: each role is its
own scenario, a role the guide denies ends in `access is denied`, and the PR's
new text is checked by `the change shows on "<page>"`. The JUnit report on the
PR/MR lists the same scenarios.

## Compose

| log | cause |
|---|---|
| `skipped` with a license note | the license has no `qa` feature |
| `not_covered` | no page, block or area matches the changed files; normal for backend-only PRs |
| questions printed with keys, nothing composed | `--unclear yes` missing |
| `role questions will come back unclear` | no `guide:` in `config.yaml`, or the file does not exist on the base branch |
| hooks `401` | the jobs and the app have different `TALOONER_QA_HOOK_TOKEN` values |
| hooks `404` on every call | the engine is not mounted: the token is not set in the app's environment, or the build left out the gem's group |
| hooks redirect | `/__qa` is behind the login wall; mount it outside authentication |
| waits, then skipped | another job of the pipeline failed, or the review blocks |

## Run

| log | cause |
|---|---|
| `the app did not come up` | the start script failed; with `CI_DEBUG_SERVICES` the app's log is in the compose job |
| `unknown step` | a block uses a step outside the vocabulary (`references/catalog.md`) |
| `role "x" is not area:role` | `/__qa/roles` answers a flat list; it must be `{area: [roles]}` |
| a seed `422` | a `@data:` name the app does not list in `/__qa/seeds` |
| `I see` fails on a correct page | the text differs from what is rendered: locale, case, or it is inside an icon |
| everything `not_run` | `time_budget` too small for the scenarios selected |
| `https` errors on a host ending `.app` | Chrome forces https on that TLD; name the service something else |

## Metrics

`metrics: pushed N series to …` after compose and after run. Nothing printed
means `TALOONER_METRICS_PUSH_URL` is not set on that job; a warning names the
reason. A push never fails the job.
