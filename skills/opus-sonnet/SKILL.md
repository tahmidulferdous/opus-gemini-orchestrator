---
name: opus-sonnet
description: "Switch the Claude Code orchestration mode to opus-sonnet. Claude only: Sonnet subagents write code and tests; Opus plans and reviews."
disable-model-invocation: true
---

# opus-sonnet

| Opus | Sonnet |
|------|--------|
| Plans, instructs, reviews diffs, runs tests | Writes code and tests |

Mode file now reads: !`mkdir -p ~/.claude && echo sonnet > ~/.claude/exec-mode && cat ~/.claude/exec-mode`

If the line above does not show `sonnet`, run `echo sonnet > ~/.claude/exec-mode` with Bash.

Then confirm to the user in one line: "Mode: opus-sonnet. Claude only: Sonnet subagents write code and tests; Opus plans and reviews." The mode applies from the next prompt
and persists across sessions (the `opus-gemini-orchestrator` hook injects it into every prompt).
For how to work in this mode, load the `opus-gemini-orchestrator` skill.
