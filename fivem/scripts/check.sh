#!/usr/bin/env bash
# リポジトリ全体の静的検査。何度でも走らせる。
#
# 目で追うと必ず見落とすので、これまでに実際に踏んだ種類の欠陥を
# 機械で拾えるようにしてある。新しく踏んだら、ここに1つ足す。
#
# 使い方: fivem/scripts/check.sh [-v]

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

VERBOSE=${1:-}
FAIL=0
PASS=0

red()  { printf '\033[31m%s\033[0m' "$1"; }
grn()  { printf '\033[32m%s\033[0m' "$1"; }
ylw()  { printf '\033[33m%s\033[0m' "$1"; }

ok()   { PASS=$((PASS+1)); printf '  %s %s\n' "$(grn OK)" "$1"; }
ng()   { FAIL=$((FAIL+1)); printf '  %s %s\n' "$(red NG)" "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }
warn() { printf '  %s %s\n' "$(ylw '--')" "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

RES=fivem/resources/'[gain]'
section() { printf '\n%s\n' "$1"; }

# ---------------------------------------------------------------- 秘密情報
section "秘密情報"
hits=$(git grep -nE "license:[0-9a-f]{20,}" -- '*.lua' '*.cfg' '*.md' 2>/dev/null || true)
[ -z "$hits" ] && ok "license 識別子がコミットされていない" || ng "license 識別子がコミットされている" "$hits"

hits=$(git grep -nE "sv_licenseKey +\"[A-Za-z0-9_]{10,}" -- '*.cfg' '*.lua' 2>/dev/null || true)
[ -z "$hits" ] && ok "ライセンスキーがコミットされていない" || ng "ライセンスキーがコミットされている" "$hits"

# Config.Owners は shared_scripts に載るので、書くと全クライアントへ配信される
owners=$(grep -n "^ *Config.Owners *= *{[^}]" "$RES"/gain_core/shared/config.lua 2>/dev/null || true)
[ -z "$owners" ] && ok "Config.Owners が空（クライアントへ配信されない）" \
  || ng "Config.Owners に値が入っている。shared_scripts なので全クライアントに配信される" "$owners"

# ---------------------------------------------------------------- イベント保護
section "イベント保護"
# クライアント側の RegisterNetEvent は server→client の受信口なので正当。
# 問題になるのはサーバー側で、そこは RegisterSafeEvent を通さないと
# 送信元検証もレート制限も効かない。
raw=$(grep -rn "RegisterNetEvent(" "$RES"/*/server/*.lua 2>/dev/null \
  | grep -v "safe_event.lua" || true)
[ -z "$raw" ] && ok "サーバー側に生の RegisterNetEvent なし" \
  || ng "サーバー側に生の RegisterNetEvent がある。送信元検証もレート制限も通らない" "$raw"

# safe_event は他リソースへ個別ロードされるため gain_core のグローバルは見えない
guard=$(grep -n "^ *if GainLog then" "$RES"/gain_core/server/safe_event.lua 2>/dev/null || true)
[ -z "$guard" ] && ok "safe_event がグローバル GainLog に依存していない" \
  || ng "safe_event が GainLog を直接参照している。gain_core 以外では常に偽でログが出ない" "$guard"

# ---------------------------------------------------------------- 常時ループ
section "常時ループ"
# クライアントの描画ループは Wait(0) が要る。サーバー側にあるのが問題。
# player.lua の deferrals 直後の Wait(0) は接続処理の作法なので除く。
w0=$(grep -rn "Wait(0)" "$RES"/*/server/*.lua 2>/dev/null || true)
# deferrals の直後の Wait(0) は接続処理の作法。前後3行に deferrals があれば除く
w0=$(printf '%s' "$w0" | while IFS= read -r line; do
  [ -z "$line" ] && continue
  f=${line%%:*}; rest=${line#*:}; n=${rest%%:*}
  ctx=$(sed -n "$((n>3?n-3:1)),$((n+1))p" "$f" 2>/dev/null)
  printf '%s' "$ctx" | grep -q "deferrals" || printf '%s\n' "$line"
done)
[ -z "$w0" ] && ok "サーバー側に Wait(0) の常時ループなし" \
  || ng "サーバー側に Wait(0) がある" "$w0"

# ---------------------------------------------------------------- 金銭
section "金銭"
# 残高を直接書く SQL は台帳フラッシュ経路にだけ在ってよい
sql=$(grep -rn "gain_characters SET .*\(cash\|bank\)" "$RES" --include=*.lua 2>/dev/null || true)
n=$(printf '%s' "$sql" | grep -c . || true)
if [ "$n" -le 1 ]; then ok "残高を書く SQL が1箇所に集約されている ($n)"
else ng "残高を書く SQL が $n 箇所ある。台帳を伴わない変動が生まれる" "$sql"; fi

# AddMoney の戻り値を見ていない呼び出し
unchecked=$(grep -rn "core:AddMoney(" "$RES" --include=*.lua 2>/dev/null \
  | grep -vE "if |local |return |and |= *core:AddMoney" || true)
[ -z "$unchecked" ] && ok "AddMoney の戻り値をすべて検査している" \
  || ng "AddMoney の戻り値を見ていない箇所がある" "$unchecked"

# 上限で黙って切り詰めていないか
trunc=$(grep -n "math.min(.*MoneyLimit" "$RES"/gain_core/server/money.lua 2>/dev/null || true)
[ -z "$trunc" ] && ok "上限で黙って切り詰めていない" \
  || ng "math.min で上限に丸めている。呼び出し側が検出できない金銭消失になる" "$trunc"

# 履歴を書く SQL は台帳（ledger.lua / offline.lua）だけに在ってよい。
# 呼び出し側が個別に書くと、成否と無関係に履歴だけ残る事故が起きる
ins=$(grep -rn "INSERT INTO gain_transactions" "$RES" --include=*.lua 2>/dev/null \
  | grep -vE "gain_core/server/(ledger|offline)\.lua" || true)
[ -z "$ins" ] && ok "取引履歴を書く SQL が台帳に集約されている" \
  || ng "台帳の外で取引履歴を書いている。成否と無関係に履歴が残る" "$ins"

# ---------------------------------------------------------------- ドキュメント整合
section "ドキュメントの整合"
actual=$(ls -d "$RES"/*/ 2>/dev/null | xargs -n1 basename | sort)
for doc in CLAUDE.md fivem/docs/DEV.md fivem/server.cfg.example; do
  [ -f "$doc" ] || continue
  missing=""
  for r in $actual; do
    grep -q "$r" "$doc" || missing="$missing $r"
  done
  [ -z "$missing" ] && ok "$doc に全リソースが載っている" \
    || ng "$doc に載っていないリソース:$missing"
done

# 作り方のルール: 各リソースに README
for d in $actual; do
  [ -f "$RES/$d/README.md" ] || warn "$d に README.md が無い（DESIGN-PROCESS の規則）"
done

# ---------------------------------------------------------------- 結果
printf '\n'
if [ "$FAIL" -eq 0 ]; then
  printf '%s  合格 %d 件\n' "$(grn '検査を通過')" "$PASS"
else
  printf '%s  不合格 %d 件 / 合格 %d 件\n' "$(red '検査に失敗')" "$FAIL" "$PASS"
fi
exit $((FAIL > 0 ? 1 : 0))
