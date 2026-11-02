# Interview script

Ask one question at a time and wait. Silence is not consent. The defaults below
are suggestions, not answers.

## 0. Preflight

Say: "I will check the repository first. Nothing is written in this step."

Run `scripts/doctor.sh` from the repository root. Report the repo, remote host,
branch, clean/dirty state, existing Talooner files, CI files, Docker and pinned
image status, and which credential names are present. Never print a value.

Stop conditions:

- Not a git repository, or the current directory is not the repository root.
- The working tree is dirty. Ask the user to commit or stash.
- Docker is missing or the pinned image cannot run.
- The remote is ambiguous. Ask instead of guessing.

## 1. Scope and consent

Question: "May I read the repository to propose sensitive paths and reviewers?"

Levels:

- **Layout only** — folder names, manifests, CI, CODEOWNERS, README.
- **Targeted (default)** — layout plus the folders the user approves, dependency
  manifests, CI, and existing docs.
- **Deep** — source and tests in the approved folders.

Say plainly: "Your coding agent reads the files locally, with your consent. That
analysis goes to your agent and its model, not to Talooner. Talooner never
receives code. In CI, Talooner sends forge API calls, your own model provider
calls where a rule asks for them, the license check, and a run summary."

Do not read source before an explicit yes.

If the user says no: stay at layout only, write the spec from what they tell you,
and leave guides out.

## 2. License

Question: "Do you already have a Talooner license key with AI review?"

No:

- Free demo: `https://talooner.dev/#pilot`.
- Open source: `https://talooner.dev/#apply-open-source`.
- Explain the 10-day demo.
- Ask the user to export `TALOONER_LICENSE_KEY` in their shell, then wait.
- Do not accept the key in chat.

Yes:

- Ask them to export it in the shell.
- Run `scripts/decode-license.sh`.
- Read only `ai_review`, `expired` and `expires`.
- If `expired=yes`: say it may be an old key, send them to their license page for
  the current key, then run the decode again.
- If `ai_review=no`: say this key does not include AI review. If they upgraded or
  applied for a demo or open-source license, get the current key first.
- If `format=bad` or `format=unknown`: stop and explain how to copy the full key.
- Never treat a local `valid` as proof the license is active. The online check on
  the first CI run is authoritative.

Stop until the user confirms the current key includes AI review.

## 3. AI review provider

Question: "Which model provider should AI review use?"

- Anthropic: `ANTHROPIC_API_KEY`, default model `claude-sonnet-5-5`.
- OpenAI: `OPENAI_API_KEY` plus `TALOONER_MODEL`.
- OpenAI-compatible: `TALOONER_MODEL_BASE_URL`, `TALOONER_MODEL`,
  `TALOONER_MODEL_API_KEY`.

Ask the user to export the key in the shell. Do not take the value in chat.
Explain that the provider bills the calls, not Talooner. Stop if no key is
present.

## 4. Context decision model

Question: "Which context decision model will you use?"

- **SubQ Snap (recommended)** — `CDM_URL=https://api.subq.ai/v1/systemone`,
  backend `subq`, default model `subq-snap-preview`.
- **Jev** — `CDM_URL=https://api.typesafe.ai/v1/systemone`.

Ask the user to export `CDM_URL` and `CDM_TOKEN`, and optionally `CDM_MODEL`.
Explain SubQ data retention: turn on zero data retention before it sees real
code. Jev is supported too. Stop if either value is missing. Both AI review and a
decision model are required.

## 5. Forge and token

Say what was detected.

- **GitHub Actions** supplies `GITHUB_TOKEN`; no new secret. The repository
  setting "Allow GitHub Actions to create and approve pull requests" must be on.
- **GitLab** needs a project or group access token with the Developer role and
  the `api` scope, stored as a masked `GITLAB_TOKEN` CI/CD variable. Do not ask
  for the value.
- **Self-managed GitLab** sets `CI_API_V4_URL` inside CI. Outside CI the user
  sets `GITLAB_API_URL`. Confirm the host.

## 6. Advice mode

Question: "Should blocking verdicts be advisory for the first weeks?"

Explain `TALOONER_ADVICE_MODE=1`: blocking verdicts exit 0, the check reports
"Changes requested (advisory)", and Talooner writes no `REQUEST_CHANGES` or
unapprove. Runtime errors still exit 1. Recommend enabling it for the first weeks.
Default yes.

## 7. Sensitive paths

Propose paths from folder layout and CODEOWNERS: auth and permissions, payments
and billing, migrations, deploy and infrastructure, CI, secrets, public APIs,
data deletion.

For each, ask:

- What is this code responsible for?
- Who reviews it? A GitHub team slug, a GitLab group, or a list of users.
- Should a change hold the merge while blocking is on?

Confirm, drop or add. Never invent a business rule.

If there is no CODEOWNERS and no team mapping, use a real user target or leave the
rule out.

## 8. Extra rules

Ask only where they apply:

- Must PRs have a description?
- Large and huge PR thresholds? Defaults 500 and 1500 lines.
- Must new dependencies get a security review? Only if a manifest exists.
- Must migrations get a DBA review? Only if migrations exist.
- Are generated, vendor or lockfile-only PRs special-cased?
- Anything else?

## 9. Auto-approve

Default no. Explain that auto-approve is the riskiest rule. If requested, require
confirmed test and lint check names, and approve only small, tested, documented,
non-sensitive, non-draft PRs. Add tests for unset facts and critical paths.

## 10. Check names

Detect test and lint jobs from CI.

- GitHub: the job `name` or id is the check-run name.
- GitLab: the job key is the commit status name.

Ask the user to confirm. Write `.talooner/config.yaml` only with confirmed names.
If unsure, leave the section commented. Then `pr.tests_passing` and
`pr.lint_passing` stay unset, so auto-approve never fires.

## 11. Guides

Propose candidate folders from the approved analysis, not just sensitive ones.
Explain the cost: each guide adds tokens to AI review and needs a real interview.

For each selected folder ask:

- What is this code responsible for?
- Which mistakes have hurt you here?
- What must never happen?
- What does the wrong version look like?
- Which tests must exist for each file?

Write `architecture.yaml` entries and `docs/guides/<area>.md`. Check each section
against the current code and report violations; do not fix them silently.

## 12. Repo-wide guidelines

Ask for concrete rules that apply to every review. Write `.talooner/review.md`
only when there are real guidelines, and keep it under 16 KiB.

## 13. PR and commit

Ask:

- Draft or ready PR/MR? Default draft.
- Branch name? Default `talooner/onboard`.
- Commit message.
- Leave it local only, or push after approval?

## 14. Anything else

Ask whether there is anything else Talooner should know.
