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

echo "== fxmanifest の取りこぼし =="
"$LUA" tests/manifest.lua
echo

echo "== 単体テスト（純粋関数） =="
"$LUA" tests/run.lua
echo

echo "== 結合テスト（価格スタック） =="
"$LUA" tests/integration.lua
echo

echo "== 決済フロー（ブリッジ） =="
"$LUA" tests/bridge.lua
echo

echo "== 他リソースとの互換 =="
"$LUA" tests/compat.lua
echo

echo "== 店舗の検証 =="
"$LUA" tests/shop.lua
echo

echo "== レシピ取り込み =="
"$LUA" tests/recipes_import.lua
echo

echo "== 資産センサスの統計 =="
"$LUA" tests/census.lua
echo

echo "== 国庫の記帳 =="
"$LUA" tests/treasury.lua
echo

echo "== SQL マイグレーションの分割 =="
"$LUA" tests/schema.lua
echo

echo "== スキーマの実機検証（DB があれば） =="
./tests/schema_check.sh
echo

echo "== センサスの SQL 実機検証（DB があれば） =="
./tests/census_sql_check.sh
