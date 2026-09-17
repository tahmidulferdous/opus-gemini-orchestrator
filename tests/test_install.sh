#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f "skills/opus-gemini-orchestrator/scripts/install.sh" ]]; then
  echo "Error: test_install.sh must be run from repository root" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq must be installed and available in PATH" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "Error: git must be installed and available in PATH" >&2
  exit 1
fi

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

# Stubs for agy, sqlite3, python3 that exit 0
mkdir -p "$tmp_root/stubs"
for stub in agy sqlite3 python3; do
  cat << 'EOF' > "$tmp_root/stubs/$stub"
#!/bin/sh
exit 0
EOF
  chmod +x "$tmp_root/stubs/$stub"
done
export PATH="$tmp_root/stubs:$PATH"

passed=0
failed=0

check() {
  local name="$1"
  shift
  if "$@"; then
    echo "PASS - $name"
    passed=$((passed + 1))
  else
    echo "FAIL - $name"
    failed=$((failed + 1))
  fi
}

# Case 1: Fresh install exits 0
tmp1="$tmp_root/home1"
mkdir -p "$tmp1"

test_case_1() {
  HOME="$tmp1" bash skills/opus-gemini-orchestrator/scripts/install.sh >/dev/null
}
check "1. Fresh install exits 0" test_case_1

# Case 2: $tmp/.local/bin/gdo, gtask, gresearch are symlinks resolving to files in repo bin
test_case_2() {
  local repo_bin
  repo_bin="$(cd skills/opus-gemini-orchestrator/bin && pwd -P)"
  for b in gdo gtask gresearch; do
    local f="$tmp1/.local/bin/$b"
    if [[ ! -L "$f" ]]; then
      return 1
    fi
    local resolved
    resolved="$(readlink -f "$f")"
    if [[ "$resolved" != "$repo_bin/$b" ]]; then
      return 1
    fi
    if [[ ! -f "$resolved" ]]; then
      return 1
    fi
  done
  return 0
}
check "2. \$tmp/.local/bin/gdo, gtask, gresearch are symlinks resolving to files in the repo's bin" test_case_2

# Case 3: $tmp/.claude/skills/opus-gemini-full and opus-gemini-orchestrator exist
test_case_3() {
  [[ -e "$tmp1/.claude/skills/opus-gemini-full" ]] || return 1
  [[ -e "$tmp1/.claude/skills/opus-gemini-orchestrator" ]] || return 1
}
check "3. \$tmp/.claude/skills/opus-gemini-full and opus-gemini-orchestrator exist" test_case_3

# Case 4: settings.json has exactly one hook command containing exec-mode-hook.sh (count with jq)
test_case_4() {
  local count
  count="$(jq '[.. | .command? // empty | select(type == "string" and contains("exec-mode-hook.sh"))] | length' "$tmp1/.claude/settings.json")"
  [[ "$count" -eq 1 ]]
}
check "4. settings.json has exactly one hook command containing exec-mode-hook.sh (count with jq)" test_case_4

# Case 5: exec-mode contains gemini-full
test_case_5() {
  local mode
  mode="$(cat "$tmp1/.claude/exec-mode" | tr -d '[:space:]')"
  [[ "$mode" == "gemini-full" ]]
}
check "5. exec-mode contains gemini-full" test_case_5

# Case 6: Second install exits 0 and the hook count is still 1
test_case_6() {
  HOME="$tmp1" bash skills/opus-gemini-orchestrator/scripts/install.sh >/dev/null || return 1
  local count
  count="$(jq '[.. | .command? // empty | select(type == "string" and contains("exec-mode-hook.sh"))] | length' "$tmp1/.claude/settings.json")"
  [[ "$count" -eq 1 ]]
}
check "6. Second install exits 0 and the hook count is still 1" test_case_6

# Case 7: Existing settings keys survive: pre-create settings.json in a new temp HOME, install,
# assert .model == "opus" and /x/other.sh is still present and hook count is 1
tmp2="$tmp_root/home2"
mkdir -p "$tmp2/.claude"
cat << 'EOF' > "$tmp2/.claude/settings.json"
{"model":"opus","hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"/x/other.sh"}]}]}}
EOF

test_case_7() {
  HOME="$tmp2" bash skills/opus-gemini-orchestrator/scripts/install.sh >/dev/null || return 1
  local model
  model="$(jq -r '.model // empty' "$tmp2/.claude/settings.json")"
  [[ "$model" == "opus" ]] || return 1
  local has_other
  has_other="$(jq '[.. | .command? // empty | select(. == "/x/other.sh")] | length' "$tmp2/.claude/settings.json")"
  [[ "$has_other" -eq 1 ]] || return 1
  local count
  count="$(jq '[.. | .command? // empty | select(type == "string" and contains("exec-mode-hook.sh"))] | length' "$tmp2/.claude/settings.json")"
  [[ "$count" -eq 1 ]]
}
check "7. Existing settings keys survive: .model == opus, /x/other.sh present, hook count 1" test_case_7

# Case 8: A backup file settings.json.bak-* was created in case 7
test_case_8() {
  local bak_count
  bak_count="$(find "$tmp2/.claude" -maxdepth 1 -name "settings.json.bak-*" | wc -l)"
  [[ "$bak_count" -ge 1 ]]
}
check "8. A backup file settings.json.bak-* was created in case 7" test_case_8

# Case 9: --agy-permissions creates the agy settings with "read_url(*)" and "command(rm)" in deny;
# running it twice leaves "command(git)" exactly once in allow
tmp3="$tmp_root/home3"
mkdir -p "$tmp3"

test_case_9() {
  HOME="$tmp3" bash skills/opus-gemini-orchestrator/scripts/install.sh --agy-permissions >/dev/null || return 1
  local agy_settings="$tmp3/.gemini/antigravity-cli/settings.json"
  [[ -f "$agy_settings" ]] || return 1
  local has_read_url
  has_read_url="$(jq '[.permissions.allow[]? | select(. == "read_url(*)")] | length' "$agy_settings")"
  [[ "$has_read_url" -eq 1 ]] || return 1
  local has_rm_deny
  has_rm_deny="$(jq '[.permissions.deny[]? | select(. == "command(rm)")] | length' "$agy_settings")"
  [[ "$has_rm_deny" -eq 1 ]] || return 1

  # Run second time
  HOME="$tmp3" bash skills/opus-gemini-orchestrator/scripts/install.sh --agy-permissions >/dev/null || return 1
  local git_count
  git_count="$(jq '[.permissions.allow[]? | select(. == "command(git)")] | length' "$agy_settings")"
  [[ "$git_count" -eq 1 ]]
}
check "9. --agy-permissions creates agy settings with read_url(*) and command(rm) in deny; deduplicated" test_case_9

# Case 10: Existing exec-mode is not overwritten (pre-write gemini-mid, install, still gemini-mid)
tmp4="$tmp_root/home4"
mkdir -p "$tmp4/.claude"
echo "gemini-mid" > "$tmp4/.claude/exec-mode"

test_case_10() {
  HOME="$tmp4" bash skills/opus-gemini-orchestrator/scripts/install.sh >/dev/null || return 1
  local mode
  mode="$(cat "$tmp4/.claude/exec-mode" | tr -d '[:space:]')"
  [[ "$mode" == "gemini-mid" ]]
}
check "10. Existing exec-mode is not overwritten (still gemini-mid)" test_case_10

# Case 11: --uninstall exits 0, removes the three bin symlinks, and leaves hook count 0 while /x/other.sh (case 7 HOME) is still present
test_case_11() {
  HOME="$tmp2" bash skills/opus-gemini-orchestrator/scripts/install.sh --uninstall >/dev/null || return 1
  for b in gdo gtask gresearch; do
    if [[ -e "$tmp2/.local/bin/$b" || -L "$tmp2/.local/bin/$b" ]]; then
      return 1
    fi
  done
  local count
  count="$(jq '[.. | .command? // empty | select(type == "string" and contains("exec-mode-hook.sh"))] | length' "$tmp2/.claude/settings.json")"
  [[ "$count" -eq 0 ]] || return 1
  local has_other
  has_other="$(jq '[.. | .command? // empty | select(. == "/x/other.sh")] | length' "$tmp2/.claude/settings.json")"
  [[ "$has_other" -eq 1 ]]
}
check "11. --uninstall exits 0, removes 3 bin symlinks, leaves hook count 0 while /x/other.sh is present" test_case_11

# Case 12: Shared folder handling: unrelated sibling skills are not linked and not deleted on uninstall
tmp5="$tmp_root/home5"
mkdir -p "$tmp5/.claude/skills"
repo_copy="$tmp_root/repo_copy"
mkdir -p "$repo_copy"
cp -r skills "$repo_copy/skills"
mkdir -p "$repo_copy/skills/zz-unrelated-test-skill"
echo "# Sibling Test Skill" > "$repo_copy/skills/zz-unrelated-test-skill/SKILL.md"
mkdir -p "$repo_copy/skills/other-unrelated-skill"
echo "# Other Unrelated Skill" > "$repo_copy/skills/other-unrelated-skill/SKILL.md"

ln -s "$repo_copy/skills/zz-unrelated-test-skill" "$tmp5/.claude/skills/zz-unrelated-test-skill"

test_case_12() {
  HOME="$tmp5" bash "$repo_copy/skills/opus-gemini-orchestrator/scripts/install.sh" >/dev/null || return 1
  # Assert install does not create links for other unrelated names
  if [[ -e "$tmp5/.claude/skills/other-unrelated-skill" || -L "$tmp5/.claude/skills/other-unrelated-skill" ]]; then
    return 1
  fi
  # Assert pack skills were installed
  if [[ ! -e "$tmp5/.claude/skills/opus-gemini-orchestrator" ]]; then
    return 1
  fi
  # Run uninstall
  HOME="$tmp5" bash "$repo_copy/skills/opus-gemini-orchestrator/scripts/install.sh" --uninstall >/dev/null || return 1
  # Assert --uninstall leaves the zz-unrelated-test-skill symlink in place
  if [[ ! -L "$tmp5/.claude/skills/zz-unrelated-test-skill" ]]; then
    return 1
  fi
  # Assert pack skills were removed
  if [[ -e "$tmp5/.claude/skills/opus-gemini-orchestrator" || -L "$tmp5/.claude/skills/opus-gemini-orchestrator" ]]; then
    return 1
  fi
  return 0
}
check "12. Shared folder handling: unrelated skills are not linked and not removed on uninstall" test_case_12

echo "$passed passed, $failed failed"
if [[ $failed -gt 0 ]]; then
  exit 1
fi
