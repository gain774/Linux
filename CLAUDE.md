# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## このリポジトリの二重性

1つのリポジトリに、性格の違う2つのものが入っている。混同しないこと。

- **`README.md` / `runbook.html`** — Dell Latitude 5320 を Ubuntu Server 化して FiveM と
  Claude Code を同居させるまでの作業記録と手順書（Phase 0〜11）。コードではなく運用文書
- **`fivem/`** — 自作 FiveM フレームワーク `gain_*` の実装。**通常の開発対象はこちら**

有料 MOD を買わずに RP サーバーを成立させる、というのがプロジェクトの前提。
有料スクリプトの入手・再配布は行わない。

## 新しいリソースを作るときは先に `fivem/docs/DESIGN-PROCESS.md` を読む

「既存実装があるならまず調べて真似る、無いなら1から作る」という方針が定めてある。
実測データでカテゴリの現状を見る → 読めるソースは読む → **コードは写さず設計を学ぶ**
（ox 系の多くは LGPL/GPL 系でライセンス義務が伝播する）。
参考にしたものは各リソースの `README.md` に残す。`gain_spawn/README.md` が適用例。

## ローカル検証環境

WSL2 上に FXServer build 35245 + MariaDB 10.6 が用意してある。
リポジトリの `fivem/resources/[gain]` は `/home/gain/fivem/server-data/resources/[gain]`
からシンボリックリンクで参照されているので、**ここを編集すればそのまま検証機に反映される**。

```bash
fivem/scripts/dev-server.sh start      # 起動
fivem/scripts/dev-server.sh restart    # 編集後はこれ
fivem/scripts/dev-server.sh errors     # エラーだけ抜き出す
fivem/scripts/dev-server.sh log 40     # ログ末尾
fivem/scripts/dev-server.sh cmd <cmd>  # サーバーコンソールにコマンドを送る
```

DB は `mariadb -u gain -pgainlocal gain`（ローカル検証専用の資格情報）。
台帳の照合はこれで見る:

```bash
mariadb -u gain -pgainlocal gain -e \
  "SELECT citizenid, account, SUM(delta) FROM gain_transactions GROUP BY citizenid, account;"
```

ゲームクライアントからは `connect localhost`。

## 踏むと時間を溶かす罠（すべて実機で確認済み）

- **FXServer は stdin が閉じていると即終了する。** ログには
  `Quitting: Ctrl-C pressed in server console.` と出るが Ctrl-C は押されていない。
  バックグラウンド起動では FIFO を噛ませる（`dev-server.sh` がやっている）
- **`sv_lan 1` では `license:` 識別子が付かない。** クライアントが Cfx.re で認証されないため。
  `gain_core/server/player.lua` の `getLicense` が nil を返し、接続が拒否される。
  マスターリストに出したくないだけなら `sv_master1 ""` を使う
- **`sv_enforceGameBuild` を指定すると、クライアントに 1.7GB のダウンロードを要求することがある。**
  検証では外しておく
- **`basic-gamemode` は入れない。** `setAutoSpawn(true)` と `forceRespawn()` を呼ぶため
  `gain_spawn` とスポーン制御を奪い合う。既定マップ（`fivem-map-skater` 等）も同じ理由で使わない
- **ライセンスキーはローカル検証でも必須。** `server-data/secrets.cfg`（gitignore 済み）に置く
- **`luac` は検証機に入っていない。** 構文確認は FXServer に実際に読み込ませて
  `dev-server.sh errors` を見るのが早い

## アーキテクチャ

### リソースの責務

| リソース | 責務 |
|---|---|
| `gain_core` | 身元・永続化・所持金・権限・ロケール・ログ・イベント保護・ESX/QBCore 互換 |
| `gain_spawn` | スポーンの権威。初回スポーン、位置復元、死亡→復帰 |
| `gain_admin` | 管理メニュー（F6）とコマンド |
| `gain_anticheat` | 体力・移動・武器・爆発の検知と段階処分 |
| `gain_jobs` | 就職・出退勤・巡回業務・給料 |
| `gain_banking` | 銀行窓口・ATM・送金・履歴 |
| `gain_build` | 図面（ゲーム内 CAD）・地縄張り。素材と労働力は未実装 |

### 守っている原則

- **公開面は exports のみ。** `GetCoreObject` のような全部入りオブジェクトを増やさない
  （QBCore 互換のためだけに `compat.lua` が提供している）
- **金額・権限・到達判定はすべてサーバー側。** クライアントから来た数値は使わない
- **残高の変更は必ず取引履歴を伴う。** 不変条件は
  `SUM(gain_transactions.delta) == gain_characters.<account>`。
  `gain_characters` の `cash` / `bank` を書く SQL は `server/ledger.lua` だけ。
  `player.save()` は残高を書かない（絶対上書きで他経路を踏み潰さないため）。
  検算は `gainverify` をサーバーコンソールで叩く
  `gain_transactions` には `account` と符号付き `delta` があり、ここから残高を再現できる
- **コアに `Wait(0)` の常時ループを置かない**
- **クライアントから叩ける net イベントは `RegisterSafeEvent` を通す**
  （送信元検証とレート制限）。生の `RegisterNetEvent` は原則使わない
- 1リソースは1人が全体を把握できる大きさに保つ。`gain_core` は約1,240行

### 読み込み順が意味を持つ

`gain_core/fxmanifest.lua` の `server_scripts` は依存順に並んでいる
（`log` → `safe_event` → `permission` → `money` → `player` → `api` → `compat`）。
グローバル（`GainLog`、`Permission`、`Money`）を定義する側が先。ファイルを足すときは位置に注意。

`@gain_core/server/safe_event.lua` は他リソースへ**個別にロードされる**ため、
そこから `gain_core` のグローバル（`GainLog` など）は見えない。
リソースをまたぐ参照は `exports['gain_core']` を使う。

### 状態の受け渡し

`gain_core` はキャラクターデータを `gain_core:setPlayerData` で本人に送る。
所持金は本人限定の情報なので、レプリケートされる Player statebag には置かない。

## SQL の変更

`fivem/sql/schema.sql` は新規環境用。既存 DB への変更は
`fivem/sql/migrations/` に冪等な migration を足し、**両方を更新する**（列の順序も合わせる）。

```bash
mariadb -u gain -pgainlocal gain < fivem/sql/migrations/001_ledger.sql
```

## 建物を設計するとき

**`building-design` スキルを使う。** 間取りを頼まれたら、いきなり図面を描かず要件を聞き出す。
グリッドを機械的に分割して部屋名を割り振ったものは間取りではない。
スキルに世界の建築類型・寸法基準・作図規約が入っている。

設計した案は `plan-review` エージェントに監査させる。設計者本人には自分の欠陥が見えない。

図面と部品は `fivem/tools/` の `genplan.py`（図面一式）と `genkit.py`（.obj 部品）で生成する。

## 効率よく進めるために

- **コード全体を横断して調べるときは `Explore` エージェント**を使う。3,600行あり、
  金銭の変更経路のように「呼び出し元を全部洗い出す」種類の調査は手で追うと漏れる
- **変更をレビューするときは `/code-review`**。金銭とイベント検証まわりは
  境界条件（残高上限、切断レース、失敗時の戻り値）で壊れるので、ここを重点的に見る
- 実装計画は `Plan` エージェントに投げると、段階の切り方と完了条件まで出る
- 日本語で書く。コメント・コミットメッセージ・ドキュメント・ロケールすべて日本語
