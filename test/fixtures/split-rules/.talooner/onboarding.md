# Talooner onboarding spec

## Sensitive paths

Changes here wait for a review before merge.

- `billing/` — payments — owner assigned for review

## Extra rules

- Huge PRs need a human review

## AI review

off

## Decision model

off

## AI review units

- `app/` — no guide

## Notes

Split ruleset fixture: shared defines live in `.talooner/rules/_predicates.tln`
and are joined by `.talooner/test-rules.sh`.
