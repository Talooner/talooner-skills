# GitHub Actions

Add a `qa` job to `.github/workflows/talooner.yml`, after `review`. GitHub
service containers cannot take a start command, so the job starts the app
itself with the repository's own compose file (or reaches a deployed preview),
then composes and runs in the same job: both steps see the same app.

```yaml
  qa:
    needs: review
    runs-on: ubuntu-latest
    continue-on-error: true      # advisory until several PRs are green
    permissions:
      contents: read
      pull-requests: write
    env:
      TALOONER_QA_PREVIEW_URL: http://localhost:3000
      TALOONER_QA_CACHE_DIR: .qa-cache
    steps:
      - uses: actions/checkout@v4
      - name: hook token for this run
        run: echo "TALOONER_QA_HOOK_TOKEN=qa-${{ github.run_id }}-${{ github.run_attempt }}" >> "$GITHUB_ENV"
      - name: start the app
        run: |
          docker compose -f docker-compose.qa.yml up -d --wait
          for i in $(seq 150); do curl -sf -o /dev/null "$TALOONER_QA_PREVIEW_URL/health" && break; sleep 2; done
          curl -sf -o /dev/null "$TALOONER_QA_PREVIEW_URL/health" || { docker compose -f docker-compose.qa.yml logs; exit 1; }
      - uses: actions/cache@v4
        with:
          path: .qa-cache
          key: qa-${{ github.event.pull_request.number }}-${{ github.sha }}
          restore-keys: qa-${{ github.event.pull_request.number }}-
      - name: validate the catalog
        run: docker run --rm -v "$PWD:/repo" -w /repo --entrypoint talooner-qa ghcr.io/talooner/talooner-runner:1.3.2 catalog validate
      - name: compose
        run: |
          # shellcheck disable=SC2046 # one -e per GITHUB_* name: the PR, the run and the token
          docker run --rm --network host -v "$PWD:/repo" -w /repo \
            $(env | grep -o '^GITHUB_[A-Z_]*' | sed 's/^/-e /') \
            -v "$GITHUB_EVENT_PATH:$GITHUB_EVENT_PATH:ro" \
            -e TALOONER_PROVIDER=github -e TALOONER_LICENSE_KEY -e ANTHROPIC_API_KEY -e TALOONER_MODEL \
            -e CDM_URL -e CDM_TOKEN \
            -e TALOONER_QA_PREVIEW_URL -e TALOONER_QA_HOOK_TOKEN -e TALOONER_QA_CACHE_DIR \
            ghcr.io/talooner/talooner-runner:1.3.2 qa --out qa-out --unclear yes
        env:
          GITHUB_TOKEN: ${{ github.token }}
          TALOONER_LICENSE_KEY: ${{ secrets.TALOONER_LICENSE_KEY }}
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
          TALOONER_MODEL: ${{ vars.TALOONER_MODEL }}
          CDM_URL: ${{ vars.CDM_URL }}
          CDM_TOKEN: ${{ secrets.CDM_TOKEN }}
      - name: run
        run: |
          docker run --rm --network host -v "$PWD:/repo" -w /repo \
            -e TALOONER_QA_PREVIEW_URL -e TALOONER_QA_HOOK_TOKEN \
            ghcr.io/talooner/talooner-qa:0.0.10 run --fail
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: qa-out
          path: qa-out/
```

- `docker-compose.qa.yml` is the repository's: the PR's app built from the
  checkout, its database, a seed for QA, `TALOONER_QA_HOOK_TOKEN` passed through,
  port 3000 published. Write it with the user when it does not exist; never
  reuse a compose file that points at shared data.
- The token is built from the run id: the app lives only in this job. With a
  deployed preview, drop the start step, set `TALOONER_QA_PREVIEW_URL` to the
  preview and make the token a repository secret.
- `--network host` lets both containers reach the app on `localhost`.
- Use the provider key and model the review uses; match its env names.
- `--fail` exits `3` on a failed or not-run scenario; `continue-on-error` keeps
  the workflow green while QA is advisory.
- Publish `qa-out/junit.xml` with a test-report action if the repository uses
  one.

## Metrics

Add `-e TALOONER_METRICS_PUSH_URL -e TALOONER_METRICS_PUSH_TOKEN` to both
`docker run` steps, with the same values the review uses.
