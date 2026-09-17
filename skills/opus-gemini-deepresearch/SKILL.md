---
name: opus-gemini-deepresearch
description: "Switch the Claude Code orchestration mode to opus-gemini-deepresearch. Opus plans the research; Gemini searches the web, writes a cited report, and a second Gemini fact-checks every citation."
disable-model-invocation: true
---

# opus-gemini-deepresearch

| Opus | Gemini |
|------|--------|
| Turns the question into a research brief, reads the summary and executive summary, rules on gaps and follow-ups | Searches and reads sources, writes the cited report, fact-checks every citation with a fresh agent, fixes |

Mode file now reads: !`mkdir -p ~/.claude && echo gemini-deepresearch > ~/.claude/exec-mode && cat ~/.claude/exec-mode`

If the line above does not show `gemini-deepresearch`, run `echo gemini-deepresearch > ~/.claude/exec-mode` with Bash.

Then confirm to the user in one line: "Mode: opus-gemini-deepresearch. Opus plans the research; Gemini searches the web, writes a cited report, and a second Gemini fact-checks every citation." The mode applies from the next prompt
and persists across sessions (the `opus-gemini-orchestrator` hook injects it into every prompt).
For how to work in this mode, load the `opus-gemini-orchestrator` skill.
