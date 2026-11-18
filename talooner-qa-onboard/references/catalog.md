# The catalog

```
.talooner/qa/
├── config.yaml                 QA settings (optional)
└── blocks/<area>/*.feature     the only hand-written part: an action and its check
```

`talooner-qa catalog validate` reads it and reports every problem with
`file:line`, all at once.

## config.yaml

```yaml
time_budget: 5m          # scenarios past it are not_run, never passed (default 10m)
smoke:                   # blocks every PR runs, whatever it touches
  - open the item list
guide: docs/guides/roles.md   # who may do what; a path in the repository
guide_from: base         # base (default): a PR cannot rewrite it to pass; head: the PR's own
login: new_user_session  # the page a guest who may not lands on
```

One YAML document. An unknown key is an error, and every `smoke` name must be a
block. A missing file means the defaults: `time_budget: 10m`, no smoke, no guide
(every role question comes back unclear).

## Blocks

```gherkin
@page:order @data:order:paid
Block: refund a paid order
  When I click "Refund"
  And I confirm the dialog
  Then I see "Refunded"
```

- `Block:` names the block. Names are unique across the catalog: compose asks
  the decision model "does this PR need *refund a paid order*?", so write the
  name as what a person would check.
- `@page:<route name>` — at most one, from `/__qa/pages`. The scenario opens it
  as the role before the block's steps.
- `@data:<seed>` — from `/__qa/seeds`; may repeat. The first one fills the
  page's `:id`.
- Every block needs a `Then`: its success check. A block without one is
  rejected; it would pass by doing nothing.
- The folder under `blocks/` is the area. Match the hooks' areas where you can.

## Steps

The vocabulary is fixed; an unknown step fails its scenario, never passes it.
Elements are found by visible text and accessibility role, never CSS, and the
browser waits on its own (there is no wait step).

| step | |
|---|---|
| `I click "<text>"` | a button or link with that name |
| `I fill in "<label>" with "<value>"` | a field by its label or placeholder |
| `I confirm the dialog` | accepts the next browser dialog |
| `I see "<text>"` | visible text, a placeholder, a label, or a button or link name |
| `I don't see "<text>"` | waits for it to go away (a dialog a save closes) |
| `I am on "<page>"` | the current page is that route; `"login"` is `config.yaml`'s `login:` |

Compose adds the rest itself: who signs in (`I am "<area>:<role>"`), the
records (`"<seed>" exists`), opening the page, and `access is denied` for a role
the guide says may not.

## Writing good blocks

- Check what only that page shows: a heading, a column, an empty-state text.
  `I see "Save"` passes on half the app.
- Use the app's default locale's text, exactly as rendered.
- One flow per block. "create an order" and "approve an order" are two blocks,
  so compose can pick one.
- Prefer opening and reading. A block that changes data needs its own
  `@data:` record, so scenarios never depend on each other.
- Do not test the PR's new text here: compose copies it from the diff and
  checks it on the composed page.

## Naming

`blocks/<area>/<record>.feature`, one file per record or page group:
`blocks/inventory/items.feature`, `blocks/tickets/templates.feature`.
