#!/usr/bin/env bash
set -euo pipefail

# Run from repo root. BIN=skills/opus-gemini-orchestrator/bin.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO_ROOT"

BIN="skills/opus-gemini-orchestrator/bin"
BIN_ABS="$REPO_ROOT/$BIN"

# Temp dirs (mktemp -d, trap cleanup) and a fake HOME
TMP_DIR="$(mktemp -d)"
FAKE_HOME="$(mktemp -d)"
STUB_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR" "$FAKE_HOME" "$STUB_DIR"
}
trap cleanup EXIT INT TERM

# Put a stub dir first in PATH with an agy stub that prints agy stub called to stderr and exits 1
cat <<'EOF' > "$STUB_DIR/agy"
#!/usr/bin/env bash
echo "agy stub called" >&2
exit 1
EOF
chmod +x "$STUB_DIR/agy"
export PATH="$STUB_DIR:$PATH"

# Check helper prints PASS - name / FAIL - name, counts failures, exits 1 if any failed, prints a final count.
passes=0
failures=0
skips=0

pass() {
  local name="$1"
  passes=$((passes + 1))
  echo "PASS - $name"
}

fail() {
  local name="$1"
  failures=$((failures + 1))
  echo "FAIL - $name"
}

skip() {
  local name="$1"
  skips=$((skips + 1))
  echo "SKIP - $name"
}

# -----------------------------------------------------------------------------
# Case 1: Hook, per mode
# -----------------------------------------------------------------------------
mkdir -p "$FAKE_HOME/.claude"

MODES=(
  "gemini-lite:MODE opus-gemini-lite"
  "gemini-mid:MODE opus-gemini-mid"
  "gemini-full:MODE opus-gemini-full"
  "gemini-deepresearch:MODE opus-gemini-deepresearch"
  "sonnet:MODE opus-sonnet"
  "opus:MODE opus-solo"
)

for item in "${MODES[@]}"; do
  mode="${item%%:*}"
  expected="${item#*:}"
  test_name="hook per mode $mode"

  echo "$mode" > "$FAKE_HOME/.claude/exec-mode"
  set +e
  out=$(echo '{}' | HOME="$FAKE_HOME" "$BIN/exec-mode-hook.sh" 2>/dev/null)
  hook_rc=$?
  set -e

  if [ $hook_rc -eq 0 ] && echo "$out" | jq empty >/dev/null 2>&1; then
    event_name=$(echo "$out" | jq -r '.hookSpecificOutput.hookEventName // empty')
    has_str=$(echo "$out" | jq -r --arg exp "$expected" 'if (.hookSpecificOutput.additionalContext // "") | contains($exp) then "true" else "false" end')
    if [ "$event_name" = "UserPromptSubmit" ] && [ "$has_str" = "true" ]; then
      pass "$test_name"
    else
      fail "$test_name"
    fi
  else
    fail "$test_name"
  fi
done

# -----------------------------------------------------------------------------
# Case 2: Hook fallback
# -----------------------------------------------------------------------------
# Subcase 2a: No exec-mode file gives MODE opus-gemini-full
rm -f "$FAKE_HOME/.claude/exec-mode"
test_name="hook fallback no exec-mode file"
set +e
out=$(echo '{}' | HOME="$FAKE_HOME" "$BIN/exec-mode-hook.sh" 2>/dev/null)
hook_rc=$?
set -e

if [ $hook_rc -eq 0 ] && echo "$out" | jq empty >/dev/null 2>&1; then
  event_name=$(echo "$out" | jq -r '.hookSpecificOutput.hookEventName // empty')
  has_str=$(echo "$out" | jq -r 'if (.hookSpecificOutput.additionalContext // "") | contains("MODE opus-gemini-full") then "true" else "false" end')
  if [ "$event_name" = "UserPromptSubmit" ] && [ "$has_str" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name"
  fi
else
  fail "$test_name"
fi

# Subcase 2b: exec-mode containing garbage gives MODE opus-gemini-full
echo "garbage" > "$FAKE_HOME/.claude/exec-mode"
test_name="hook fallback garbage mode"
set +e
out=$(echo '{}' | HOME="$FAKE_HOME" "$BIN/exec-mode-hook.sh" 2>/dev/null)
hook_rc=$?
set -e

if [ $hook_rc -eq 0 ] && echo "$out" | jq empty >/dev/null 2>&1; then
  event_name=$(echo "$out" | jq -r '.hookSpecificOutput.hookEventName // empty')
  has_str=$(echo "$out" | jq -r 'if (.hookSpecificOutput.additionalContext // "") | contains("MODE opus-gemini-full") then "true" else "false" end')
  if [ "$event_name" = "UserPromptSubmit" ] && [ "$has_str" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name"
  fi
else
  fail "$test_name"
fi

# Subcase 2c: mode file with trailing newline and spaces works
printf "   gemini-lite   \n\n" > "$FAKE_HOME/.claude/exec-mode"
test_name="hook mode file with whitespace and trailing newline"
set +e
out=$(echo '{}' | HOME="$FAKE_HOME" "$BIN/exec-mode-hook.sh" 2>/dev/null)
hook_rc=$?
set -e

if [ $hook_rc -eq 0 ] && echo "$out" | jq empty >/dev/null 2>&1; then
  event_name=$(echo "$out" | jq -r '.hookSpecificOutput.hookEventName // empty')
  has_str=$(echo "$out" | jq -r 'if (.hookSpecificOutput.additionalContext // "") | contains("MODE opus-gemini-lite") then "true" else "false" end')
  if [ "$event_name" = "UserPromptSubmit" ] && [ "$has_str" = "true" ]; then
    pass "$test_name"
  else
    fail "$test_name"
  fi
else
  fail "$test_name"
fi

# -----------------------------------------------------------------------------
# Case 3: gtask
# -----------------------------------------------------------------------------
# 3a: no argument exits non-zero
test_name="gtask no argument exits non-zero"
set +e
out=$("$BIN/gtask" 2>&1)
rc=$?
set -e
if [ $rc -ne 0 ]; then
  pass "$test_name"
else
  fail "$test_name"
fi

# 3b: nonexistent brief exits 2 and prints "no brief"
test_name="gtask nonexistent brief exits 2 and prints no brief"
set +e
out=$("$BIN/gtask" "$TMP_DIR/nonexistent.md" 2>&1)
rc=$?
set -e
if [ $rc -eq 2 ] && [[ "$out" == *"no brief"* ]]; then
  pass "$test_name"
else
  fail "$test_name"
fi

# 3c: inside a temp git repo, brief without Files:/Verify: lines exits 2 and prints "needs 'Files:' and 'Verify:'"
test_name="gtask brief missing Files and Verify in git repo"
GIT_REPO_DIR="$TMP_DIR/gtask_git_repo"
mkdir -p "$GIT_REPO_DIR"
git -C "$GIT_REPO_DIR" init -q
echo "# Brief without required headers" > "$GIT_REPO_DIR/brief.md"
set +e
out=$(cd "$GIT_REPO_DIR" && "$BIN_ABS/gtask" "$GIT_REPO_DIR/brief.md" 2>&1)
rc=$?
set -e
if [ $rc -eq 2 ] && [[ "$out" == *"needs 'Files:' and 'Verify:'"* ]]; then
  pass "$test_name"
else
  fail "$test_name"
fi

# 3d: in a temp dir that is not a git repo exits 2 and prints "not a git repo"
test_name="gtask non-git temp dir exits 2 and prints not a git repo"
NON_GIT_DIR="$TMP_DIR/gtask_non_git"
mkdir -p "$NON_GIT_DIR"
echo "# Dummy brief" > "$NON_GIT_DIR/brief.md"
set +e
out=$(cd "$NON_GIT_DIR" && "$BIN_ABS/gtask" "$NON_GIT_DIR/brief.md" 2>&1)
rc=$?
set -e
if [ $rc -eq 2 ] && [[ "$out" == *"not a git repo"* ]]; then
  pass "$test_name"
else
  fail "$test_name"
fi

# -----------------------------------------------------------------------------
# Case 4: gresearch
# -----------------------------------------------------------------------------
# 4a: no argument exits non-zero
test_name="gresearch no argument exits non-zero"
set +e
out=$("$BIN/gresearch" 2>&1)
rc=$?
set -e
if [ $rc -ne 0 ]; then
  pass "$test_name"
else
  fail "$test_name"
fi

# 4b: nonexistent brief exits 2 and prints "no brief"
test_name="gresearch nonexistent brief exits 2 and prints no brief"
set +e
out=$("$BIN/gresearch" "$TMP_DIR/nonexistent_research.md" 2>&1)
rc=$?
set -e
if [ $rc -eq 2 ] && [[ "$out" == *"no brief"* ]]; then
  pass "$test_name"
else
  fail "$test_name"
fi

# 4c: brief without Report: line exits 2 and prints "needs a 'Report:"
test_name="gresearch brief without Report line exits 2"
NO_REPORT_FILE="$TMP_DIR/no_report_brief.md"
echo "# Research brief without report header" > "$NO_REPORT_FILE"
set +e
out=$("$BIN/gresearch" "$NO_REPORT_FILE" 2>&1)
rc=$?
set -e
if [ $rc -eq 2 ] && [[ "$out" == *"needs a 'Report:"* ]]; then
  pass "$test_name"
else
  fail "$test_name"
fi

# -----------------------------------------------------------------------------
# Case 5: gdo
# -----------------------------------------------------------------------------
# gdo "" </dev/null exits 2 and prints "empty task"
test_name="gdo empty task exits 2 and prints empty task"
set +e
out=$("$BIN/gdo" "" </dev/null 2>&1)
rc=$?
set -e
if [ $rc -eq 2 ] && [[ "$out" == *"empty task"* ]]; then
  pass "$test_name"
else
  fail "$test_name"
fi

# -----------------------------------------------------------------------------
# Case 6: gdo -l
# -----------------------------------------------------------------------------
test_name="gdo -l with conversation database"
if ! command -v sqlite3 >/dev/null 2>&1; then
  skip "$test_name"
else
  DB_DIR="$FAKE_HOME/.gemini/antigravity-cli"
  mkdir -p "$DB_DIR"
  DB_FILE="$DB_DIR/conversation_summaries.db"
  rm -f "$DB_FILE"

  sqlite3 "$DB_FILE" "CREATE TABLE conversation_summaries(conversation_id text, title text, step_count integer, last_modified_time text, workspace_uris text, project_id text);"

  SPACE_DIR="$TMP_DIR/dir with space"
  mkdir -p "$SPACE_DIR"

  ENCODED_URI=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote("file://"+sys.argv[1], safe="/:"))' "$SPACE_DIR")
  JSON_URIS=$(jq -n -c --arg uri "$ENCODED_URI" '[$uri]')

  sqlite3 "$DB_FILE" "INSERT INTO conversation_summaries (conversation_id, title, step_count, last_modified_time, workspace_uris, project_id) VALUES ('conv-1', 'Demo Conversation', 5, '2026-09-17 12:00:00', '$JSON_URIS', 'proj-1');"

  set +e
  out=$(cd "$SPACE_DIR" && HOME="$FAKE_HOME" "$BIN_ABS/gdo" -l 2>&1)
  rc=$?
  set -e

  if [ $rc -eq 0 ] && [[ "$out" == *"Demo Conversation"* ]]; then
    pass "$test_name"
  else
    fail "$test_name"
  fi
fi

# -----------------------------------------------------------------------------
# Case 7: Skills
# -----------------------------------------------------------------------------
skills_found=0
re_name='^[a-z0-9-]+$'

for skill_file in skills/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  skills_found=$((skills_found + 1))
  dir_name="$(basename "$(dirname "$skill_file")")"
  test_name="skill metadata $dir_name"

  first_line="$(head -n 1 "$skill_file")"
  if [ "$first_line" != "---" ]; then
    fail "$test_name"
    continue
  fi

  name=$(sed -n '2,/^---$/s/^name:[[:space:]]*//p' "$skill_file" | head -1 | tr -d '[:space:]"' | tr -d "'")
  if [ "$name" != "$dir_name" ] || ! [[ "$name" =~ $re_name ]]; then
    fail "$test_name"
    continue
  fi

  desc=$(sed -n '2,/^---$/s/^description:[[:space:]]*//p' "$skill_file" | head -1 | tr -d '[:space:]"' | tr -d "'")
  if [ -z "$desc" ]; then
    fail "$test_name"
    continue
  fi

  pass "$test_name"
done

if [ "$skills_found" -eq 0 ]; then
  fail "no skills found in skills/*/SKILL.md"
fi

# -----------------------------------------------------------------------------
# Case 8: Mode skills
# -----------------------------------------------------------------------------
mode_skills_found=0

for skill_file in skills/opus-*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  dir_name="$(basename "$(dirname "$skill_file")")"
  if [ "$dir_name" = "opus-gemini-orchestrator" ]; then
    continue
  fi
  mode_skills_found=$((mode_skills_found + 1))
  test_name="mode skill $dir_name configures exec-mode"

  if ! grep -q '~/\.claude/exec-mode' "$skill_file"; then
    fail "$test_name"
    continue
  fi

  if ! grep -qE 'echo[[:space:]]+(gemini-lite|gemini-mid|gemini-full|gemini-deepresearch|sonnet|opus)[[:space:]]*>[[:space:]]*~/\.claude/exec-mode' "$skill_file"; then
    fail "$test_name"
    continue
  fi

  pass "$test_name"
done

if [ "$mode_skills_found" -eq 0 ]; then
  fail "no mode skills found in skills/opus-*/SKILL.md"
fi

# -----------------------------------------------------------------------------
# Case 9: All files in $BIN
# -----------------------------------------------------------------------------
bin_files_found=0

for bin_file in "$BIN"/*; do
  [ -f "$bin_file" ] || continue
  bin_files_found=$((bin_files_found + 1))
  bname="$(basename "$bin_file")"
  test_name="bin file $bname shebang and syntax"

  first_line="$(head -n 1 "$bin_file")"
  if [ "$first_line" != "#!/usr/bin/env bash" ]; then
    fail "$test_name"
    continue
  fi

  if ! bash -n "$bin_file"; then
    fail "$test_name"
    continue
  fi

  pass "$test_name"
done

if [ "$bin_files_found" -eq 0 ]; then
  fail "no files found in $BIN"
fi

# -----------------------------------------------------------------------------
# Final count
# -----------------------------------------------------------------------------
echo "Total: $((passes + failures + skips)), Passed: $passes, Failed: $failures, Skipped: $skips"

if [ "$failures" -gt 0 ]; then
  exit 1
fi
exit 0
