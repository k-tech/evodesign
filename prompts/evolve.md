# EvoDesign Evolution Cycle

You are running one real EvoDesign evolution cycle.

Read, in order:

1. `AGENTS.md`
2. `prompts/current.md`
3. the latest generation record, if one exists
4. the latest reflection, if one exists
5. `index.html`
6. `styles.css`
7. `script.js`
8. `README.md`

## Process

1. Observe information hierarchy, whitespace, typography, repetition, container usage, readability, visual rhythm, mobile behavior, consistency and clarity. Do not begin by searching for something to change.
2. Identify 2–4 current design decisions that should remain.
3. Choose only one meaningful, visible weakness affecting comprehension or design quality.
4. Explain its root cause and translate it into one reusable design lesson.
5. Decide `CHANGE` or `NO_CHANGE`. Use `NO_CHANGE` when evidence is weak or a modification would mainly create novelty.
6. Only when `CHANGE`, decide whether the lesson should minimally mutate the Design Prompt. Preserve prior prompt history and increment the version only when justified.
7. Make the smallest useful website modification expressing the lesson. Do not redesign the page.
8. Save a reflection, Generation JSON record and Run Log containing the prompt version, decision, timestamp and files changed.

Every run must be observable, honest and traceable. Never invent user feedback, analytics, scores, metrics or previous generations. Do not enable cron or modify files outside this repository.

## Scheduled Run Contract

When a scheduled runner provides an authoritative `RUN CONTEXT`, copy its
generation, previous generation, date, timestamp, prompt version and timezone
into the evidence. Always create these three evidence files for that context:

- `reflections/YYYY-MM-DD-gen-XXX.md`
- `generations/gen-XXX.json`
- `logs/YYYY-MM-DD-gen-XXX.log`

The generation JSON must remain valid JSON and include `generation`,
`previousGeneration`, `date`, `timestamp` (or the existing `startedAt` field),
`promptVersionBefore`, `promptVersionAfter`, `decision` (`CHANGE` or
`NO_CHANGE`) and `status: "completed"`. Use integer values for `generation` and
`previousGeneration` (zero-padded strings are also accepted by the runner for
backward compatibility).

The three evidence files are required outputs, not a restriction on the
implementation. If the reflection supports `CHANGE`, also modify the smallest
useful allowed website or prompt file before recording the evidence. Allowed
implementation files are `index.html`, `styles.css`, `script.js`, `README.md`,
`prompts/`, `reflections/`, `generations/` and `logs/`; the runner will reject
protected infrastructure changes. Do not choose `NO_CHANGE` merely because the
evidence files are required. If the same weakness has appeared in two or more
recent generations, either implement a justified minimal change or document a
new, concrete evidence gap that blocks it; do not repeat the same contract-based
reason. Do not overwrite an existing generation record, delete historical
evidence, commit, push, or edit protected infrastructure files. The runner
performs validation and owns Git operations. The runner also maintains the
root `rsi-status.json` audit snapshot; do not edit that file directly.

## Freeze Recovery

When `rsi-status.json.consecutiveNoChange >= 2` AND the gap since
`rsi-status.json.lastRun.date` is greater than one scheduler window, treat the
current cycle as a freeze-recovery run, not a true design judgment:

- State explicitly in `Observation` and `Main Weakness` that the runner was
  frozen and why the visible surfaces are being brought back into alignment
  with the on-disk evidence (cite the runner commit that fixed the freeze, if
  any).
- Restrict any website change to the smallest useful one that re-aligns
  visible surfaces with `rsi-status.json.currentGeneration`. Do not invent a
  novel design change just because the runner has been silent.
- Never choose `CHANGE` for freeze-recovery cycles whose only reason is
  "fix the gap"; the change must also reflect a real, named weakness from
  the latest reflection or a documented evidence gap that blocks a meaningful
  previous lesson.
- Always produce one `NO_CHANGE` reflection that documents the freeze window
  (with the exact dates and last-run timestamp) so the audit trail explains
  why the page did not advance on those days.

## Counter Robustness

- The runner uses `$((10#$number))` (explicit base-10 prefix) to parse every
  numeric generation field. Never reintroduce `${number##+(0)}`,
  `[ $n -gt 0 ]` or any other pattern that depends on `extglob` or that lets
  leading zeros reach arithmetic context; bash 5.x will treat them as invalid
  octal and fail silently inside `(( ))`. The runner's preflight already
  enforces a liveness cross-check (`LIVENESS_DRIFT` if the helper's count
  disagrees with the highest file on disk) and a freeze-watch log line
  (`PASS freeze_watch=...`); respect both when writing reflections or
  proposing prompt changes.
