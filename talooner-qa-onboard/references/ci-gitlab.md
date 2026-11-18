# GitLab CI

Two stages after the review, in this order:

```yaml
stages:
  # … the repository's own stages, then the review's …
  - qa
  - qa-run
```

`talooner-qa` composes with the runner image (it starts the cluster, like the
review); `talooner-qa-run` executes in the qa image (Chromium). Both run the PR's
app as a service and reach it at the same URL.

## The app as a service

The usual shape: the PR's image, built earlier in the pipeline, runs as the
service `web` with its database, seeded for QA by a start script the repository
owns. GitLab hands a service only the job's variables, so every value the app
needs is in the shared `.qa-app` template, and all of them are throwaway values
for an app that lives only in the job's network.

```yaml
.qa-app:
  interruptible: true
  allow_failure: true          # advisory until several MRs are green
  services:
    - name: postgres:16
      alias: postgres
    - name: ${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}   # the MR's app image
      alias: web                                    # not "app": Chrome forces https on .app
      command: [bin/qa-web]                         # migrate, seed for QA, serve
  variables:
    FF_NETWORK_PER_BUILD: "true"                    # services see each other by alias
    CI_DEBUG_SERVICES: "true"                       # the app's boot log lands in the job log
    DATABASE_URL: postgres://postgres:postgres@postgres/qa
    SECRET_KEY_BASE: qa-${CI_PIPELINE_ID}-${CI_JOB_ID}
    TALOONER_QA_HOOK_TOKEN: qa-${CI_PIPELINE_ID}-${CI_JOB_ID}
    TALOONER_QA_PREVIEW_URL: http://web:3000
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
```

`TALOONER_QA_HOOK_TOKEN` is built from the pipeline and job ids: the app lives
only in this job, so no other process can use it. With a deployed preview
instead, drop the services, set `TALOONER_QA_PREVIEW_URL` to the preview, and
make the token a masked CI/CD variable.

If the app takes longer than the runner's service wait to listen, open a TCP
port at once in the start script and set `HEALTHCHECK_TCP_PORT` on the service;
the jobs wait for the real health URL themselves.

## Compose

```yaml
talooner-qa:
  extends: [.talooner_base, .qa-app]   # .talooner_base: the review's image, entrypoint and variables
  stage: qa
  needs: [build_image, { job: talooner-review, artifacts: false }]
  variables:
    TALOONER_PROVIDER: gitlab
    TALOONER_QA_CACHE_DIR: $CI_PROJECT_DIR/.qa-cache
  cache:
    key: qa-$CI_MERGE_REQUEST_IID
    paths:
      - .qa-cache/
  script:
    - talooner-qa catalog validate
    - |
      for i in $(seq 300); do wget -q -O /dev/null "$TALOONER_QA_PREVIEW_URL/health" && break; sleep 2; done
      wget -q -O /dev/null "$TALOONER_QA_PREVIEW_URL/health" || { echo "the app did not come up"; exit 1; }
    - talooner-step qa --out qa-out --unclear yes
    - '[ ! -f qa-out/scenario.feature ] || cat qa-out/scenario.feature'
  artifacts:
    when: always
    paths:
      - qa-out/
```

- `.talooner_base` is the review's template: `ghcr.io/talooner/talooner-runner:1.3.2`
  with `entrypoint: [""]`, the license, model and decision-model variables. If the
  repository has none, give the job `image:` and those variables directly.
- `--unclear yes` lets the pipeline answer questions compose could not settle;
  without it they are printed for a person and the job composes nothing.
- The cache is keyed per MR, so a rebase that keeps the patch costs no model
  call. Use `cache:`, not artifacts.
- The runner image has busybox `wget`, not `curl`.

## Run

```yaml
talooner-qa-run:
  extends: .qa-app
  stage: qa-run
  image:
    name: ghcr.io/talooner/talooner-qa:0.0.10
    entrypoint: [""]
  needs: [build_image, talooner-qa]
  variables:
    CI_DEBUG_SERVICES: "false"   # the log is the scenarios; the app's log is in talooner-qa
  script:
    - |
      for i in $(seq 300); do curl -sf -o /dev/null "$TALOONER_QA_PREVIEW_URL/health" && break; sleep 2; done
      curl -sf -o /dev/null "$TALOONER_QA_PREVIEW_URL/health" || { echo "the app did not come up"; exit 1; }
    - talooner-qa run --fail
  artifacts:
    when: always
    paths:
      - qa-out/
    reports:
      junit: qa-out/junit.xml
```

`talooner-qa run` reads `qa-out/` from the compose job's artifacts. `--fail` exits
`3` on a failed or not-run scenario; without it the job is green whatever the
results.

## Metrics

Set `TALOONER_METRICS_PUSH_URL` (and `TALOONER_METRICS_PUSH_TOKEN` if the gateway
needs one) in `.qa-app` when the review pushes metrics. Compose and run each
push their `talooner_qa_*` counters once; compose's LLM cost comes from the
cluster. A push only warns, never fails the job.

## Variables

Reused from the review: `TALOONER_LICENSE_KEY`, `GITLAB_TOKEN`, the model key,
`TALOONER_MODEL`, `CDM_URL`, `CDM_TOKEN`. Add `TALOONER_QA_HOOK_TOKEN` as a masked
variable only for a deployed preview.
