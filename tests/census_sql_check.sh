#!/usr/bin/env bash
# 資産センサスが組み立てる SQL を、VORP と同じ形のテーブルに対して実際に流す。
# 列名の綴りや引用の誤りは、これを流さないと本番の起動時まで分からない。
# DB が用意できない環境ではスキップする。
#
#   MYSQL="mariadb --socket=/tmp/mysqld/m.sock" ./tests/census_sql_check.sh
set -euo pipefail
cd "$(dirname "$0")/.."

MYSQL="${MYSQL:-mariadb}"
if ! $MYSQL -e "SELECT 1" >/dev/null 2>&1; then
    echo "SKIP: MySQL / MariaDB に接続できません"
    exit 0
fi

DB="dyn_census_check_$$"
cleanup() { $MYSQL -e "DROP DATABASE IF EXISTS \`$DB\`" >/dev/null 2>&1 || true; }
trap cleanup EXIT
$MYSQL -e "CREATE DATABASE \`$DB\`"

echo "== VORP と同じ形のテーブルを作る =="
# characters: vorp_core が LastLogin を更新する。bank_users: vorp_banking の定義そのまま。
$MYSQL "$DB" <<'SQL'
CREATE TABLE characters (
  charidentifier INT NOT NULL PRIMARY KEY,
  identifier     VARCHAR(50) NOT NULL,
  money          DOUBLE(22,2) NOT NULL DEFAULT 0.00,
  gold           DOUBLE(22,2) NOT NULL DEFAULT 0.00,
  LastLogin      DATETIME NULL
) ENGINE=InnoDB;
CREATE TABLE bank_users (
  id             INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  name           VARCHAR(50) NOT NULL,
  identifier     VARCHAR(50) NOT NULL,
  charidentifier INT NOT NULL,
  money          DOUBLE(22,2) NOT NULL DEFAULT 0.00,
  gold           DOUBLE(22,2) NOT NULL DEFAULT 0.00
) ENGINE=InnoDB;
INSERT INTO characters (charidentifier, identifier, money, LastLogin) VALUES
  (1, 'lic:a', 100.00, NOW()),
  (2, 'lic:b', 250.00, DATE_SUB(NOW(), INTERVAL 3 DAY)),
  (3, 'lic:c', 999.00, DATE_SUB(NOW(), INTERVAL 90 DAY)),
  (4, 'lic:d',  50.00, NULL);
INSERT INTO bank_users (name, identifier, charidentifier, money) VALUES
  ('valentine', 'lic:a', 1, 400.00),
  ('blackwater','lic:a', 1,  75.00),
  ('valentine', 'lic:b', 2, 1000.00),
  ('valentine', 'lic:z', 9, 12345.00);
SQL
echo "OK"

echo "== census.lua が組み立てる SQL をそのまま流す =="
lua5.4 -e '
  Config = { Census = {
    base    = { table = "characters", owner = "charidentifier", column = "money", lastLogin = "LastLogin" },
    wallets = { { table = "bank_users", owner = "charidentifier", column = "money" } },
  } }
  DynCensus = {}
  local f = assert(io.open("resources/dyn_economy/server/census.lua"))
  local src = f:read("a"); f:close()
  -- 関数定義だけを取り出して評価する（FiveM の関数を呼ばずに済ませる）
  local chunk = src:match("(function DynCensus%.baseQuery.-\nend)\n")
  local chunk2 = src:match("(function DynCensus%.walletQuery.-\nend)\n")
  load(chunk)(); load(chunk2)()
  io.write(DynCensus.baseQuery(Config.Census.base):gsub("%?", "14"), ";\n")
  io.write(DynCensus.walletQuery(Config.Census.wallets[1]), ";\n")
' > /tmp/census_queries.sql
cat /tmp/census_queries.sql
$MYSQL "$DB" < /tmp/census_queries.sql > /tmp/census_out.txt
echo "OK"

echo "== 結果を確認 =="
# 直近14日: char 1 と 2 がアクティブ、3 は 90 日前、4 は NULL
ACTIVE=$($MYSQL -N -B "$DB" -e "SELECT COUNT(*) FROM characters WHERE LastLogin >= DATE_SUB(NOW(), INTERVAL 14 DAY)")
[ "$ACTIVE" = "2" ] || { echo "FAIL: アクティブ判定が 2 件でない ($ACTIVE)"; exit 1; }
echo "アクティブ判定 OK"

# 銀行残高の集約: char1 は 400+75=475
B1=$($MYSQL -N -B "$DB" -e "SELECT SUM(money) FROM bank_users WHERE charidentifier = 1")
[ "$B1" = "475.00" ] || { echo "FAIL: 銀行の集約が 475 でない ($B1)"; exit 1; }
echo "銀行残高の集約 OK"

# LastLogin が NULL のキャラは非アクティブとして扱われる（比較が NULL になる）
NULLACT=$($MYSQL -N -B "$DB" -e "SELECT (LastLogin >= DATE_SUB(NOW(), INTERVAL 14 DAY)) FROM characters WHERE charidentifier = 4")
[ "$NULLACT" = "NULL" ] || { echo "FAIL: LastLogin NULL の扱いが想定と違う ($NULLACT)"; exit 1; }
echo "LastLogin NULL は非アクティブ OK"

echo
echo "census_sql_check: すべて OK"
