#!/bin/bash
# AFLNet Live555 Fuzzing Tutorial with Coverage Measurement
# This script runs inside the AFLNet Docker container
# 
# Usage: ./aflnet_live555_tutorial.sh [duration_in_seconds]
# Example: ./aflnet_live555_tutorial.sh 300  (runs for 5 minutes)

set -e

# Configuration
FUZZ_DURATION=${1:-300}  # Default 5 minutes, or use first argument
echo "===== AFLNet Live555 Fuzzing Tutorial ====="
echo "Fuzzing duration: ${FUZZ_DURATION} seconds per experiment"
echo "This will fuzz Live555 RTSP server with and without state-aware mode"
echo ""

# Set up environment (AFLNet Docker container has these pre-configured)
export WORKDIR=${WORKDIR:-/home}
export AFLNET=${AFLNET:-/opt/aflnet}
export PATH=$PATH:$AFLNET
export AFL_PATH=$AFLNET

echo "Environment:"
echo "  WORKDIR: $WORKDIR"
echo "  AFLNET: $AFLNET"
echo ""

# Create working directory
mkdir -p $WORKDIR
cd $WORKDIR

echo "[1/7] Installing dependencies..."
apt-get update -qq
apt-get install -y wget gcovr lcov graphviz libssl-dev -qq

# Use pre-downloaded Live555 (2019.08.16 - has testOnDemandRTSPServer, works with AFLNet)
if [ ! -d "$WORKDIR/live" ]; then
  echo "ERROR: Live555 not found in $WORKDIR/live"
  echo "Please download it first:"
  echo "  cd /home"
  echo "  curl -L -o live555.tar.gz 'https://download.videolan.org/contrib/live555/live.2019.08.16.tar.gz'"
  echo "  tar -xzf live555.tar.gz"
  exit 1
fi

echo "    - Using pre-downloaded Live555 from $WORKDIR/live"
cd $WORKDIR/live

# Fix xlocale.h issue (removed in glibc 2.26+)
echo "    - Patching Live555 for modern glibc..."
sed -i 's/#include <xlocale\.h>/#include <locale.h>/g' liveMedia/include/Locale.hh 2>/dev/null || true

echo "[2/7] Compiling Live555 libraries (this takes ~2-3 minutes)..."
echo "    - Generating Makefiles for Linux..."
./genMakefiles linux
echo "    - Compiling all libraries and test programs..."
make clean all > compile.log 2>&1 && \
  echo "    ✓ Live555 compiled successfully" || \
  (echo "    ✗ Compilation failed - check /home/live/compile.log"; exit 1)

# Prepare the RTSP server for fuzzing (following AFLNet README tutorial)
cd testProgs
echo "    - Copying sample media files..."
cp $AFLNET/tutorials/live555/sample_media_sources/*.* ./

echo "[3/7] Instrumenting testOnDemandRTSPServer with AFL..."
echo "    - Compiling with afl-clang-fast++ (following AFLNet README)..."
# Following the exact compilation from AFLNet README
# Library order matters: liveMedia -> groupsock -> BasicUsageEnvironment -> UsageEnvironment
$AFLNET/afl-clang-fast++ -g -O0 -fprofile-arcs -ftest-coverage \
  -o testOnDemandRTSPServer testOnDemandRTSPServer.cpp \
  -I../UsageEnvironment/include -I../groupsock/include/ \
  -I../liveMedia/include/ -I../BasicUsageEnvironment/include/ \
  -L. ../liveMedia/libliveMedia.a ../groupsock/libgroupsock.a \
  ../BasicUsageEnvironment/libBasicUsageEnvironment.a \
  ../UsageEnvironment/libUsageEnvironment.a

if [ -f ./testOnDemandRTSPServer ]; then
  echo "    ✓ testOnDemandRTSPServer instrumented successfully"
else
  echo "    ✗ Failed to compile testOnDemandRTSPServer"
  exit 1
fi

echo ""
echo "========================================="
echo "EXPERIMENT 1: Fuzzing WITHOUT -E (no state-aware mode)"
echo "========================================="
echo ""

# Run fuzzing WITHOUT -E flag (no state-aware mode)
# IMPORTANT: AFLNet defaults to seed schedule 2 (IPSM_SCHEDULE) which requires -E
# We must use -h 1 (QUEUE_SCHEDULE) for baseline fuzzing without state-awareness
mkdir -p out-no-state
echo "[4/7] Running AFLNet without -E for ${FUZZ_DURATION} seconds..."
echo "    (Using -h 1: QUEUE_SCHEDULE for baseline fuzzing)"
timeout $FUZZ_DURATION afl-fuzz \
  -i $AFLNET/tutorials/live555/in-rtsp \
  -o out-no-state \
  -N tcp://127.0.0.1/8554 \
  -P RTSP -D 10000 -h 1 \
  ./testOnDemandRTSPServer 8554 || true

echo ""
echo "[5/7] Collecting coverage for NO-STATE mode..."
# Replay all test cases to generate coverage
find out-no-state/queue -type f -name "id:*" | while read testcase; do
  $AFLNET/aflnet-replay $testcase RTSP 8554 > /dev/null 2>&1 || true
done

# Generate coverage report
gcov testOnDemandRTSPServer.cpp > /dev/null 2>&1
lcov --capture --directory . --output-file coverage_no_state.info > /dev/null 2>&1
lcov --summary coverage_no_state.info 2>&1 | tee coverage_no_state_summary.txt

# Save results
NO_STATE_PATHS=$(find out-no-state/queue -type f -name "id:*" | wc -l)
NO_STATE_CRASHES=$(find out-no-state/replayable-crashes -type f 2>/dev/null | wc -l || echo 0)
NO_STATE_HANGS=$(find out-no-state/replayable-hangs -type f 2>/dev/null | wc -l || echo 0)

# Clean gcov data for next experiment
rm -f *.gcda

echo ""
echo "========================================="
echo "EXPERIMENT 2: Fuzzing WITH -E (state-aware mode)"
echo "========================================="
echo ""

# Run fuzzing WITH -E flag
mkdir -p out-with-state
echo "[6/7] Running AFLNet WITH -E for ${FUZZ_DURATION} seconds..."
timeout $FUZZ_DURATION afl-fuzz -d \
  -i $AFLNET/tutorials/live555/in-rtsp \
  -o out-with-state \
  -N tcp://127.0.0.1/8554 \
  -x $AFLNET/tutorials/live555/rtsp.dict \
  -P RTSP -D 10000 -q 3 -s 3 -E -K -R\
  ./testOnDemandRTSPServer 8554 || true

echo ""
echo "[7/7] Collecting coverage for WITH-STATE mode..."
# Replay all test cases to generate coverage
find out-with-state/queue -type f -name "id:*" | while read testcase; do
  $AFLNET/aflnet-replay $testcase RTSP 8554 > /dev/null 2>&1 || true
done

# Generate coverage report
gcov testOnDemandRTSPServer.cpp > /dev/null 2>&1
lcov --capture --directory . --output-file coverage_with_state.info > /dev/null 2>&1
lcov --summary coverage_with_state.info 2>&1 | tee coverage_with_state_summary.txt

# Save results
WITH_STATE_PATHS=$(find out-with-state/queue -type f -name "id:*" | wc -l)
WITH_STATE_CRASHES=$(find out-with-state/replayable-crashes -type f 2>/dev/null | wc -l || echo 0)
WITH_STATE_HANGS=$(find out-with-state/replayable-hangs -type f 2>/dev/null | wc -l || echo 0)
WITH_STATE_STATES=$(find out-with-state/queue -type f -name "id:*" -exec grep -o ",src:[^,]*,time" {} \; 2>/dev/null | cut -d: -f2 | cut -d, -f1 | sort -u | wc -l || echo 0)

echo ""
echo "========================================="
echo "   GENERATING STATE MACHINE DIAGRAM"
echo "========================================="
if [ -f out-with-state/ipsm.dot ]; then
  echo "Creating state machine visualization..."
  dot -Tpng out-with-state/ipsm.dot -o state_machine.png 2>/dev/null && \
    echo "✓ State machine diagram saved to: state_machine.png" || \
    echo "✗ Could not generate state machine image"
else
  echo "✗ State machine file not found (ipsm.dot)"
fi
echo ""

echo "========================================="
echo "           RESULTS COMPARISON"
echo "========================================="
echo ""

cat > results_comparison.txt <<EOF
AFLNet Live555 Fuzzing Results (${FUZZ_DURATION} seconds each)
================================================

WITHOUT -E (No State-Aware Mode):
----------------------------------
  Paths discovered: $NO_STATE_PATHS
  Crashes found: $NO_STATE_CRASHES
  Hangs found: $NO_STATE_HANGS
  States explored: N/A (state-aware mode disabled)

Coverage (No State-Aware):
$(cat coverage_no_state_summary.txt)

WITH -E (State-Aware Mode):
---------------------------
  Paths discovered: $WITH_STATE_PATHS
  Crashes found: $WITH_STATE_CRASHES
  Hangs found: $WITH_STATE_HANGS
  States explored: $WITH_STATE_STATES

Coverage (State-Aware):
$(cat coverage_with_state_summary.txt)

Key Observations:
-----------------
1. State-aware mode (-E) explores protocol states explicitly
2. Coverage differences show impact of state-guided fuzzing
3. Check ipsm.dot in out-with-state/ for the inferred state machine

Files Generated:
----------------
- out-no-state/: Fuzzing results without state-aware mode
- out-with-state/: Fuzzing results with state-aware mode
- coverage_*.info: Detailed coverage data (LCOV format)
- coverage_*_summary.txt: Human-readable coverage summaries
- state_machine.png: Visual representation of discovered states
- ipsm.dot: Raw state machine data (for -E mode)

To view detailed coverage:
  genhtml coverage_with_state.info -o coverage_html
  # Then open coverage_html/index.html in a browser

To replay a test case:
  ./testOnDemandRTSPServer 8554 &
  SERVER_PID=\$!
  aflnet-replay out-with-state/queue/id:000000,* RTSP 8554
  kill \$SERVER_PID
EOF

cat results_comparison.txt

echo ""
echo "========================================="
echo "         EXPERIMENT COMPLETE!"
echo "========================================="
echo ""
echo "📊 Results Summary:"
echo "   - Full report: $WORKDIR/live/testProgs/results_comparison.txt"
echo "   - State machine: $WORKDIR/live/testProgs/state_machine.png"
echo "   - Coverage data: $WORKDIR/live/testProgs/coverage_*.info"
echo ""
echo "📁 Output Directories:"
echo "   - Without -E: $WORKDIR/live/testProgs/out-no-state/"
echo "   - With -E:    $WORKDIR/live/testProgs/out-with-state/"
echo ""
echo "💡 Quick Actions:"
echo "   View state machine: xdg-open state_machine.png (or copy to host)"
echo "   List test cases:    ls out-with-state/queue/"
echo "   Check crashes:      ls out-with-state/replayable-crashes/"
echo ""
echo "========================================="

