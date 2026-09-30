---
name: nimble
description: Ask the local decision model (Nimble on Ollama, or Laya) a yes/no or pick-one question about a long log, file or command output instead of reading it into context. Use before reading a big build log, test output, logcat dump or generated file when you only need a verdict (passed? which failure kind? does it mention X?).
---

# Nimble: cheap local verdicts

A local "System One" model answers on this PC through `/v1/systemone`: Nimble on Ollama
(`127.0.0.1:11434`) or Laya (`127.0.0.1:8000`, set by `NIMBLE_URL`/`NIMBLE_MODEL`). A warm call
takes about 50–110 ms and costs no Claude tokens. Use it to decide **whether** to read something,
not to replace reading when you must fix code.

## Command

```bash
~/.claude/nimble/nimble-ask yesno  "Does this output show the build passed?"            < log.txt
~/.claude/nimble/nimble-ask choice "What kind of failure is this?" \
    kotlin="Kotlin compiler errors (e: lines)" deps="Could not resolve a dependency" \
    oom="OutOfMemoryError or daemon died" other="none of these"                        < log.txt
some-command 2>&1 | ~/.claude/nimble/nimble-ask yesno "Did any test fail?"
```

- Output: `yes 0.97` / `no 0.03` (P(yes)), or `<label> <probability>`.
- Exit 2: the model is off, unreachable or gave a bad answer. Read the text the normal way.
- Only the **tail** of long input is sent: ~6K tokens on Nimble, ~400 on Laya. Pipe a `grep` or
  `tail` first so the part that matters is at the end.
- The first call after a while can take a few seconds while the model loads.

## When to trust it

- Act on it alone only when the probability is ≥ 0.9 (yesno ≥ 0.9 or ≤ 0.1). Between those,
  read the relevant part yourself.
- Always offer an `other` label in `choice`, so it is not forced into a wrong class.
- A "passed" verdict is not evidence for the user. Quote the real line (`BUILD SUCCESSFUL`, the
  test count) before claiming done.
- Never send secrets, tokens or `.env` content. It is local, but keep the habit.

## Settings

`NIMBLE_URL` (default `http://127.0.0.1:11434`), `NIMBLE_MODEL` (default `nimble`),
`NIMBLE_MAX_BYTES` (input budget), `NIMBLE_TIMEOUT` seconds (default 30), `NIMBLE_HOOKS=0` turns it
off.
