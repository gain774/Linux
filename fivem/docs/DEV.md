# gain framework 開発・導入メモ

FiveM 用の自作フレームワーク。有料スクリプトを買わずに本格 RP サーバーを成立させるため、
必要なリソースを `gain_*` として自作する。ESX / QBCore 互換レイヤーを持つので、
既存の無料リソースも（主要 API の範囲で）そのまま載せられる。

## 構成

| リソース | 役割 | 状態 |
|---|---|---|
| `gain_core` | プレイヤー・所持金・権限・ロケール・互換レイヤー | M1 実装済み |
| `gain_admin` | 管理メニュー（キック / BAN / ワープ等） | M2 予定 |
| `gain_anticheat` | サーバー側検知と段階的処分 | M3 予定 |
| `gain_jobs` | ジョブと給料 | M4 予定 |
| `gain_banking` | 現金 / 銀行 / ATM / 送金 | M4 予定 |

## 前提

- MariaDB（または MySQL）と [oxmysql](https://github.com/overextended/oxmysql)（MIT, 無料）
- FXServer（Phase 9 で構築）

## 導入手順

```bash
# 1) DB とユーザーを用意
sudo apt install -y mariadb-server
sudo mysql -e "CREATE DATABASE gain CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
sudo mysql -e "CREATE USER 'gain'@'localhost' IDENTIFIED BY 'ここにパスワード';"
sudo mysql -e "GRANT ALL PRIVILEGES ON gain.* TO 'gain'@'localhost'; FLUSH PRIVILEGES;"

# 2) スキーマ投入
mysql -u gain -p gain < fivem/sql/schema.sql

# 3) このリポジトリを server-data に配置
cd ~/server-data/resources
git clone <このリポジトリの URL> gain-repo
ln -s gain-repo/fivem/resources/[gain] [gain]

# 4) oxmysql を resources に置く（GitHub の releases から）

# 5) server.cfg に fivem/server.cfg.example の内容を反映して再起動
```

初回接続後、サーバーコンソールに出る自分の `license:...` を
`gain_core/shared/config.lua` の `Config.Owners` に追加して再起動すると owner 権限になる。

## 他リソースからの使い方

```lua
-- サーバー側
local player = exports['gain_core']:GetPlayer(src)
exports['gain_core']:AddMoney(src, 'bank', 500, 'paycheck')
if exports['gain_core']:HasPermission(src, 'admin') then ... end
exports['gain_core']:Notify(src, 'メッセージ', 'success')
exports['gain_core']:Log('admin', '何かした', { player = player.name })

-- クライアント側
local data = exports['gain_core']:GetPlayerData()
AddEventHandler('gain_core:playerDataUpdated', function(data) ... end)
```

クライアントから叩けるイベントは必ず `RegisterSafeEvent` で登録する
（送信元検証とレート制限が入る）。依存リソースの fxmanifest でこう読み込む:

```lua
server_scripts {
    '@gain_core/shared/config.lua',
    '@gain_core/server/safe_event.lua',
    'server/main.lua',
}
```

## サーバーイベント

| イベント | 発火 |
|---|---|
| `gain_core:playerLoaded` (src, citizenid) | キャラ読み込み完了 |
| `gain_core:playerUnloaded` (src, citizenid) | 退出時（保存後） |
| `gain_core:jobChanged` (src, job) | 職業変更 |
| `gain_core:dutyChanged` (src, job) | 勤務状態変更 |

## 互換レイヤーの範囲

カバー: プレイヤー取得 / 所持金（cash・bank）/ 職業 / 通知。
未カバー: インベントリ、ESX の `RegisterServerCallback`、QBCore の `Shared.Items` など。
これらを使うリソースは個別対応が必要。互換レイヤーは `Config.Compat` で個別に無効化できる。

## 静的チェック

```bash
find fivem -name '*.lua' -print0 | xargs -0 -n1 luac -p
```
