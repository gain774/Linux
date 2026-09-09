#!/usr/bin/env bash
# dyn_economy のテスト一式。FiveM を起動せず素の Lua で走る。
#   ./tests/run_all.sh
set -euo pipefail
cd "$(dirname "$0")/.."

LUA="${LUA:-lua5.4}"
command -v "$LUA" >/dev/null || { echo "Lua が見つかりません (apt install lua5.4)"; exit 1; }

echo "== 構文チェック =="
n=0
for f in $(find resources tests -name '*.lua'); do
  "$LUA" -e "assert(loadfile('$f'))"
  n=$((n+1))
done
echo "$n ファイル OK"
echo

echo "== 単体テスト（純粋関数） =="
"$LUA" tests/run.lua
echo

echo "== 結合テスト（価格スタック） =="
"$LUA" tests/integration.lua
echo

echo "== 決済フロー（ブリッジ） =="
"$LUA" tests/bridge.lua
