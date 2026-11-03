# talooner-skills

Agent skills for Talooner onboarding and review setup.

`talooner-onboard` is a skill for Claude Code, OpenCode, Codex and other coding
agents. Your agent interviews you about the repository, writes
`.talooner/onboarding.md`, writes tested `tln` rules, guides and CI, verifies
everything with a pinned Talooner runner image, and prepares a draft PR/MR.

The skill runs in your repository. Talooner never receives your code. Your own
agent reads the repository locally, only with your consent.

## Requirements

- Docker.
- A Talooner license that includes AI review.
- An AI review key: Anthropic, OpenAI, or any OpenAI-compatible endpoint.
- A context decision model key: SubQ Snap (recommended) or Jev.

## Install

Copy the `talooner-onboard` folder into the place your agent reads skills from.

Claude Code:

```sh
mkdir -p ~/.claude/skills
cp -R talooner-onboard ~/.claude/skills/
```

Or, for one repository only:

```sh
mkdir -p .claude/skills
cp -R talooner-onboard .claude/skills/
```

OpenCode:

```sh
mkdir -p ~/.config/opencode/skills
cp -R talooner-onboard ~/.config/opencode/skills/
```

Or, for one repository only:

```sh
mkdir -p .opencode/skills
cp -R talooner-onboard .opencode/skills/
```

Codex:

```sh
mkdir -p ~/.agents/skills
cp -R talooner-onboard ~/.agents/skills/
```

Or, for one repository only:

```sh
mkdir -p .agents/skills
cp -R talooner-onboard .agents/skills/
```

Restart the agent if the skill does not appear.

## Use

Open the repository you want to onboard, start the agent, and say:

> onboard this repo to Talooner

The agent resolves the installed skill folder and runs the scripts from there.
The scripts work from any directory and take the target repository as an
argument.

## What it writes

- `.talooner/onboarding.md` — the spec and the decisions it records
- `.talooner/rules.tln` and `.talooner/rules.tln.test`
- `.talooner/rules/*.tln` plus `.talooner/test-rules.sh` for a split ruleset
- `.talooner/config.yaml` when check names are confirmed
- `.talooner/teams.yaml` when reviewers are mapped
- `.talooner/architecture.yaml` — the code AI review reads, one entry per code root
- `docs/guides/*.md` when guides are selected; a section-formatted guide turns on
  the sections review
- `.talooner/review.md` when there are repo-wide guidelines
- `.github/workflows/talooner.yml` or Talooner jobs in `.gitlab-ci.yml`

## Versioning

`metadata.version` in `talooner-onboard/SKILL.md` is the release number. The
release job fails unless the tag without its `v` equals that value, so
`metadata.version: 1.2.0` ships as `v1.2.0` and never drifts.

## What it will not do

- It never asks for, prints or writes a secret value.
- It never commits, pushes or opens a PR/MR without an explicit yes.
- It never changes branch protection, repository settings or secrets.
- It never force-pushes, resets or stashes your work.
- It never uses `git add -A`; it stages the paths it wrote.
- It deletes only branches it created in that run.
- It requires a clean tree.

## After merge

Run the probe in
[`references/post-merge-check.md`](talooner-onboard/references/post-merge-check.md)
to confirm the base branch has `.talooner/config.yaml` and that a throwaway PR
gets the comment, block and owner assignment. The same probe checks the
lifecycle: a draft is skipped, a human approval at the head releases the gate, a
change request keeps it blocked, auto-approve only touches a safe PR, and a guide
violation gets an inline comment.

## Update

```sh
git pull
```

Or download the latest release zip from
`https://github.com/Talooner/talooner-skills/releases/latest/download/talooner-onboard.zip`
and copy the folder again.

Before the first release exists, use
`https://github.com/Talooner/talooner-skills/archive/refs/heads/main.zip`.

## Security

Audit a skill before installing it. This skill contains shell scripts, rule
templates and documentation. It does not send repository contents to Talooner.
Your coding agent reads code locally with your consent; that analysis goes to the
agent and its model, not to Talooner.

## Contributing

Issues and feedback: `https://github.com/Talooner/feedback`.

Changes here need `scripts/check-skill.sh`, shellcheck, the starter rules test
and the fixture suite. See the workflow in `.github/workflows/ci.yml`.

Licensed under Apache-2.0. See `LICENSE`.
