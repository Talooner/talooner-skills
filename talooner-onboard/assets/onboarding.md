# Talooner onboarding spec

## Sensitive paths

Changes here wait for a review before merge.

- `.talooner/` — the review policy itself — owner assigned for review
- `auth/` — authentication and sessions — owner assigned for review
- `billing/` — payments and invoices — owner assigned for review

## Extra rules

- PRs need a description
- Very large PRs need an explicit review

## AI review

on — provider: anthropic, model: claude-sonnet-5-5

## Decision model

on — SubQ Snap

## AI review units

- `app/` — no guide
- `billing/` — docs/guides/payments.md

## Guides

- `billing/` — docs/guides/payments.md

## Notes

Replace these examples with the paths, reviewers and rules the user confirmed.

- Big at 401 changed lines or 26 changed files; huge at 1501 or 71.
- Generated files, lockfiles and fixtures count: the forge reports them.
- Drafts are skipped; the review starts when the PR is ready.
- Release: a human approval on the head commit, without a change request.
- Fallback reviewer: the CODEOWNERS owner, else the last person to touch the file.
- Auto-approve: off unless the check names are confirmed; then small, tested PRs only.
- A folder without a `doc_ref` is rules-only: no guide, no AI review.
