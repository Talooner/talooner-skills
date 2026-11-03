# tln and Talooner rules

Full language reference: `https://tln-lang.org/`.

## Shape

```tln
define "critical_path" {
  attr "pr.changed_files" contains ".talooner/"
    or attr "pr.changed_files" contains "auth/"
    or attr "pr.changed_files" contains "billing/"
}

rule "Critical path needs review" {
  for records where type == "pr" and is "critical_path"
  do block "pr.merge"
  do assign "pr" attr "user.owner"
  do comment "pr" "Changes a sensitive path; the owner is assigned for review"
  reason "critical path"
  priority HIGH
}
```

- `define` names a predicate. `rule` matches records, declares a verdict
  (`allow`, `block "…"`, `requires "…"`), and lists actions with `do …`.
- `enrich` asks a tool and writes the answer back as facts.

## Verdicts and actions

- `allow "merge"` approves.
- `block "merge"` records the verdict.
- `requires "review.name"` names a review. It does nothing on its own.
- `do block "pr.merge"` is what actually holds the merge.
- `do require "review.name"` requests the reviewers.
- `do comment "pr" "…"` writes a sticky comment.
- `do assign "pr" attr "user.owner"` assigns the owner.
- `do approve "pr"` approves the PR.

Pair `requires` with `do block "pr.merge"` when the PR must wait. If you use
`do assign` instead of `do require`, drop `requires`; a rule that declares a
review nobody requests is misleading. `verify.sh` rejects it.

On GitHub Actions, a team review request made with `GITHUB_TOKEN` fails with a
422. Use `do assign` or a user target there; team `do require` is for GitLab or a
PAT/GitHub App. Assignment needs CODEOWNERS or a confirmed user: `user.owner` is
unset for a new file with no last toucher, and the action then no-ops with
`assignee_unresolved`.

## Matching

- `contains`, `starts_with`, `ends_with` are substring scans, not globs.
- Paths need a trailing slash: `contains "auth/"`. Test lookalikes such as
  `src/authorization/`.
- `attr "pr.changed_files"` is a list. `contains` matches when any element does.
  An empty list matches nothing.
- An unset fact is false. A positive condition on it does not fire. A negated
  condition on it does fire, so test the unset case.

The base strict ruleset has a rule that blocks while required checks are still
running. It has no comment action, so a run can say "1 rule fired" with nothing on
the PR. Add a tenant comment:

```tln
rule "CI checks still running" {
  for records where type == "pr" and attr "pr.checks_pending" == true
  do comment "pr" "Waiting for required checks to finish."
  priority LOW
}
```

Do not write:

- `strict` rules. The base ruleset already ships them; redefining one is a
  compile error.
- `do notify`. It has no executor and a fired notify fails the run.
- `do llm_review`. It is not a verb. Use an `enrich` block with
  `tool "llm" "review"`.
- A path substring without a trailing slash.
- A `require` target with no mapping in `.talooner/teams.yaml`.
- `requires "review.…"` without a matching `do require`.
- A team `do require` on GitHub Actions with `GITHUB_TOKEN`.

## Facts

- `pr.lines_changed`, `pr.files_changed`, `pr.changed_files`
- `pr.draft`, `pr.has_description`, `pr.is_fork`, `pr.author`
- `pr.tests_passing`, `pr.lint_passing` (unset until configured check names match)
- `pr.checks_pending` (true while required checks are still running)
- `pr.new_dependencies`
- `user.owner` (CODEOWNERS, else the last person to touch the code)
- `review.human.approved`, `review.changes_requested`, `review.<team>.approved`
- `unit.llm_result`, `unit.llm_explanation`, `unit.important`
- `pr.risk`, `pr.risk_certainty`, `pr.description_kind`,
  `pr.description_certainty`

## AI review

The base ruleset reviews documented units. A tenant `enrich` block is only for an
explicit override:

```tln
enrich "Review changed code against its guide" {
  for records where type == "code_unit" and attr "unit.important" == true
  tool "llm" "review" {
    doc  attr "unit.doc_content"
    diff attr "unit.diff"
  }
  update attr "unit.llm_result" from result.verdict
}
```

Handle `unclear` and `error`; never leave them silent.

## Decision model

```tln
enrich "cdm: how risky is this PR?" {
  for records where type == "pr"
  stale_after 1 hour
  tool "cdm" "decide" {
    state   concat(attr "pr.title", "\n\n", attr "pr.body", "\n\nChanged files:\n", join(attr "pr.changed_files", "\n"))
    choices "low, medium, high"
  }
  update attr "pr.risk" from result.chosen
  update attr "pr.risk_certainty" from result.certainty
}

rule "Confident high risk needs a senior review" {
  for records where type == "pr"
    and attr "pr.risk" == "high"
    and attr "pr.risk_certainty" >= 0.85
  do block "pr.merge"
  do require "review.senior"
}
```

`choices` is a comma-separated string. Read `result.chosen` and
`result.certainty`; `confidence` is a tln keyword. A failed or unallowed decision
returns `chosen: "error"` and certainty 0, so a confident rule never fires on it.
Gate decisions at 0.85 or higher.

## Tests

```tln
test "Critical path needs its reviewer" {
  given {
    record 1 type "pr"
    attr 1 "pr.changed_files" ["internal/auth/session.go"]

    record 2 type "pr"
    attr 2 "pr.changed_files" ["README.md"]
  }

  when rule "Critical path needs review"

  expect {
    flagged 1
    not flagged 2
    did 1 require "review.owners"
    did_not 2 require "review.owners"
  }
}
```

- `given` builds records and attributes; list literals and empty lists work.
- `when rule "…"` runs a rule. `when enrich "…"` runs an enrich block.
- `mock tool "server" "tool" { returns { key value } }` stubs a tool.
- `expect` supports `flagged`, `not flagged`, `count`, `did`, `did_not`,
  `tool_called`.
- Cover both directions for every rule: one record that matches and one that
  does not.
- Cover threshold boundaries, unset facts, empty `pr.changed_files`, missing
  `user.owner`, and path lookalikes.
- Cover confident, unsure and error decisions.

Run the suite:

```sh
docker run --rm --user "$(id -u):$(id -g)" \
  -v "$PWD:/repo" -w /repo --entrypoint tln \
  ghcr.io/talooner/talooner-runner:1.1.2 test .talooner/
```

Never delete a failing test to make the suite green. Fix the rule or ask the user.

## Files

- `.talooner/rules.tln` plus `.talooner/rules.tln.test`
- or `.talooner/rules/*.tln` with `.tln.test` next to each file
- `.talooner/config.yaml` — `checks.tests` and `checks.lint` job names
- `.talooner/teams.yaml` — logical team name to GitHub team, GitLab group, or user
  list. Write it only when a rule uses `do require`:

  ```yaml
  owners: acme/owners
  senior:
    - alice
    - bob
  ```

  `review.owners` resolves the `owners` key. A list needs no host lookup.
- `.talooner/architecture.yaml` — folder, `kind` (`model`, `controller` or
  `service`), `doc_ref`
- `.talooner/review.md` — repo-wide guidelines, under 16 KiB
- `docs/guides/<area>.md` — the guide the AI review reads

If `.talooner/rules/` has any `.tln` file, `.talooner/rules.tln` is not read.
Tailor the split files instead of adding a shadowing single file.

Rules are not capped by plan.
