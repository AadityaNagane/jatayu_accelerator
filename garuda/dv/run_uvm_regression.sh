#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

UVM_HOME="$(bash garuda/dv/uvm_common/resolve_uvm_home.sh)"
export UVM_HOME

RUN_DIR="${UVM_REGRESS_DIR:-build/uvm_regression}"
WAVE_ROOT="${UVM_WAVE_DIR:-waves/uvm_regression}"
UVM_VERBOSITY="${UVM_VERBOSITY:-UVM_MEDIUM}"
KEEP_WAVES="${KEEP_WAVES:-0}"
MANIFEST="${UVM_MANIFEST:-garuda/dv/uvm_manifest.csv}"
RESULT_CSV="${UVM_RESULT_CSV:-$RUN_DIR/uvm_regression_results.csv}"
RESULT_JUNIT="${UVM_JUNIT_XML:-$RUN_DIR/uvm_regression_results.xml}"

mkdir -p "$RUN_DIR" "$WAVE_ROOT"

if [[ ! -f "$MANIFEST" ]]; then
  echo "[ERROR] Manifest not found: $MANIFEST"
  exit 1
fi

TOTAL=0
PASS=0
FAIL=0
SKIP=0

declare -a RESULT_ROWS=()

to_abs_script() {
  local script_path="$1"
  if [[ "$script_path" = /* ]]; then
    echo "$script_path"
  else
    echo "$ROOT_DIR/$script_path"
  fi
}

run_one() {
  local suite="$1"
  local testname="$2"
  local script="$3"
  local priority="$4"
  local block="$5"
  local declared_status="$6"
  local log_file="$RUN_DIR/${suite}_${testname}.log"
  local wave_file="$WAVE_ROOT/${suite}_${testname}.vcd"
  local start_ms
  local end_ms
  local duration_ms
  local status="PASS"
  local reason="ok"

  TOTAL=$((TOTAL + 1))

  echo "[RUN] ${suite}/${testname} (priority=${priority}, block=${block})"
  start_ms=$(date +%s%3N)

  set +e
  TESTNAME="$testname" UVM_VERBOSITY="$UVM_VERBOSITY" DUMPFILE="$wave_file" \
    bash "$script" >"$log_file" 2>&1
  local rc=$?
  set -e
  end_ms=$(date +%s%3N)
  duration_ms=$((end_ms - start_ms))

  if [[ $rc -ne 0 ]]; then
    status="FAIL"
    reason="runner_exit_${rc}"
  else
    if grep -Eq 'UVM_FATAL\s*:\s*[1-9][0-9]*|UVM_ERROR\s*:\s*[1-9][0-9]*' "$log_file"; then
      status="FAIL"
      reason="uvm_errors"
    fi
  fi

  if [[ "$status" == "PASS" ]]; then
    PASS=$((PASS + 1))
    if [[ "$KEEP_WAVES" != "1" ]]; then
      rm -f "$wave_file"
    fi
  else
    FAIL=$((FAIL + 1))
  fi

  RESULT_ROWS+=("${suite},${testname},${status},${reason},${duration_ms},${log_file},${wave_file},${priority},${block},${declared_status}")
}

xml_escape() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  s="${s//\"/&quot;}"
  s="${s//\'/&apos;}"
  echo "$s"
}

while IFS=, read -r suite testname script enabled priority block declared_status; do
  [[ -z "${suite}" ]] && continue
  [[ "${suite:0:1}" == "#" ]] && continue

  enabled="${enabled// /}"
  if [[ "$enabled" != "1" ]]; then
    SKIP=$((SKIP + 1))
    continue
  fi

  abs_script="$(to_abs_script "$script")"
  if [[ ! -x "$abs_script" ]]; then
    echo "[WARN] Script missing or not executable for ${suite}/${testname}: $abs_script"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    RESULT_ROWS+=("${suite},${testname},FAIL,missing_script,0,${RUN_DIR}/${suite}_${testname}.log,${WAVE_ROOT}/${suite}_${testname}.vcd,${priority},${block},${declared_status}")
    continue
  fi

  run_one "$suite" "$testname" "$abs_script" "$priority" "$block" "$declared_status"
done < "$MANIFEST"

echo
echo "== UVM Regression Summary =="
printf "%-18s %-24s %-6s %-18s %-8s %-22s\n" "Suite" "Test" "Status" "Reason" "Prio" "Block"
printf "%-18s %-24s %-6s %-18s %-8s %-22s\n" "------------------" "------------------------" "------" "------------------" "--------" "----------------------"
for row in "${RESULT_ROWS[@]}"; do
  IFS=, read -r suite testname status reason _ _ _ priority block _ <<< "$row"
  printf "%-18s %-24s %-6s %-18s %-8s %-22s\n" "$suite" "$testname" "$status" "$reason" "$priority" "$block"
done
printf "\nTotals: total=%d pass=%d fail=%d skipped=%d\n" "$TOTAL" "$PASS" "$FAIL" "$SKIP"

mkdir -p "$(dirname "$RESULT_CSV")" "$(dirname "$RESULT_JUNIT")"

{
  echo "suite,test,status,reason,duration_ms,log_file,wave_file,priority,block,declared_status"
  for row in "${RESULT_ROWS[@]}"; do
    echo "$row"
  done
} > "$RESULT_CSV"

{
  echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
  echo "<testsuite name=\"garuda_uvm_regression\" tests=\"$TOTAL\" failures=\"$FAIL\">"
  for row in "${RESULT_ROWS[@]}"; do
    IFS=, read -r suite testname status reason duration_ms log_file wave_file priority block declared_status <<< "$row"
    testcase_name="${suite}.${testname}"
    testcase_time=$(awk "BEGIN { printf \"%.3f\", $duration_ms/1000.0 }")
    echo "  <testcase classname=\"$(xml_escape "$suite")\" name=\"$(xml_escape "$testcase_name")\" time=\"$testcase_time\">"
    echo "    <system-out>log=$(xml_escape "$log_file") wave=$(xml_escape "$wave_file") priority=$(xml_escape "$priority") block=$(xml_escape "$block") manifest_status=$(xml_escape "$declared_status")</system-out>"
    if [[ "$status" != "PASS" ]]; then
      echo "    <failure message=\"$(xml_escape "$reason")\">$(xml_escape "See log: $log_file")</failure>"
    fi
    echo "  </testcase>"
  done
  echo "</testsuite>"
} > "$RESULT_JUNIT"

echo
echo "Manifest: $MANIFEST"
echo "Logs directory: $RUN_DIR"
echo "Results CSV: $RESULT_CSV"
echo "JUnit XML: $RESULT_JUNIT"
if [[ "$KEEP_WAVES" == "1" ]]; then
  echo "Waves directory: $WAVE_ROOT"
fi

if [[ $FAIL -ne 0 ]]; then
  echo "[ERROR] UVM regression has failures"
  exit 1
fi

echo "[DONE] UVM regression passed"
