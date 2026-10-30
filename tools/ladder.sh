#!/usr/bin/env bash
# Sequential suite ladder with the mechanical gate from docs/HANDOFF.md:
# a suite FAILS on rc != 0 OR any SCRIPT ERROR / Parse Error in its log OR a
# 150 s hang. Never run two Godot processes at once (BrowserSave race).
# Usage:
#   bash tools/ladder.sh              # full ladder (all *_test.gd + smoke)
#   bash tools/ladder.sh 'v05[0-3]'   # only suites whose filename matches the regex
#   bash tools/ladder.sh --list       # list suites without running
#   bash tools/ladder.sh --bots       # also run sim_playtest + sim_lategame (AFTER the ladder, still sequential)
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$HOME/tools/godot}"
LOGDIR="${LOGDIR:-/tmp/ladder_logs}"
mkdir -p "$LOGDIR"
FILTER=""
BOTS=0
LIST=0
for arg in "$@"; do
  case "$arg" in
    --list) LIST=1 ;;
    --bots) BOTS=1 ;;
    *) FILTER="$arg" ;;
  esac
done

SUITES=$(ls tests/*_test.gd tests/smoke.gd 2>/dev/null | sort)
if [ -n "$FILTER" ]; then
  SUITES=$(echo "$SUITES" | grep -E "$FILTER" || true)
fi

if [ "$LIST" -eq 1 ]; then
  echo "$SUITES"
  exit 0
fi

run_suite() {
  local t="$1" base log tmo
  base=$(basename "$t" .gd)
  log="$LOGDIR/$base.log"
  tmo=150
  case "$base" in sim_*) tmo=420 ;; esac
  timeout "$tmo" "$GODOT" --headless --path . --script "$t" > "$log" 2>&1
  local rc=$?
  if [ $rc -ne 0 ]; then
    echo "FAIL $base (rc=$rc)"
    return 1
  fi
  if grep -qE "SCRIPT ERROR|Parse Error" "$log"; then
    echo "FAIL $base (SCRIPT ERROR in log)"
    return 1
  fi
  if grep -q "checks=" "$log"; then
    local defined reached
    defined=$(grep -oE "^[0-9]+ checks defined" "$log" | grep -oE "^[0-9]+" | head -1)
    reached=$(grep -oE "checks=[0-9]+" "$log" | tail -1 | grep -oE "[0-9]+")
    if [ -n "$defined" ] && [ -n "$reached" ] && [ "$defined" != "$reached" ]; then
      echo "FAIL $base (defined $defined checks, ran $reached)"
      return 1
    fi
  fi
  echo "PASS $base"
  return 0
}

total=0; failed=0; failures=""
for t in $SUITES; do
  total=$((total + 1))
  if ! run_suite "$t"; then
    failed=$((failed + 1))
    failures="$failures $t"
  fi
done

if [ "$BOTS" -eq 1 ]; then
  for t in tests/sim_playtest.gd tests/sim_lategame.gd; do
    total=$((total + 1))
    if ! run_suite "$t"; then
      failed=$((failed + 1))
      failures="$failures $t"
    fi
  done
fi

echo "----------------------------------------"
if [ $failed -eq 0 ]; then
  echo "LADDER_DONE total=$total failed=0"
else
  echo "LADDER_DONE total=$total failed=$failed:$failures"
fi
exit $failed
