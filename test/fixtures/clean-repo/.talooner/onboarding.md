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

- `app/` — docs/guides/app.md

## Guides

- `app/` — docs/guides/app.md

## Notes

Thresholds: big at 401 lines or 26 files, huge at 1501 lines or 71 files.
Generated and lockfile files count, because the forge reports them.
Drafts are skipped; the review starts when the PR is ready.
Release: a human approval on the head commit, without a change request.
Fallback reviewer: the CODEOWNERS owner, else the last toucher.
Folders outside `app/` are rules-only: no guide, no AI review.
