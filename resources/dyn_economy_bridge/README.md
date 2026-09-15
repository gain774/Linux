# dyn_economy_bridge

`dyn_economy`（価格エンジン）と VORP をつなぐアダプタ。設計ドキュメントの **Phase 3**。

確認に使ったバージョン: **vorp_core 3.3 / vorp_inventory 4.5**

## 役割

価格エンジンは金銭とインベントリを一切触らない。このリソースがその境界を受け持ち、
店舗側には「1 行呼ぶだけ」の入口を出す。

```
既存の NPC 店舗  ──▶  dyn_economy_bridge  ──▶  dyn_economy   （価格の計算・確定）
                              │
                              └────────────▶  VORP          （所持金・インベントリ）
```

## 導入

```cfg
ensure oxmysql
ensure vorp_core
ensure vorp_inventory
ensure dyn_economy
ensure dyn_economy_bridge
```

`config.lua` で通貨種別（0 = ドル / 1 = ゴールド / 2 = ROL）と通知の有無を設定する。

## 既存店舗の書き換え方

固定価格の計算と決済を、次の 1 行に置き換える。

```lua
-- 買い取り（プレイヤー → NPC）
local res = exports['dyn_economy_bridge']:SellToNpc(source, 'corn', 20, 'shop_valentine')
if res.ok then
    -- res.total が実際の受取額。入金も現物の引き落としも済んでいる
end

-- 販売（NPC → プレイヤー）
local res = exports['dyn_economy_bridge']:BuyFromNpc(source, 'corn', 20, 'shop_valentine')
```

メニューに価格を出すだけなら:

```lua
local q = exports['dyn_economy_bridge']:Quote(source, 'corn', 20, 'sell')
-- q.total / q.unitAvg / q.priceNow
```

`Quote` は**表示専用**。実際の金額は `SellToNpc` / `BuyFromNpc` の戻り値が正。
メニューを開いてから決定するまでの間に価格が動くため、表示額で決済してはいけない。

戻り値が `{ ok = false, error = '...' }` のときは、プレイヤーへの通知はブリッジ側で
済ませてある（`BridgeConfig.notify`）。店舗側で二重に通知しなくてよい。

| error | 意味 |
|---|---|
| `unknown_item` / `item_disabled` | 価格エンジンが扱っていない品 |
| `not_sellable` / `not_buyable` | その方向の取引が無効 |
| `not_enough_items` / `not_enough_money` / `cannot_carry` | プレイヤー側の条件不足 |
| `qty_invalid` / `no_character` | 引数かキャラクターの問題 |
| `remove_item_failed` / `add_item_failed` / `commit_failed` | 決済途中の失敗（後述のとおり巻き戻し済み） |

## 決済の順序（`server/txflow.lua`）

順序を間違えると金か現物が増える。実装はこの順に固定してある。

**売却**: 見積り → 所持数の確認 → **現物を引く** → 価格を確定 → 入金

現物を先に引くのは、引けなければ何も起きていない状態で止まれるから。
確定は現物を引いた**後**。インベントリ操作は yield するので、その間に価格が動きうる。
**確定値は `commit` の戻り値であって見積りではない。**
確定に失敗した場合は現物を返す。

**購入**: 見積り → 所持容量の確認 → 所持金の確認 → 価格を確定 → 支払い → **現物を渡す**

所持金の確認と価格の確定の間で yield してはいけない。yield すると、確認した残高と
実際に引く額がズレる。yield する `canCarryItem` を先に済ませてから、
`getMoney` → `commit` → `removeMoney` を続けて実行する。
現物を渡せなかった場合は返金し、`VoidCommit` で仮想在庫と取引記録も戻す。

VORP の `removeCurrency` は残高を検査せずマイナスまで引くので、
残高の確認はこちら側の責任になっている。

## 他リソースとの干渉（`server/compat.lua`）

配布物のソースを実際に読んで確認した干渉点。起動時に検出する。
**他リソースの設定は書き換えない** — 勝手に他人のリソースを変更するほうが事故が大きいので、
こちらが降りる（品目を無効化する）か、警告を出すかに留めている。

### 起動時に自動で無効化されるもの

| 対象 | 理由 |
|---|---|
| vorp_inventory の `items` に登録が無い品目 | 残すと売買のたびに `Item [x] does not exist in DB.` がコンソールに出続け、`canCarryItem` が常に false を返して購入が全部失敗する |
| 武器 | `items` ではなく `loadout` 側で管理されており、`addItem` / `subItem` が効かない。上の検証で自動的に弾かれる |
| 劣化アイテム（`maxDegradation > 0`） | 価格エンジンは個体の劣化度を見ないので、状態の悪い品を満額で売れてしまう（vorp_stores は `percentage / 100` を価格に掛けている）。承知のうえで扱うなら `compat.allowDegradable = true` |

無効化された品目は起動ログに一覧で出る。永続化はせず、起動のたびに判定し直す。

### 手で直す必要があるもの

**vorp_stores を使っている場合、`config.lua` で次の 2 つを `false` にすること。**
起動時に検出して警告を出すが、こちらからは書き換えない。

```lua
RandomPrices = false,   -- true だと再起動のたびに価格をランダムに振り直し、需給の結果が毎回消える
DynamicStore = false,   -- true だと店舗ごとの在庫上限を独自に持ち、仮想在庫と二重管理になる
```

そのほか運用で避けるもの:

- **gold / ROL 建ての品目を `dyn_items` に入れない。** vorp_stores は品目ごとに通貨を選べるが、
  価格エンジンは単一通貨を前提にしている
- **vorp_banking を使っている場合、所持金は `character.money` ではなく `bank_users` テーブルにもある。**
  資産センサス（設計 §6.4、Phase 5.6）は両方を合算しないと総額が合わない

### インベントリイベントの扱い

`vorp_inventory:Server:OnItemCreated` / `OnItemRemoved` は、クエスト進行・ログ・アンチチートなどが
listen していることがある。

- **通常の売買では発火させる。** 普通の店と同じ挙動にしないと、それらから取引が見えなくなる
- **巻き戻し（決済に失敗して現物を返す）では抑止する。** `addItem` / `subItem` の第 6 引数
  `allow = true` を渡す。発火させると他スクリプトが二重にカウントする

### DB ドライバ

vorp_core 3.3 と vorp_inventory 4.5 はどちらも `@oxmysql/lib/MySQL.lua` を読み込んでいる。
oxmysql は必ず存在するので、ドライバの衝突は無い。

## VORP API のはまりどころ

- `Core = exports.vorp_core:GetCore()` を使う。`getCore` イベントは非推奨
- `User.getUsedCharacter` は**関数ではなくプロパティ**（`()` を付けない）
- `getItemCount(source, cb, itemName, metadata, percentage)` — **cb が第 2 引数**
- **metadata を省略するときは必ず `nil` を渡す。** `{}` を渡すと Lua では truthy なので
  vorp_inventory が「メタデータ一致のアイテムを探す」経路に入り、常に 0 件になる
- `addItem` / `subItem` / `getItemCount` は cb を省くと同期的に値を返す

## 取引の主体はキャラクター

`identifier` には `charIdentifier`（キャラクター ID）を使う。
1 アカウントで複数キャラを持つ運用があり、財布が別なら経済上も別人として扱うのが正しい。
アカウント単位で見たいときのために `exports['dyn_economy_bridge']:GetAccountIdentifier(source)` がある。

所持金や所持数を店舗側から参照したい場合も、アダプタのテーブルを受け取るのではなく
個別の export を使う（`GetItemCount` / `GetMoney` / `GetIdentifier`）。
export の戻り値は msgpack でシリアライズされるので、**テーブルに入れた関数は落ちて nil になる。**

## テスト

```bash
./tests/run_all.sh
```

- `tests/bridge.lua` … 決済フロー。価格エンジンは本物を使い、所持金と現物だけスタブに差し替える
- `tests/compat.lua` … 品目の突き合わせと vorp_stores の設定衝突検出

価格エンジンは本物を使い、所持金と現物だけスタブに差し替えている。
失敗経路（現物を引けない・所持金不足・持ちきれない・現物を渡せない）で
金と現物と仮想在庫が元に戻ることを重点的に確認している。
