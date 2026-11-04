# Guide prompts

A guide is short, repo-specific and checkable. It is not a copy of the
framework's documentation and not a linter config. Write it from the code and
the user's answers.

## The five questions

Ask each one, one at a time, for each root that will get a guide:

1. What must never happen here?
2. What has actually broken, or caused an incident?
3. What do reviewers always comment on?
4. What is fine and should not be commented on?
5. Show me one file that is the example to follow.

Turn 1–3 into `###` sections. Turn 4 into `.talooner/review.md` or the guide's
`## Advice`. Turn 5 into a short golden-example snippet under `## Specs`.

If the user has no opinion on a question, leave the section out. A guessed rule
becomes a false positive on every PR.

## Mine first

Before asking, read what the repository already says:

- linter and formatter configs (`.golangci.yml`, `.rubocop.yml`, `eslint`,
  `ruff.toml`, `.editorconfig`)
- architecture decision records and design docs
- `CONTRIBUTING.md`, `AGENTS.md`, `CLAUDE.md`
- `CODEOWNERS`
- postmortems and incident notes
- test helpers: what the suite already asserts

Reuse an existing rule instead of restating it. Never duplicate a linter
finding in the guide: the linter already fails CI, and a second comment is noise.

## Stack candidates

Five to eight candidate headings per stack, expanded from the questions. Keep
the ones the user confirms.

**Go**

- Errors are wrapped with context, never logged and returned.
- A goroutine has an owner and a way to stop.
- Contexts are passed, not stored.
- A public function has a test for its failure path.

**Ruby / Rails**

- A controller action stays thin; domain work lives in a model or service.
- A migration is reversible and safe on a live table.
- N+1 queries are caught before merge.
- A background job is idempotent.

**TypeScript / React**

- A component does not fetch in render.
- State that can be derived is not stored.
- Every `useEffect` has a dependency list that explains its cleanup.
- User input is validated at the boundary, not trusted by types.

**Python (Django / FastAPI)**

- A request handler validates input with a schema.
- A query in a loop is rewritten as one query.
- An exception from a dependency is not swallowed.
- A migration has a rollback plan.

**SQL / migrations**

- A migration is reversible.
- A new column is nullable or has a default.
- An index matches the query it serves.
- A destructive change is split from a deploy.

**Terraform / Kubernetes**

- A resource change is planned, not applied blind.
- A secret comes from a secret store, not a value.
- A stateful workload has a persistence and backup story.
- A limit and a request are both set.

## Good and bad sections

Good:

```markdown
## Refunds

### Refunds carry an idempotency key

Every refund call includes the caller's key, and a repeat with the same key
returns the first result instead of charging twice.

Applies to: `billing/refund.go`.
```

Bad:

```markdown
### Code quality

Make sure the code is clean, readable and follows best practices.
```

The bad one is unmeasurable, so every review either ignores it or argues with it.

## Shape

- `# <area> guide` heading.
- `## <group>` headings, then one `###` per rule under them. The section review
  only reads a `###` that sits under a `##`; a `###` straight under the `#` title
  is invisible, and a guide with none of either fails `verify.sh`.
- The first sentence of the rule is the rule.
- `Applies to:` when the rule is scoped to part of the root, with the paths in
  backticks or comma-separated. A line that names no path applies to every file.
- `## Specs` with `### <file path>` and one bullet per required case.
- `## Advice` for taste that informs but does not block.
- Six to twelve rules. Beyond that, the model loses the thread and the cost
  climbs.
