---
name: opus-solo
description: "Switch the Claude Code orchestration mode to opus-solo. Claude only: Opus does all work directly, no delegation."
disable-model-invocation: true
---

# opus-solo

Opus plans and does the work itself. No gdo, gtask, gresearch or subagents unless asked.

Mode file now reads: !`mkdir -p ~/.claude && echo opus > ~/.claude/exec-mode && cat ~/.claude/exec-mode`

If the line above does not show `opus`, run `echo opus > ~/.claude/exec-mode` with Bash.

Then confirm to the user in one line: "Mode: opus-solo. Claude only: Opus does all work directly, no delegation." The mode applies from the next prompt
and persists across sessions (the `opus-gemini-orchestrator` hook injects it into every prompt).
For how to work in this mode, load the `opus-gemini-orchestrator` skill.
