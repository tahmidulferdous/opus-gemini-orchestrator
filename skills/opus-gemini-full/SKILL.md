---
name: opus-gemini-full
description: "Switch the Claude Code orchestration mode to opus-gemini-full. Least Claude usage: Opus plans and reads verdicts; Gemini implements, tests, reviews and fixes."
disable-model-invocation: true
---

# opus-gemini-full

| Opus | Gemini |
|------|--------|
| Plans, writes task briefs, reads the verdict and test result, rules on findings | Implements, writes and runs tests, reviews with a fresh agent, fixes until review passes |

Mode file now reads: !`mkdir -p ~/.claude && echo gemini-full > ~/.claude/exec-mode && cat ~/.claude/exec-mode`

If the line above does not show `gemini-full`, run `echo gemini-full > ~/.claude/exec-mode` with Bash.

Then confirm to the user in one line: "Mode: opus-gemini-full. Least Claude usage: Opus plans and reads verdicts; Gemini implements, tests, reviews and fixes." The mode applies from the next prompt
and persists across sessions (the `opus-gemini-orchestrator` hook injects it into every prompt).
For how to work in this mode, load the `opus-gemini-orchestrator` skill.
