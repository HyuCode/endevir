#!/usr/bin/env bash
# ソークテスト: exampleスイートをN回連続実行してフレーク率を計測する（NFR-101）。
# 使い方: scripts/soak.sh <iterations> <platform> <device>
# 環境変数 DART でdartコマンドを上書きできる（例: DART="fvm dart"）
set -u
ITERATIONS=$1
PLATFORM=$2
DEVICE=$3
DART_CMD=${DART:-dart}

cd "$(dirname "$0")/../examples/flutter_app"

pass=0
fail=0
start=$(date +%s)
for i in $(seq 1 "$ITERATIONS"); do
  log=$(mktemp)
  if $DART_CMD run endevir_cli:endevir_cli test -p "$PLATFORM" -d "$DEVICE" > "$log" 2>&1; then
    pass=$((pass + 1))
    echo "run $i/$ITERATIONS: PASS ($(grep -o 'tests: .*' "$log" | head -1))"
  else
    fail=$((fail + 1))
    echo "run $i/$ITERATIONS: FAIL"
    tail -8 "$log"
  fi
  rm -f "$log"
done
elapsed=$(( $(date +%s) - start ))

echo ""
echo "SOAK RESULT: $pass/$ITERATIONS passed, $fail failed (${elapsed}s total)"
if [ "$ITERATIONS" -gt 0 ]; then
  echo "SOAK FLAKE RATE: $(awk "BEGIN {printf \"%.1f\", $fail * 100 / $ITERATIONS}")%"
fi
[ "$fail" -eq 0 ]
