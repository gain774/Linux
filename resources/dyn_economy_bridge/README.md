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
アカウント単位で見たいときのために `GetAdapter().getAccountIdentifier(source)` を用意してある。

## テスト

```bash
./tests/run_all.sh        # tests/bridge.lua が決済フローの 42 アサーションを検証する
```

価格エンジンは本物を使い、所持金と現物だけスタブに差し替えている。
失敗経路（現物を引けない・所持金不足・持ちきれない・現物を渡せない）で
金と現物と仮想在庫が元に戻ることを重点的に確認している。
