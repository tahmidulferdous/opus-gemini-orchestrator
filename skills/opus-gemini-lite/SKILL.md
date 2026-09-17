---
name: opus-gemini-lite
description: "Switch the Claude Code orchestration mode to opus-gemini-lite. Quality first: Opus plans, writes precise instructions, reviews every diff and runs all verification; Gemini only follows instructions."
disable-model-invocation: true
---

# opus-gemini-lite

| Opus | Gemini |
|------|--------|
| Plans, writes step-level instructions, reviews every diff line by line, runs all tests and checks | Writes the code and tests exactly as instructed |

Mode file now reads: !`mkdir -p ~/.claude && echo gemini-lite > ~/.claude/exec-mode && cat ~/.claude/exec-mode`

If the line above does not show `gemini-lite`, run `echo gemini-lite > ~/.claude/exec-mode` with Bash.

Then confirm to the user in one line: "Mode: opus-gemini-lite. Quality first: Opus plans, writes precise instructions, reviews every diff and runs all verification; Gemini only follows instructions." The mode applies from the next prompt
and persists across sessions (the `opus-gemini-orchestrator` hook injects it into every prompt).
For how to work in this mode, load the `opus-gemini-orchestrator` skill.
