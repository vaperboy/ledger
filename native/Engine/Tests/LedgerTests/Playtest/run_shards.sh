#!/bin/bash
# Usage: run_shards.sh <TestClass/testMethod> [shards=4] [tag=run]
# Runs the play-test sweep in N parallel processes (each takes every Nth job). A trapped Swift runtime error kills a process, so the crashing job is
# found from progress-<tag>-<shard>.log, written up as a severity-1 finding, skipped, and the shard is restarted.
# Needs a built test bundle: cd native/Engine && swift build --build-tests
set -u
FILTER=${1:?test filter}; N=${2:-4}; TAG=${3:-run}
export PATH=/opt/swift/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin:$PATH
ENGINE=$(cd "$(dirname "$0")/../../.." && pwd)
OUT=${LEDGER_PT_OUT:-/tmp/claude-0/s/playtest}; mkdir -p "$OUT"
BIN=$ENGINE/.build/debug/LedgerEnginePackageTests.xctest
export LEDGER_PLAYTEST=1 LEDGER_PT_TAG=$TAG LEDGER_PT_OUT=$OUT
shard() {
  local i=$1 skip=$OUT/skip-$TAG-$i.txt; : > "$skip"
  while true; do
    LEDGER_PT_SHARD=$i/$N LEDGER_PT_SKIPFILE=$skip "$BIN" "$FILTER" > "$OUT/log-$TAG-$i.txt" 2>&1; rc=$?
    [ $rc -eq 0 ] && break
    local prog=$OUT/progress-$TAG-$i.log
    local last; last=$(grep -E '^(START|DONE) ' "$prog" | tail -1)
    if [[ "$last" == START* ]]; then
      local job=${last#START }
      echo "$job" >> "$skip"
      local why; why=$(grep -E "Fatal error|error:|Crash|signal" "$OUT/log-$TAG-$i.txt" | head -1 | tr '\t' ' ')
      printf '1\tcrash:%s\t1\tProcess crashed (Swift trap/signal) while playing %s: %s\t%s\t%s\t%s\n' "$job" "$job" "$why" "job $job" "see log" "" >> "$OUT/findings-$TAG-crash.tsv"
    else
      echo "shard $i failed rc=$rc without a crashing job; see $OUT/log-$TAG-$i.txt" >> "$OUT/shard-errors-$TAG.txt"; break
    fi
  done
}
for ((i=0;i<N;i++)); do shard $i & done
wait
echo finished $TAG
