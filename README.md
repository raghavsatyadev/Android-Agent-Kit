# Android Agent Kit

A drop-in setup for coding agents (Claude Code, Gemini, Codex, Cursor) in an Android repo. It
holds rules, skills, git hooks and scripts that keep agents cheap and careful: build before
"done", ktfmt formatting, PR-only branch policy, on-device bug reproduction with ARTEMIS, and
compact Gradle output. Taken from a real Compose Multiplatform app and made app-neutral.

## What is inside

| Path | Purpose |
| --- | --- |
| `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` | one agent index (template) and two pointers |
| `.agents/rules/` | android-build, format, branch-pr-policy, artemis-mobile-testing |
| `.agents/skills/` | fix-issue, android-device-test, compose-screenshot-test, cmp-best-practices, material3-expressive, workspace-cleanup, project-onboarding-setup |
| `scripts/` | setup-env (.ps1/.sh), ci-local, gradle-agent, check-done, evidence-hash, hooks helpers |
| `.githooks/` | pre-commit (ktfmt), pre-push (ci-local) |
| `.claude/settings.json` | permissions and the prompt-routing and Stop hooks |
| `.maestro/` | empty; see its README to record replayable flows (Maestro 2.x) |

## Install

```bash
./install.sh /path/to/android-repo            # never overwrites
./install.sh /path/to/android-repo --force    # overwrite existing files
./install.sh /path/to/android-repo --dry-run  # show only
```

It prints what it copied and what to fill. Then append `gradle.properties.snippet` and
`gitignore.snippet`, run `git config core.hooksPath .githooks`, and run `scripts/setup-env.sh`
(or `.ps1`) once.

## Config: `agent-kit.env`

One file at the repo root, read by every script and hook.

```
APP_MODULE=:app        # Gradle module of the app
APP_VARIANT=Debug      # build variant; DevDebug etc. when the app has flavors
APPLICATION_ID=        # used by the device-test scripts
BASE_BRANCH=development
KTFMT_VERSION=         # blank = latest release
NDK_VERSION=           # blank = skip the NDK check
```

`AGENTS.md` uses `{{PLACEHOLDER}}` markers; the docs use `<BASE_BRANCH>`, `<app>` and
`<applicationId>` hints. Replace them with your values.

## Optional: Nimble / Laya hooks

A small local decision model reads long logs so the agent does not. `route-prompt.sh` (prompt
routing), `gradle-agent.sh` (failure hints), `check-done.sh` and `tools/nimble-skill/` use it
when present and do nothing when it is missing. `setup-env` picks by hardware: Nimble
(`ollama pull nimble`, Ollama 0.35+, about 9 GB VRAM) or Laya (pip, smaller). Env vars:
`NIMBLE_URL`, `NIMBLE_MODEL`, `NIMBLE_MAX_BYTES`.