#!/usr/bin/env bash
set -euo pipefail

# Run from repo root. BIN=skills/opus-gemini-orchestrator/bin.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO_ROOT"

BIN="skills/opus-gemini-orchestrator/bin"
BIN_ABS="$REPO_ROOT/$BIN"

chmod +x "$BIN_ABS/gmap" 2>/dev/null || true

# Temp dirs (mktemp -d, trap cleanup) and a fake HOME
TMP_DIR="$(mktemp -d)"
FAKE_HOME="$(mktemp -d)"
STUB_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR" "$FAKE_HOME" "$STUB_DIR"
}
trap cleanup EXIT INT TERM

# Default agy stub in STUB_DIR
cat <<'EOF' > "$STUB_DIR/agy"
#!/usr/bin/env bash
echo "agy stub called" >&2
exit 1
EOF
chmod +x "$STUB_DIR/agy"
export PATH="$STUB_DIR:$PATH"

passes=0
failures=0

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

# -----------------------------------------------------------------------------
# Case 1: Empty or missing status dir
# -----------------------------------------------------------------------------
test_name="gmap empty or missing status dir prints no workers"
MISSING_DIR="$TMP_DIR/missing_status"
EMPTY_DIR="$TMP_DIR/empty_status"
mkdir -p "$EMPTY_DIR"

set +e
out_missing=$(GDO_STATUS_DIR="$MISSING_DIR" "$BIN/gmap" -1 2>&1)
rc_missing=$?
out_empty=$(GDO_STATUS_DIR="$EMPTY_DIR" "$BIN/gmap" -1 2>&1)
rc_empty=$?
set -e

if [ $rc_missing -eq 0 ] && [[ "$out_missing" == *"no workers"* ]] && \
   [ $rc_empty -eq 0 ] && [[ "$out_empty" == *"no workers"* ]]; then
  pass "$test_name"
else
  fail "$test_name"
fi

# -----------------------------------------------------------------------------
# Case 2: Three hand-written status rows
# -----------------------------------------------------------------------------
test_name="gmap three status rows render right markers and header counts"
CASE2_DIR="$TMP_DIR/case2_status"
mkdir -p "$CASE2_DIR"
now=$(date +%s)
cat <<EOF > "$CASE2_DIR/worker-run.status"
worker-run|implement|running|$((now - 10))|$now|100|0|conv-1
EOF
cat <<EOF > "$CASE2_DIR/worker-pass.status"
worker-pass|review|pass|$((now - 50))|$now|200|0|conv-2
EOF
cat <<EOF > "$CASE2_DIR/worker-fail.status"
worker-fail|fix 1|fail|$((now - 30))|$now|300|0|conv-3
EOF

set +e
out=$(NO_COLOR=1 GDO_STATUS_DIR="$CASE2_DIR" "$BIN/gmap" -1 2>&1)
rc=$?
set -e

if [ $rc -eq 0 ] && \
   [[ "$out" == *"1 running · 2 done"* ]] && \
   echo "$out" | grep -q "● worker-run" && \
   echo "$out" | grep -q "○ worker-pass" && \
   echo "$out" | grep -q "✗ worker-fail"; then
  pass "$test_name"
else
  fail "$test_name"
fi

# -----------------------------------------------------------------------------
# Case 3: Rows ordered by start_epoch ascending
# -----------------------------------------------------------------------------
test_name="gmap rows ordered by start_epoch ascending"
CASE3_DIR="$TMP_DIR/case3_status"
mkdir -p "$CASE3_DIR"
now=$(date +%s)
cat <<EOF > "$CASE3_DIR/w_mid.status"
worker-mid|call|pass|1000|$now|100|0|c2
EOF
cat <<EOF > "$CASE3_DIR/w_early.status"
worker-early|call|pass|500|$now|100|0|c1
EOF
cat <<EOF > "$CASE3_DIR/w_late.status"
worker-late|call|pass|1500|$now|100|0|c3
EOF

set +e
out=$(NO_COLOR=1 GDO_STATUS_DIR="$CASE3_DIR" "$BIN/gmap" -1 2>&1)
rc=$?
set -e

early_line=$(echo "$out" | grep -n "worker-early" | cut -d: -f1 || true)
mid_line=$(echo "$out" | grep -n "worker-mid" | cut -d: -f1 || true)
late_line=$(echo "$out" | grep -n "worker-late" | cut -d: -f1 || true)

if [ $rc -eq 0 ] && [ -n "$early_line" ] && [ -n "$mid_line" ] && [ -n "$late_line" ] && \
   [ "$early_line" -lt "$mid_line" ] && [ "$mid_line" -lt "$late_line" ]; then
  pass "$test_name"
else
  fail "$test_name"
fi

# -----------------------------------------------------------------------------
# Case 4: Running row with update_epoch 700s old shows stale
# -----------------------------------------------------------------------------
test_name="gmap stale running row shows stale and not counted as running"
CASE4_DIR="$TMP_DIR/case4_status"
mkdir -p "$CASE4_DIR"
now=$(date +%s)
cat <<EOF > "$CASE4_DIR/worker-stale.status"
worker-stale|implement|running|$((now - 800))|$((now - 700))|100|0|conv-stale
EOF

set +e
out=$(NO_COLOR=1 GDO_STATUS_DIR="$CASE4_DIR" "$BIN/gmap" -1 2>&1)
rc=$?
set -e

if [ $rc -eq 0 ] && \
   [[ "$out" == *"stale"* ]] && \
   ! [[ "$out" == *"1 running"* ]]; then
  pass "$test_name"
else
  fail "$test_name"
fi

# -----------------------------------------------------------------------------
# Case 5: Malformed rows ignored
# -----------------------------------------------------------------------------
test_name="gmap malformed rows ignored exit 0"
CASE5_DIR="$TMP_DIR/case5_status"
mkdir -p "$CASE5_DIR"
now=$(date +%s)
cat <<EOF > "$CASE5_DIR/valid.status"
worker-valid|call|pass|$((now - 10))|$now|50|0|c1
EOF
cat <<EOF > "$CASE5_DIR/bad_fields.status"
worker-bad1|implement|running|1000|1010
EOF
cat <<EOF > "$CASE5_DIR/bad_start.status"
worker-bad2|implement|running|not_a_number|1010|0|0|c2
EOF
cat <<EOF > "$CASE5_DIR/bad_update.status"
worker-bad3|implement|running|1000|not_a_number|0|0|c3
EOF
cat <<EOF > "$CASE5_DIR/bad_state.status"
worker-bad4|implement|unknown_state|1000|1010|0|0|c4
EOF

set +e
out=$(NO_COLOR=1 GDO_STATUS_DIR="$CASE5_DIR" "$BIN/gmap" -1 2>&1)
rc=$?
set -e

if [ $rc -eq 0 ] && \
   [[ "$out" == *"worker-valid"* ]] && \
   ! [[ "$out" == *"worker-bad1"* ]] && \
   ! [[ "$out" == *"worker-bad2"* ]] && \
   ! [[ "$out" == *"worker-bad3"* ]] && \
   ! [[ "$out" == *"worker-bad4"* ]] && \
   [[ "$out" == *"1 workers"* ]]; then
  pass "$test_name"
else
  fail "$test_name"
fi

# -----------------------------------------------------------------------------
# Case 6: Token formatting and sum
# -----------------------------------------------------------------------------
test_name="gmap token formatting and footer total"
CASE6_DIR="$TMP_DIR/case6_status"
mkdir -p "$CASE6_DIR"
now=$(date +%s)
cat <<EOF > "$CASE6_DIR/w1.status"
worker-one|call|pass|$((now - 20))|$now|1500|0|c1
EOF
cat <<EOF > "$CASE6_DIR/w2.status"
worker-two|call|pass|$((now - 10))|$now|340|0|c2
EOF

set +e
out=$(NO_COLOR=1 GDO_STATUS_DIR="$CASE6_DIR" "$BIN/gmap" -1 2>&1)
rc=$?
set -e

if [ $rc -eq 0 ] && \
   echo "$out" | grep "worker-one" | grep -q "1.5k tok" && \
   echo "$out" | grep "worker-two" | grep -q "340 tok" && \
   echo "$out" | grep -q "total 1.8k tok · 2 workers"; then
  pass "$test_name"
else
  fail "$test_name"
fi

# -----------------------------------------------------------------------------
# Case 7: Help and unknown option
# -----------------------------------------------------------------------------
test_name="gmap help exits 0 and unknown flag exits 1"
set +e
out_h=$("$BIN/gmap" -h 2>&1)
rc_h=$?
out_bad=$("$BIN/gmap" --invalid-flag 2>&1)
rc_bad=$?
set -e

if [ $rc_h -eq 0 ] && [[ "$out_h" == *"Usage:"* ]] && \
   [ $rc_bad -eq 1 ] && [[ "$out_bad" == *"unknown option"* ]]; then
  pass "$test_name"
else
  fail "$test_name"
fi

# -----------------------------------------------------------------------------
# Case 8: gdo writes status file
# -----------------------------------------------------------------------------
test_name="gdo writes status file with state=pass and tokens"
CASE8_DIR="$TMP_DIR/case8_status"
mkdir -p "$CASE8_DIR"

cat <<'EOF' > "$STUB_DIR/agy"
#!/usr/bin/env bash
cat <<'JSON'
{
  "status": "SUCCESS",
  "response": "all done",
  "conversation_id": "test-conv-case8",
  "usage": {
    "total_tokens": 1234
  }
}
JSON
exit 0
EOF
chmod +x "$STUB_DIR/agy"

set +e
gdo_out=$(HOME="$FAKE_HOME" GDO_STATUS_DIR="$CASE8_DIR" GDO_TITLE="task_case8" "$BIN/gdo" "run something" 2>&1)
gdo_rc=$?
set -e

status_file="$CASE8_DIR/task_case8.status"
if [ $gdo_rc -eq 0 ] && [ -f "$status_file" ]; then
  content="$(head -n 1 "$status_file")"
  field_count=$(awk -F'|' '{print NF}' <<< "$content")
  state_field=$(awk -F'|' '{print $3}' <<< "$content")
  token_field=$(awk -F'|' '{print $6}' <<< "$content")
  conv_field=$(awk -F'|' '{print $8}' <<< "$content")
  if [ "$field_count" -eq 8 ] && [ "$state_field" = "pass" ] && [ "$token_field" = "1234" ] && [ "$conv_field" = "test-conv-case8" ]; then
    pass "$test_name"
  else
    fail "$test_name"
  fi
else
  fail "$test_name"
fi

# -----------------------------------------------------------------------------
# Case 9: GDO_STATUS_DIR='' disables status writing
# -----------------------------------------------------------------------------
test_name="gdo with empty GDO_STATUS_DIR writes no status file"
CASE9_DIR="$TMP_DIR/case9_status"
mkdir -p "$CASE9_DIR"

set +e
gdo_out=$(HOME="$FAKE_HOME" GDO_STATUS_DIR='' GDO_TITLE="task_case9" "$BIN/gdo" "run something" 2>&1)
gdo_rc=$?
set -e

shopt -s nullglob
files_case9=("$CASE9_DIR"/*.status "$FAKE_HOME/.cache/gdo/status"/*.status)
shopt -u nullglob

if [ $gdo_rc -eq 0 ] && [ ${#files_case9[@]} -eq 0 ]; then
  pass "$test_name"
else
  fail "$test_name"
fi

# -----------------------------------------------------------------------------
# Case 10: Status file older than 86400s pruned on next gdo run
# -----------------------------------------------------------------------------
test_name="gdo prunes status files older than 86400 seconds"
CASE10_DIR="$TMP_DIR/case10_status"
mkdir -p "$CASE10_DIR"
now=$(date +%s)
old_epoch=$((now - 90000))
cat <<EOF > "$CASE10_DIR/old_worker.status"
old_worker|call|pass|$((old_epoch - 100))|$old_epoch|50|0|c_old
EOF
recent_epoch=$((now - 1000))
cat <<EOF > "$CASE10_DIR/recent_worker.status"
recent_worker|call|pass|$((recent_epoch - 100))|$recent_epoch|50|0|c_recent
EOF

set +e
gdo_out=$(HOME="$FAKE_HOME" GDO_STATUS_DIR="$CASE10_DIR" GDO_TITLE="new_task_case10" "$BIN/gdo" "run something" 2>&1)
gdo_rc=$?
set -e

if [ $gdo_rc -eq 0 ] && \
   [ ! -f "$CASE10_DIR/old_worker.status" ] && \
   [ -f "$CASE10_DIR/recent_worker.status" ] && \
   [ -f "$CASE10_DIR/new_task_case10.status" ]; then
  pass "$test_name"
else
  fail "$test_name"
fi

# -----------------------------------------------------------------------------
# Final count
# -----------------------------------------------------------------------------
echo "Total: $((passes + failures)), Passed: $passes, Failed: $failures"

if [ "$failures" -gt 0 ]; then
  exit 1
fi
exit 0
