#!/usr/bin/env bash
# ローカル検証サーバーの起動・停止・ログ確認。
#
# FXServer は stdin が閉じていると即座に終了する（ログには
# "Quitting: Ctrl-C pressed in server console." と出るが、実際には
# Ctrl-C など押していない）。バックグラウンドで動かすときは stdin を
# 開いたままにする必要があるため、FIFO を噛ませている。
# この FIFO はサーバーコンソールへの入力口でもあるので、
# `dev-server.sh cmd <command>` でコンソールコマンドを流せる。
#
# 使い方:
#   dev-server.sh start          起動（バックグラウンド）
#   dev-server.sh stop           停止
#   dev-server.sh restart        再起動
#   dev-server.sh status         起動しているか
#   dev-server.sh log [n]        ログ末尾（色を落として表示）
#   dev-server.sh errors         エラーらしき行だけ
#   dev-server.sh cmd <command>  サーバーコンソールにコマンドを送る

set -uo pipefail

ROOT="${GAIN_DEV_ROOT:-/home/gain/fivem}"
RUN="$ROOT/run.sh"
STATE="${TMPDIR:-/tmp}/gain-dev-server"
FIFO="$STATE/stdin"
LOG="$STATE/server.log"
TIMEOUT="${GAIN_DEV_TIMEOUT:-3600}"

mkdir -p "$STATE"

strip_color() { sed -E 's/\x1b\[[0-9;]*m//g'; }

is_running() { pgrep -f '[F]XServer' >/dev/null 2>&1; }

start() {
    if is_running; then echo "既に起動しています"; return 0; fi
    [ -x "$RUN" ] || { echo "run.sh が見つかりません: $RUN" >&2; return 1; }

    rm -f "$FIFO"; mkfifo "$FIFO"

    # FIFO を開いたままにする書き手。これが無いと FXServer が即終了する
    ( sleep "$TIMEOUT" > "$FIFO" ) &
    local keeper=$!
    echo "$keeper" > "$STATE/keeper.pid"

    ( timeout "$TIMEOUT" "$RUN" < "$FIFO" > "$LOG" 2>&1; kill "$keeper" 2>/dev/null ) &

    for _ in $(seq 1 20); do
        if ss -tuln 2>/dev/null | grep -q ':30120'; then
            echo "起動しました (30120 待受)"; return 0
        fi
        sleep 1
    done
    echo "30120 が開きませんでした。'dev-server.sh errors' を確認してください" >&2
    return 1
}

stop() {
    pkill -f '[F]XServer' 2>/dev/null
    [ -f "$STATE/keeper.pid" ] && kill "$(cat "$STATE/keeper.pid")" 2>/dev/null
    rm -f "$FIFO" "$STATE/keeper.pid"
    echo "停止しました"
}

case "${1:-}" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; sleep 2; start ;;
    status)  is_running && echo "起動中" || echo "停止中" ;;
    log)     tail -n "${2:-40}" "$LOG" | strip_color ;;
    errors)  strip_color < "$LOG" | grep -inE 'error|failed|exception|SCRIPT ERROR|nil value|attempt to' || echo "(エラーなし)" ;;
    cmd)     shift; [ -p "$FIFO" ] || { echo "サーバーが起動していません" >&2; exit 1; }; echo "$*" > "$FIFO" ;;
    *)       sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
