#!/usr/bin/env bash
#
# RedM サーバーを一から組み立てる。Ubuntu Server 24.04 で確認する想定。
#
#   ./server/setup.sh
#   FXSERVER_URL=https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/XXXX-.../fx.tar.xz ./server/setup.sh
#
# 途中で失敗したらそこで止まる。作り直すときは $ROOT を消してから再実行する。
set -euo pipefail

ROOT="${ROOT:-$HOME/redm}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
DB_NAME="${DB_NAME:-redm}"
DB_USER="${DB_USER:-redm}"

say()  { printf '\n\033[1;32m== %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m!! %s\033[0m\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------------ 事前確認
say "必要なパッケージを確認"
MISSING=()
for c in curl tar xz git; do command -v "$c" >/dev/null || MISSING+=("$c"); done
command -v mariadb >/dev/null || command -v mysql >/dev/null || MISSING+=(mariadb-server)
if [ ${#MISSING[@]} -gt 0 ]; then
    echo "不足: ${MISSING[*]}"
    echo "  sudo apt update && sudo apt install -y curl tar xz-utils git mariadb-server"
    die "パッケージを入れてから再実行してください"
fi
echo "OK"

# ------------------------------------------------------------------ artifacts
say "FXServer artifacts を取得"
mkdir -p "$ROOT/artifacts"
if [ -x "$ROOT/artifacts/run.sh" ]; then
    echo "既にあります: $ROOT/artifacts"
    echo "  入れ替えたいときは ./server/update-artifacts.sh を使ってください"
else
    if [ -z "${FXSERVER_URL:-}" ]; then
        echo "最新ビルドの URL を解決します"
        INDEX=https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/
        # 一覧ページから最新の fx.tar.xz を拾う。取れなければ手で指定してもらう。
        # ビルド番号でソートする。'./' を外してから数値比較しないと全部 0 になる。
        FXSERVER_URL=$(curl -fsSL "$INDEX" \
            | grep -oE '[0-9]+-[0-9a-f]+/fx\.tar\.xz' \
            | sort -t- -k1,1n -u | tail -1 | sed "s|^|$INDEX|") || true
    fi
    [ -n "${FXSERVER_URL:-}" ] || die "artifacts の URL を解決できません。
  https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/ を開いて
  最新の fx.tar.xz の URL を FXSERVER_URL に指定して再実行してください。"

    echo "取得: $FXSERVER_URL"
    curl -fL --retry 3 -o /tmp/fx.tar.xz "$FXSERVER_URL"
    tar xf /tmp/fx.tar.xz -C "$ROOT/artifacts"
    rm -f /tmp/fx.tar.xz
    chmod +x "$ROOT/artifacts/run.sh"
fi

# ------------------------------------------------------------------ server-data
say "server-data と標準リソースを用意"
if [ ! -d "$ROOT/server-data" ]; then
    git clone -q https://github.com/citizenfx/cfx-server-data.git "$ROOT/server-data"
else
    echo "既にあります: $ROOT/server-data"
fi
mkdir -p "$ROOT/server-data/resources/[vorp]" "$ROOT/server-data/resources/[dyn]"

# ------------------------------------------------------------------ oxmysql
say "oxmysql を取得"
OX="$ROOT/server-data/resources/oxmysql"
if [ ! -d "$OX" ]; then
    LATEST=$(curl -fsSL https://api.github.com/repos/overextended/oxmysql/releases/latest \
        | grep -oE '"browser_download_url": *"[^"]+oxmysql\.zip"' | head -1 | cut -d'"' -f4) || true
    if [ -n "${LATEST:-}" ] && command -v unzip >/dev/null; then
        curl -fL -o /tmp/oxmysql.zip "$LATEST" && unzip -q /tmp/oxmysql.zip -d "$ROOT/server-data/resources/" && rm -f /tmp/oxmysql.zip
    else
        warn "リリース版を取得できないのでソースを clone します（ビルド済みでない場合は手で用意してください）"
        git clone -q --depth 1 https://github.com/overextended/oxmysql.git "$OX"
    fi
else
    echo "既にあります"
fi

# ------------------------------------------------------------------ VORP
say "VORP のリソースを取得"
for r in vorp_lib vorp_core vorp_inventory vorp_menu vorp_character; do
    DEST="$ROOT/server-data/resources/[vorp]/$r"
    # ダウンロードが HTML（エラーページ）で落ちていることがあるので取り直す。
    if [ -d "$DEST" ] && grep -rlqI '^<!DOCTYPE\|^<html' "$DEST" --include='*.lua' 2>/dev/null; then
        warn "  $r … .lua が HTML になっています。取り直します"
        rm -rf "$DEST"
    fi
    if [ -d "$DEST" ]; then
        echo "  $r … 既にあります"
    else
        echo "  $r"
        git clone -q --depth 1 "https://github.com/VORPCORE/$r.git" "$DEST" \
            || warn "$r の取得に失敗しました。あとで手で入れてください"
    fi
done

# ------------------------------------------------------------------ dyn_*
say "動的経済のリソースを配置"
for r in dyn_economy dyn_economy_bridge dyn_shop dyn_treasury; do
    DEST="$ROOT/server-data/resources/[dyn]/$r"
    rm -rf "$DEST"
    # 開発しながら試せるようにシンボリックリンクにする。
    # 配布するときは cp -r に変える。
    ln -s "$REPO/resources/$r" "$DEST"
    echo "  $r -> $REPO/resources/$r"
done

# ------------------------------------------------------------------ データベース
say "データベースを用意"
SQL_CLIENT=$(command -v mariadb || command -v mysql)
# 既存 DB の判定は、まず DB ユーザーの認証情報で試す。
# sudo が使えない／パスワードを聞かれる環境でも通るようにするため。
if { [ -n "${DB_PASSWORD:-}" ] && "$SQL_CLIENT" -u "$DB_USER" -p"$DB_PASSWORD" -e "USE \`$DB_NAME\`"; } 2>/dev/null \
   || sudo "$SQL_CLIENT" -e "USE \`$DB_NAME\`" 2>/dev/null; then
    echo "既にあります: $DB_NAME"
    DB_PASSWORD="${DB_PASSWORD:-}"
    [ -n "$DB_PASSWORD" ] || warn "既存 DB のパスワードが分からないので server.cfg は書き換えません（DB_PASSWORD で指定できます）"
else
    DB_PASSWORD="${DB_PASSWORD:-$(head -c 18 /dev/urandom | base64 | tr -d '/+=')}"
    sudo "$SQL_CLIENT" <<SQL
CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL
    echo "作成しました: $DB_NAME / ユーザー $DB_USER"
fi

# VORP のテーブルは各リソースが起動時に作る。
# dyn_* も同様（Config.Db.autoMigrate）。ここでは何も流さない。

# ------------------------------------------------------------------ server.cfg
say "server.cfg を配置"
CFG="$ROOT/server-data/server.cfg"
if [ -f "$CFG" ]; then
    warn "既にあるので上書きしません: $CFG"
else
    cp "$REPO/server/server.cfg" "$CFG"
    if [ -n "${DB_PASSWORD:-}" ]; then
        sed -i "s|__DB_PASSWORD__|$DB_PASSWORD|" "$CFG"
    fi
    echo "配置しました: $CFG"
fi

# ------------------------------------------------------------------ 起動スクリプト
cat > "$ROOT/start.sh" <<EOF
#!/usr/bin/env bash
cd "$ROOT/server-data"
exec "$ROOT/artifacts/run.sh" +exec server.cfg
EOF
chmod +x "$ROOT/start.sh"

say "完了"

# 残っている作業だけを出す。済んだことまで並べると、
# 何が本当に残っているのか分からなくなる。
TODO=0

if grep -q '__LICENSE_KEY__' "$CFG" 2>/dev/null; then
    TODO=$((TODO+1))
    cat <<EOF

[$TODO] ライセンスキーが未設定
      https://keymaster.fivem.net で取得し、次のファイルの
      sv_licenseKey "__LICENSE_KEY__" を置き換える。これが無いと起動しない。
        $CFG
EOF
fi

if grep -q '__DB_PASSWORD__' "$CFG" 2>/dev/null; then
    TODO=$((TODO+1))
    cat <<EOF

[$TODO] データベースのパスワードが未設定
      $CFG の __DB_PASSWORD__ を置き換える。
      パスワードが分からない場合は設定し直せる:
        sudo $SQL_CLIENT -e "ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '新しいパスワード'"
EOF
fi

cat <<EOF

起動:
  $ROOT/start.sh

外から人を入れる場合はルーターで 30120 の TCP と UDP を転送する。
Cloudflare の無料プランは任意の UDP を中継しないため、ゲーム接続には
ポート転送が別途必要（SSH と txAdmin は Tunnel 経由でよい）。
同じ LAN 内や同一マシンから試すだけなら転送は要らない。

常時稼働にする場合は server/redm.service を参照。
EOF

if [ "$TODO" -eq 0 ]; then
    echo "手でやることは残っていません。"
fi
