#!/usr/bin/env bash
# schema.sql を実際の MariaDB / MySQL に流して検証する。
# 起動時の自動マイグレーションと同じ経路（コメント除去 → ';' 分割 → 1 文ずつ実行）も再現する。
# DB が用意できない環境ではスキップする。
#
#   ./tests/schema_check.sh
#   MYSQL="mariadb --socket=/tmp/mysqld/m.sock" ./tests/schema_check.sh
set -euo pipefail
cd "$(dirname "$0")/.."

MYSQL="${MYSQL:-mariadb}"
if ! $MYSQL -e "SELECT 1" >/dev/null 2>&1; then
    echo "SKIP: MySQL / MariaDB に接続できません（\$MYSQL で接続方法を指定できます）"
    exit 0
fi

DB="dyn_schema_check_$$"
cleanup() { $MYSQL -e "DROP DATABASE IF EXISTS \`$DB\`" >/dev/null 2>&1 || true; }
trap cleanup EXIT

SCHEMA=resources/dyn_economy/sql/schema.sql

echo "== 1. ファイルをそのまま流す =="
$MYSQL -e "CREATE DATABASE \`$DB\`"
$MYSQL "$DB" < "$SCHEMA"
echo "OK"

echo "== 2. 同じファイルをもう一度流す（冪等性） =="
$MYSQL "$DB" < "$SCHEMA"
echo "OK"

echo "== 3. 起動時マイグレーションと同じ分割で 1 文ずつ流す =="
$MYSQL -e "DROP DATABASE \`$DB\`; CREATE DATABASE \`$DB\`"
lua5.4 -e '
  MySQL = nil
  dofile("resources/dyn_economy/server/db.lua")
  local f = assert(io.open("resources/dyn_economy/sql/schema.sql"))
  local raw = f:read("a"); f:close()
  for _, s in ipairs(DynDb.splitStatements(raw)) do io.write(s, ";\n") end
' | $MYSQL "$DB"
echo "OK"

echo "== 4. テーブルと主要な列を確認 =="
EXPECTED="dyn_econ_config dyn_item_state dyn_items dyn_npc_tx dyn_price_history dyn_recipe_inputs dyn_recipes"
ACTUAL=$($MYSQL -N -B "$DB" -e "SHOW TABLES" | sort | tr '\n' ' ' | sed 's/ $//')
if [ "$ACTUAL" != "$(echo $EXPECTED)" ]; then
    echo "FAIL: テーブルが一致しません"
    echo "  期待: $EXPECTED"
    echo "  実際: $ACTUAL"
    exit 1
fi
echo "テーブル 7 件 OK"

for col in "dyn_npc_tx price_breakdown" "dyn_npc_tx voided" "dyn_items price_index" \
           "dyn_items pinned" "dyn_item_state mat_cost"; do
    set -- $col
    if ! $MYSQL -N -B "$DB" -e "SHOW COLUMNS FROM \`$1\` LIKE '$2'" | grep -q "$2"; then
        echo "FAIL: $1.$2 がありません"; exit 1
    fi
done
echo "主要な列 OK"

echo "== 5. 外部キーが効くか =="
if $MYSQL "$DB" -e "INSERT INTO dyn_recipe_inputs (recipe_id, item, qty) VALUES (999, 'x', 1)" 2>/dev/null; then
    echo "FAIL: 存在しない recipe_id を受け付けてしまいました"; exit 1
fi
echo "dyn_recipe_inputs の外部キー OK"

echo
echo "schema_check: すべて OK"
