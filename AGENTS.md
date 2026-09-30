# AGENTS.md

Shared instructions for every coding agent in this repo — Claude, Gemini, Codex, Cursor.
`CLAUDE.md` and `GEMINI.md` just point here.

**{{APP_NAME}}** — {{ONE_LINE_DESCRIPTION}}.
Modules: {{MODULES}} · app module `{{APP_MODULE}}` · applicationId `{{APPLICATION_ID}}` ·
base branch `{{BASE_BRANCH}}`. Values also live in `agent-kit.env`.

## How to work

- Do only what the task asks: no unrequested features, tests, files, docs or refactors.
- Ask only when blocked, or before an action that needs approval (push, PR).
- Before "done", run the check for the change (android-build.md); if none can run, say why.
- When done and checked, stop. Report in five lines or fewer, in ASD-STE100 Simplified Technical English.
- Claude Code: medium effort for scoped edits; high for native or architecture work. A second
  agent only for a review the user asked for.

## Rules — `.agents/rules/`

| Rule | Read it when |
| --- | --- |
| [android-build.md](.agents/rules/android-build.md) | before calling any task done — the code must compile |
| [format.md](.agents/rules/format.md) | touching any Kotlin — ktfmt Google style is mandatory |
| [artemis-mobile-testing.md](.agents/rules/artemis-mobile-testing.md) | *on demand* — using ARTEMIS MCP tools |
| [branch-pr-policy.md](.agents/rules/branch-pr-policy.md) | *always* — see the summary below |

## Skills — `.agents/skills/`

One folder per skill; each `SKILL.md` `description` says when to read it. Claude Code sees them
through the `.claude/skills/` links that `scripts/setup-env.*` create.

## Commands

New machine: run the setup doctor first — `scripts/setup-env.ps1` (Windows) or
`scripts/setup-env.sh` (macOS/Linux).

```bash
scripts/ci-local.sh                      # ktfmt + compileDebugKotlin — run before pushing
scripts/gradle-agent.sh <tasks>          # agents: Gradle with errors only; full log in tmp/
./gradlew {{APP_MODULE}}:assembleDebug   # build
./gradlew {{APP_MODULE}}:testDebugUnitTest
git config core.hooksPath .githooks      # once: pre-commit runs ktfmt, pre-push runs ci-local.sh
```

`ci-local.sh` flags: `--fix` reformats, `--format-only` skips the compile, `--committed-only`
matches CI exactly. Never format with a `ktfmt` from your PATH; `ci-local.sh` fetches the right one.

## Branches & PRs (strict)

Never push to `{{BASE_BRANCH}}` or `master`. Branch off `origin/{{BASE_BRANCH}}` as `<type>/<slug>`,
push, and open a PR against `{{BASE_BRANCH}}` with `gh pr create --body-file <file>` (never inline
`--body`). Never merge or approve a PR — hand off the URL.

## Working on a bug

Follow [project-onboarding-setup](.agents/skills/project-onboarding-setup/SKILL.md) Part 2
(`/fix-issue <url>` in Claude Code): reproduce on the device → diagnose from real device state →
fix with a test that fails on the old behaviour → reinstall and re-run the reproduction → PR, stop.
A green unit test is not device verification. Inspect the device with ARTEMIS, not
`uiautomator dump`, which rebinds accessibility services.

## Housekeeping

`tmp/` (agent scratch), `memory/` (persistent local data such as device serials),
`.cache/` and every `.env` are git-ignored. Never commit credentials. Never clean `tmp/` unless the
user asks — see [workspace-cleanup](.agents/skills/workspace-cleanup/SKILL.md).
