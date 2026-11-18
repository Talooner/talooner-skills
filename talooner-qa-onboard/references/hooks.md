# The `/__qa/*` hooks

The app's test-only HTTP API. QA reads the vocabulary (roles, pages, seeds) from
it and acts through it (sign in, seed). The decision model picks pages, roles
and data only from what the PR's own app answers, so a scenario cannot name
something that does not exist, and a role, page or seed the PR adds shows up by
itself.

## Every call

- `Authorization: Bearer $TALOONER_QA_HOOK_TOKEN`. Without it the app answers
  `401` (or `404`, as if the hooks were not there). QA refuses to call hooks
  without a token.
- Under `$TALOONER_QA_PREVIEW_URL/__qa/`, outside the login wall. A redirect is
  read as "behind the login wall" and fails the run.
- A hook the app does not implement answers `404`.
- Mounted only in test or preview builds. `/__qa/login` signs in as any role.

## Vocabulary

| hook | answer |
|---|---|
| `GET /__qa/roles` | `{"<area>": ["<role>", …]}` |
| `GET /__qa/pages` | `{"<route name>": "/path/:id", …}`: named GET routes |
| `GET /__qa/seeds` | `{"seeds": ["<name>", …]}`; `{"seeds": []}` if none |

## Acting

| hook | request | answer |
|---|---|---|
| `POST /__qa/login` | `{"<area>": "<role>", …}` | `2xx`, session in `Set-Cookie`: a user with exactly these roles and no access elsewhere |
| `POST /__qa/seed` | `{"name": "<seed>"}` | the record's scalar attributes, `{"id": 42, "param": "42"}`; never secrets |
| `POST /__qa/reset` | | `2xx` |
| `POST /__qa/flag` | `{"name": "<flag>", "on": true}` | `2xx` |
| `GET /__qa/check?name=<check>` | | `{"ok": true}` or `{"ok": false}` |

A seed's attributes fill a page's params: `@page:order` with `@data:order`
opens `/orders/<param or id>`.

## Rails: talooner-qa-rails

```ruby
# Gemfile — never in the production group
group :test, :preview do
  gem "talooner-qa-rails", git: "https://github.com/Talooner/talooner-qa-rails.git", ref: "<commit>"
end
```

```ruby
# config/routes.rb
mount TaloonerQa::Engine, at: "/__qa" if defined?(TaloonerQa) && TaloonerQa.enabled?
```

`TaloonerQa.enabled?` is true only with `TALOONER_QA_HOOK_TOKEN` set, and never
in production unless `TALOONER_QA_ALLOW_PRODUCTION=1` too. Pin the gem to a
commit. Configure it in `config/initializers/talooner_qa.rb`
(`assets/talooner_qa.rb`):

- `qa.roles { {area => [role, …]} }` — what `/__qa/roles` answers. Leave out
  roles a person cannot hold (token-only, no access).
- `qa.user_for { |roles| … }` — one user per role combination, with no access
  elsewhere. Signed in with Devise's `sign_in` unless `qa.sign_in` is set.
- `qa.seeds_from_factory_bot(attributes: ->(factory) { … })` — every factory as
  `order` and every trait as `order:paid`; the lambda adds attributes every
  record needs, such as the test account.
- `qa.seeds(names: -> { … }, seed: ->(name) { … })` — a seed script that names
  what it builds. A named seed wins over a factory of the same name.
- `qa.exclude_pages(%r{\A/(api|admin/sidekiq)(/|\z)})` — routes no scenario
  should open.

## Other stacks

Implement the table above in the app's test or preview mode. Pages come from the
router's named GET routes; seeds from whatever builds test records. Start with
`roles`, `pages`, `seeds`, `login` and `seed`; `reset`, `flag` and `check` may
answer `404` until a block needs them.

## Local check

With the app running and `TALOONER_QA_HOOK_TOKEN` exported (never printed):

```sh
curl -fsS -H "Authorization: Bearer $TALOONER_QA_HOOK_TOKEN" "$URL/__qa/roles" | head -c 300
curl -fsS -H "Authorization: Bearer $TALOONER_QA_HOOK_TOKEN" "$URL/__qa/pages" | head -c 300
curl -fsS -H "Authorization: Bearer $TALOONER_QA_HOOK_TOKEN" "$URL/__qa/seeds" | head -c 300
curl -s -o /dev/null -w '%{http_code}\n' "$URL/__qa/roles"   # 401 or 404, never 200
```
