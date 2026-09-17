#!/usr/bin/env bash
# UserPromptSubmit hook: inject the current orchestration mode into every prompt.
# Modes are set by the /opus-gemini-* , /opus-sonnet and /opus-solo skills and stored in
# ~/.claude/exec-mode. Missing or unknown mode falls back to gemini-full.
set -uo pipefail
cat >/dev/null

mode="$(cat "$HOME/.claude/exec-mode" 2>/dev/null | tr -d '[:space:]')"
p="Skill: opus-gemini-orchestrator."
case "$mode" in
  gemini-lite)
    rule="MODE opus-gemini-lite: Opus plans, step-level gdo instructions, reads every diff, runs all checks. Gemini only follows instructions. $p" ;;
  gemini-mid)
    rule="MODE opus-gemini-mid: Opus plans + instructs (gdo, parallel disjoint files), runs verify, reads logic diffs, feedback via gdo -c. Gemini codes + tests. $p" ;;
  gemini-deepresearch)
    rule="MODE opus-gemini-deepresearch: Opus writes research brief (Report: line), runs gresearch in background, reads summary only, rules on gaps. Gemini researches + fact-checks. $p" ;;
  sonnet)
    rule="MODE opus-sonnet: Sonnet subagents (Agent, model sonnet) code + test; Opus plans, reviews diffs, runs tests, feedback via SendMessage. $p" ;;
  opus)
    rule="MODE opus-solo: Opus works directly. No gdo/gtask/gresearch/subagents unless asked." ;;
  *)
    rule="MODE opus-gemini-full: Opus plans, writes briefs (.orchestrate/<task>.md: Files:, Verify:), runs gtask in background, reads summary only (verdict, tests, diff stat). Gemini implements, tests, reviews, fixes. Read code only if a finding needs it. $p" ;;
esac

jq -n --arg ctx "$rule" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
