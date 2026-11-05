#!/bin/bash
# Full play-test run: every sweep in turn, 4 shards each, results in $LEDGER_PT_OUT (default /tmp/claude-0/s/playtest). Then aggregate.py.
# Build first: cd native/Engine && swift build --build-tests
cd "$(dirname "$0")" || exit 1
export PATH=/opt/swift/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin:$PATH
N=${1:-4}
./run_shards.sh LedgerTests.PlaytestSweepTests/testDeterminism "$N" det
LEDGER_PLAYTEST=1 LEDGER_PT_TAG=tours "$(cd ../../.. && pwd)/.build/debug/LedgerEnginePackageTests.xctest" LedgerTests.PlaytestToursTests > "${LEDGER_PT_OUT:-/tmp/claude-0/s/playtest}/log-tours.txt" 2>&1
./run_shards.sh LedgerTests.PlaytestSweepTests/testSweepTrades "$N" trades
./run_shards.sh LedgerTests.PlaytestSweepTests/testSweepScenarios "$N" scen
./run_shards.sh LedgerTests.PlaytestSweepTests/testSweepPolicies "$N" pol
python3 -I aggregate.py "${LEDGER_PT_OUT:-/tmp/claude-0/s/playtest}"
