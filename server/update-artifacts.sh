#!/usr/bin/env bash
# FXServer の artifacts を最新ビルドに入れ替える。
#
#   ./server/update-artifacts.sh
#   FXSERVER_URL=https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/XXXXX-.../fx.tar.xz ./server/update-artifacts.sh
#
# oxmysql が "server needs to be NNNNN or higher" で止まるときはこれを実行する。
set -euo pipefail

ROOT="${REDM_ROOT:-$HOME/redm}"
INDEX=https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/

say()  { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m!! %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 現在の版
if [ -d "$ROOT/artifacts" ]; then
    CUR=$(cat "$ROOT/artifacts/citizen/.version" 2>/dev/null \
          || grep -ohE '"[0-9]{4,6}"' "$ROOT/artifacts/citizen/system_resources"/*/fxmanifest.lua 2>/dev/null | head -1 \
          || true)
    echo "現在の artifacts: $ROOT/artifacts ${CUR:+(build $CUR)}"
fi

# ---------------------------------------------------------------- URL 解決
if [ -z "${FXSERVER_URL:-}" ]; then
    say "最新ビルドの URL を解決"
    # ビルド番号でソートする。'./' を外してから数値比較しないと全部 0 になる。
    FXSERVER_URL=$(curl -fsSL "$INDEX" \
        | grep -oE '[0-9]+-[0-9a-f]+/fx\.tar\.xz' \
        | sort -t- -k1,1n -u | tail -1 | sed "s|^|$INDEX|") || true
fi
[ -n "${FXSERVER_URL:-}" ] || die "URL を解決できません。
  $INDEX をブラウザで開いて一番上（最新）の fx.tar.xz の URL を控え、
  FXSERVER_URL=... を付けて再実行してください。"

BUILD=$(printf '%s' "$FXSERVER_URL" | grep -oE '/[0-9]+-[0-9a-f]+/' | tr -d '/' | cut -d- -f1)
echo "取得: $FXSERVER_URL"
[ -n "$BUILD" ] && [ "$BUILD" -lt 12913 ] 2>/dev/null \
    && die "build $BUILD は oxmysql の要求 (12913 以上) を満たしません。URL を確認してください。"

# ---------------------------------------------------------------- 入れ替え
say "ダウンロード"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fL --retry 3 -o "$TMP/fx.tar.xz" "$FXSERVER_URL"
mkdir -p "$TMP/x"
tar xf "$TMP/fx.tar.xz" -C "$TMP/x"
[ -f "$TMP/x/run.sh" ] || die "展開結果に run.sh がありません。URL が fx.tar.xz か確認してください。"

say "差し替え"
pkill -f FXServer 2>/dev/null && echo "起動中の FXServer を停止しました" || true
if [ -d "$ROOT/artifacts" ]; then
    rm -rf "$ROOT/artifacts.bak"
    mv "$ROOT/artifacts" "$ROOT/artifacts.bak"
    echo "旧 artifacts を $ROOT/artifacts.bak に退避しました"
fi
mkdir -p "$ROOT"
mv "$TMP/x" "$ROOT/artifacts"
chmod +x "$ROOT/artifacts/run.sh"

say "完了 (build ${BUILD:-不明})"
echo "起動: cd $ROOT/server-data && $ROOT/artifacts/run.sh +exec server.cfg"
