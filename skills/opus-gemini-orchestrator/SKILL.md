---
name: opus-gemini-orchestrator
description: Claude Opus plans, instructs and verifies while Gemini (Antigravity CLI `agy`) writes code, writes and runs tests, reviews, and does deep web research, to cut Claude usage without cutting quality. Use before delegating any implementation or research, when the prompt shows an opus-gemini/opus-sonnet/opus-solo MODE, and whenever driving the Antigravity CLI from Claude Code.
---

# Opus plans, Gemini builds

Claude usage is scarce, Gemini quota is not. Opus spends tokens on decisions: plan, briefs,
verdicts, rulings. Gemini spends tokens on volume: code, tests, review, research. Quality comes
from gates, not from Opus re-reading: precise brief, tests that must pass, independent Gemini
reviewer or fact-checker, bounded fix loop.

## Modes

A hook injects `MODE ...` into every prompt (from `~/.claude/exec-mode`). Follow it. User switches
with the slash command.

| Command | Opus | Gemini | Claude usage |
|---------|------|--------|--------------|
| `/opus-gemini-lite` | plan, step-level instructions, reads every diff, runs all checks | follows instructions | highest |
| `/opus-gemini-mid` | plan, instructions, reads logic diffs, runs verify | code + tests, parallel workers | medium |
| `/opus-gemini-full` | plan, briefs, reads verdicts | implement, test, review, fix (`gtask`) | lowest |
| `/opus-gemini-deepresearch` | research brief, reads summary | research, cite, fact-check, fix (`gresearch`) | lowest |
| `/opus-sonnet` | plan, instructions, review | Sonnet subagents instead of Gemini | Claude only |
| `/opus-solo` | everything | nothing | Claude only |

agy missing, signed out, or out of quota (`agy -p "/usage"`): tell the user, suggest
`/opus-sonnet`. Never silently do the work in Opus.

## Tools

In `bin/`, linked into `~/.local/bin` by `scripts/install.sh`. Run from the project root.

| Command | Does | Prints |
|---------|------|--------|
| `gdo "task"` | one Gemini call with executor contract | `STATUS` `FILES` `VERIFY` `NOTES`, git status |
| `gdo -c <id> "msg"` | same conversation: feedback, answers | same |
| `gdo -l` | this folder's agy conversations (headless `/resume`) | id, title, steps |
| `gtask <brief>` | implement, run `Verify:`, fresh-Gemini review, max 2 fix rounds | verdict, test tail, diff stat, Critical/Important |
| `gresearch <brief>` | web research, fresh-Gemini checks every URL, max 2 fix rounds | verdict, sources, unsupported claims, executive summary |

- Non-zero exit on any failure, including permission soft-denials agy reports as success.
- Env: `GDO_MODEL` (`gemini-3.8-flash-high`; use `gemini-3.1-pro-high` for hard reasoning),
  `GDO_EFFORT` (`high`), `GDO_TIMEOUT` (`20m`), `GTASK_ROUNDS`, `GRESEARCH_ROUNDS` (`2`).
- Always `run_in_background: true`. Parallel workers in ONE background call
  (`gtask a.md & gtask b.md & wait`): one wake-up, not one per worker. Never poll.
- Each Gemini call costs about a minute and ~27k Gemini tokens of fixed overhead: batch small
  same-shape edits into one task instead of many calls.

## Brief (all Gemini modes)

Gemini sees only the brief. Put it in `.orchestrate/<task>.md` (git-ignored):

- `Files: <paths>`: only files the task may touch. gtask diffs exactly these.
- `Verify: <command>`: exits 0 when done. The script runs it; Gemini cannot run bash.
- One or two lines of context; point to files, never paste them.
- Exact interfaces: names, signatures, return shapes, constants, formats.
- Decisions already made. Gemini never chooses.
- Test cases by input and expected output. Gemini writes tests; Opus picks what they cover.
- Acceptance criteria, out-of-scope items.

Parallel tasks need disjoint `Files:` and tests that do not depend on each other's unfinished code.

## opus-gemini-full

1. Plan: short `PLAN.md`, contracts, file ownership. Read only what the plan needs.
2. Brief each task. 3. `gtask` (background, parallel when disjoint).
4. Accept only when: `PASS`, tests exit 0, diff stat lists only brief files. Do not read code.
5. FAIL: read `<task>.review.md`, rule, then `gdo -c <implementer id> "<exact fix>"` and rerun
   `Verify:`, or tighten brief and rerun `gtask`. `IMPLEMENTER_NOT_DONE`: answer its question
   via `gdo -c`.
6. Integrate: run full tests yourself. One read-only whole-feature review:
   `gdo "Read-only review of <feature> against PLAN.md; write .orchestrate/final-review.md; reply
   Critical/Important only"`. Fix findings with another `gtask`.
7. Before shipping anything that runs on other machines or touches user config (installers,
   auth, deletion), read that code's risky paths yourself. Tests pass on what they cover only.

## opus-gemini-mid

Plan, disjoint tasks, `gdo "Read the brief at .orchestrate/<task>.md ..."`. On return: run
`Verify:` yourself, read `git diff -- <logic files>`, skim boilerplate. Feedback `gdo -c <id>`
until right. Integrate with a full test run.

## opus-gemini-lite

Like mid, plus: step-level instructions (what, where, in which order); read every diff in full;
run every check yourself, never trust Gemini's `VERIFY`; one task at a time unless trivially
independent.

## opus-gemini-deepresearch

1. Ambiguous question: ask the user 1-2 questions. Else pick defaults, state them in the brief.
2. Brief `.orchestrate/research-<topic>.md`: `Report: research/<topic>.md`, main question,
   3-6 sub-questions, scope (time window, source types, exclusions), what the answer is for.
3. `gresearch` (background; independent topics in parallel).
4. Read the printed summary only.
5. PASS: answer from the executive summary, link the report. FAIL or gaps: `gdo -c <researcher
   id> "<follow-up>"` or a narrower brief. Spot-check a claim yourself only if it drives a
   high-stakes decision.

## opus-sonnet

Mid loop with the Agent tool (`subagent_type: "general-purpose"`, `model: "sonnet"`) in Gemini's
place: parallel Agent calls in one message, feedback via `SendMessage`, same
`STATUS`/`FILES`/`VERIFY`/`NOTES` report.

## Rules

- Executors never decide. `BLOCKED` is answered by Opus.
- Implementer's own report is never proof (see accept rules per mode).
- Never `--dangerously-skip-permissions`. `DENIED:` means the run died on an unallowed tool:
  scripts retry once steering around it; if it persists, give the user the exact rule to add.
- agy headless rejects compound shell lines (`a | b`, `a && b`, `>`): keep `Verify:` for the
  scripts to run, not for Gemini.
- Never test the tools with dummy tasks inside a real project: they do real work.
- Never continue an agy conversation the user started unless asked.
- Executors never commit, push or reset. Opus commits only when the user asks.

## Reference

[reference/agy-cli.md](reference/agy-cli.md): Antigravity CLI for orchestrators: headless flags,
JSON output, permissions and headless pitfalls, web tools, projects and conversations, slash
commands, Gemini's own subagents. Read before changing scripts or agy permissions.
