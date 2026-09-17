---
name: opus-gemini-mid
description: "Switch the Claude Code orchestration mode to opus-gemini-mid. Balanced: Gemini writes and tests the code; Opus instructs, reviews the logic-bearing diff and runs the verify command."
disable-model-invocation: true
---

# opus-gemini-mid

| Opus | Gemini |
|------|--------|
| Plans, writes task instructions, reads logic-bearing diffs, runs the verify command, sends feedback | Writes code and tests in parallel workers, runs them, fixes feedback |

Mode file now reads: !`mkdir -p ~/.claude && echo gemini-mid > ~/.claude/exec-mode && cat ~/.claude/exec-mode`

If the line above does not show `gemini-mid`, run `echo gemini-mid > ~/.claude/exec-mode` with Bash.

Then confirm to the user in one line: "Mode: opus-gemini-mid. Balanced: Gemini writes and tests the code; Opus instructs, reviews the logic-bearing diff and runs the verify command." The mode applies from the next prompt
and persists across sessions (the `opus-gemini-orchestrator` hook injects it into every prompt).
For how to work in this mode, load the `opus-gemini-orchestrator` skill.
