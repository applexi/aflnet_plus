#!/bin/bash

set -e

DURATION_MIN=${1:-5}
DURATION=$((DURATION_MIN * 60))
AFLNET=/opt/aflnet

export PATH=$PATH:$AFLNET
export AFL_PATH=$AFLNET

if [ ! -d "/home/LightFTP" ]; then
  cd /home
  apt-get update -qq && apt-get install -y git libgnutls28-dev -qq
  git clone https://github.com/hfiref0x/LightFTP.git
  cd LightFTP && git checkout 5980ea1
  patch -p1 < $AFLNET/tutorials/lightftp/5980ea1.patch
fi

cd /home/LightFTP/Source/Release
CC=$AFLNET/afl-clang-fast make clean all
cp $AFLNET/tutorials/lightftp/fftp.conf ./
cp -r $AFLNET/tutorials/lightftp/certificate ~/
mkdir -p ~/ftpshare
cp $AFLNET/tutorials/lightftp/ftpclean.sh ./
chmod +x ftpclean.sh
sed -i 's|/home/ubuntu|/root|g' fftp.conf
sed -i 's/rm /rm -f /g' ftpclean.sh

pkill -9 fftp 2>/dev/null || true
rm -rf out-*

# Create results folder
mkdir -p results
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_FILE="results/result_${TIMESTAMP}.txt"

# Function to extract a stat from fuzzer_stats file
get_stat() {
  local file="$1"
  local stat="$2"
  grep "^${stat}" "$file" 2>/dev/null | awk -F': ' '{print $2}' | tr -d ' %' || echo "0"
}

# Function to calculate percentage change
calc_pct_change() {
  local baseline="$1"
  local state="$2"
  if [ "$baseline" = "0" ] || [ -z "$baseline" ]; then
    if [ "$state" = "0" ] || [ -z "$state" ]; then
      echo "0.00"
    else
      echo "+inf"
    fi
  else
    awk "BEGIN {printf \"%.2f\", (($state - $baseline) / $baseline) * 100}"
  fi
}

echo "Run without -E"
afl-fuzz \
  -i $AFLNET/tutorials/lightftp/in-ftp -o out-baseline \
  -N tcp://127.0.0.1/2200 -P FTP -h 1 \
  -c ./ftpclean.sh ./fftp fftp.conf 2200 &>/dev/null &
AFL_PID=$!
sleep $DURATION
kill -SIGINT $AFL_PID 2>/dev/null || true
sleep 2
pkill -9 fftp 2>/dev/null || true

echo "Run with -E"
afl-fuzz \
  -i $AFLNET/tutorials/lightftp/in-ftp -o out-state \
  -N tcp://127.0.0.1/2200 -P FTP -E \
  -c ./ftpclean.sh ./fftp fftp.conf 2200 &>/dev/null &
AFL_PID=$!
sleep $DURATION
kill -SIGINT $AFL_PID 2>/dev/null || true
sleep 2
pkill -9 fftp 2>/dev/null || true

# Extract stats from fuzzer_stats files
B_STATS="out-baseline/fuzzer_stats"
S_STATS="out-state/fuzzer_stats"

B_CRASHES=$(get_stat "$B_STATS" "unique_crashes")
B_HANGS=$(get_stat "$B_STATS" "unique_hangs")
B_PATHS_TOTAL=$(get_stat "$B_STATS" "paths_total")
B_PATHS_FOUND=$(get_stat "$B_STATS" "paths_found")
B_PENDING=$(get_stat "$B_STATS" "pending_total")
B_CYCLES=$(get_stat "$B_STATS" "cycles_done")
B_BITMAP=$(get_stat "$B_STATS" "bitmap_cvg")
B_STABILITY=$(get_stat "$B_STATS" "stability")
B_RSS=$(get_stat "$B_STATS" "peak_rss_mb")
B_EXECS=$(get_stat "$B_STATS" "execs_per_sec")

S_CRASHES=$(get_stat "$S_STATS" "unique_crashes")
S_HANGS=$(get_stat "$S_STATS" "unique_hangs")
S_PATHS_TOTAL=$(get_stat "$S_STATS" "paths_total")
S_PATHS_FOUND=$(get_stat "$S_STATS" "paths_found")
S_PENDING=$(get_stat "$S_STATS" "pending_total")
S_CYCLES=$(get_stat "$S_STATS" "cycles_done")
S_BITMAP=$(get_stat "$S_STATS" "bitmap_cvg")
S_STABILITY=$(get_stat "$S_STATS" "stability")
S_RSS=$(get_stat "$S_STATS" "peak_rss_mb")
S_EXECS=$(get_stat "$S_STATS" "execs_per_sec")

PCT_CRASHES=$(calc_pct_change "$B_CRASHES" "$S_CRASHES")
PCT_HANGS=$(calc_pct_change "$B_HANGS" "$S_HANGS")
PCT_PATHS_TOTAL=$(calc_pct_change "$B_PATHS_TOTAL" "$S_PATHS_TOTAL")
PCT_PATHS_FOUND=$(calc_pct_change "$B_PATHS_FOUND" "$S_PATHS_FOUND")
PCT_PENDING=$(calc_pct_change "$B_PENDING" "$S_PENDING")
PCT_CYCLES=$(calc_pct_change "$B_CYCLES" "$S_CYCLES")
PCT_BITMAP=$(calc_pct_change "$B_BITMAP" "$S_BITMAP")
PCT_STABILITY=$(calc_pct_change "$B_STABILITY" "$S_STABILITY")
PCT_RSS=$(calc_pct_change "$B_RSS" "$S_RSS")
PCT_EXECS=$(calc_pct_change "$B_EXECS" "$S_EXECS")

cat > "$RESULTS_FILE" <<EOF
AFLNet LightFTP Fuzzing Results
Generated: $(date)
Duration: $DURATION_MIN minutes per run
===============================================

COMPARISON (State-aware w/ E vs Baseline w/out E):
-------------------------------------
$(printf "  %-16s  %12s  %12s  %12s\n" "Stat" "No State" "State" "Diff (%)")
$(printf "  %-16s  %12s  %12s  %12s\n" "────────────────" "────────────" "────────────" "────────────")
$(printf "  %-16s  %12s  %12s  %12s\n" "unique_crashes" "$B_CRASHES" "$S_CRASHES" "${PCT_CRASHES}%")
$(printf "  %-16s  %12s  %12s  %12s\n" "unique_hangs" "$B_HANGS" "$S_HANGS" "${PCT_HANGS}%")
$(printf "  %-16s  %12s  %12s  %12s\n" "paths_total" "$B_PATHS_TOTAL" "$S_PATHS_TOTAL" "${PCT_PATHS_TOTAL}%")
$(printf "  %-16s  %12s  %12s  %12s\n" "paths_found" "$B_PATHS_FOUND" "$S_PATHS_FOUND" "${PCT_PATHS_FOUND}%")
$(printf "  %-16s  %12s  %12s  %12s\n" "pending_total" "$B_PENDING" "$S_PENDING" "${PCT_PENDING}%")
$(printf "  %-16s  %12s  %12s  %12s\n" "cycles_done" "$B_CYCLES" "$S_CYCLES" "${PCT_CYCLES}%")
$(printf "  %-16s  %12s  %12s  %12s\n" "bitmap_cvg" "${B_BITMAP}%" "${S_BITMAP}%" "${PCT_BITMAP}%")
$(printf "  %-16s  %12s  %12s  %12s\n" "stability" "${B_STABILITY}%" "${S_STABILITY}%" "${PCT_STABILITY}%")
$(printf "  %-16s  %12s  %12s  %12s\n" "peak_rss_mb" "$B_RSS" "$S_RSS" "${PCT_RSS}%")
$(printf "  %-16s  %12s  %12s  %12s\n" "execs_per_sec" "$B_EXECS" "$S_EXECS" "${PCT_EXECS}%")

Note: Positive % = State performed better
      Negative % = No State performed better
EOF

echo ""
echo "Results saved to: $RESULTS_FILE"
echo ""
cat "$RESULTS_FILE"
