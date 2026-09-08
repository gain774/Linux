# dyn_economy

RedM 向けの需給連動 価格エンジン。設計は [`docs/redm-dynamic-economy.md`](../../docs/redm-dynamic-economy.md)。
このリソースは設計ドキュメントの **Phase 1〜2**（スキーマ・価格式・exports）を実装したもの。

## 現在の状態

| | |
|---|---|
| 実装済み | 仮想在庫モデル（§4.1〜4.3）、まとめ売りの積分価格（§4.2）、物価水準レイヤー（§4.5）、価格スタック（§4.6）、レシピ原価による下限（§5）、exports（§10）、アンカーからの `currency_scale` 導出（§6.2 B） |
| 未実装 | 既存 NPC 店舗への接続（Phase 3・要ブリッジ）、レシピインポータ（Phase 4）、自動較正（§6）、成長曲線（§7）、委託所（§8）、国庫・組合（§9） |

**フレームワークにはまだ繋がっていない。** 価格の計算と記録だけを行い、
所持金とインベントリは一切触らない。接続は `dyn_economy_bridge` を書く Phase 3 の作業。

## 依存

- [oxmysql](https://github.com/overextended/oxmysql) — 無くても起動はするが、
  永続化なしのメモリ動作になる（再起動で仮想在庫が均衡値に戻る）

## 導入

1. `resources/dyn_economy` をサーバーの resources 配下に置く
2. `server.cfg` に `ensure dyn_economy`（`ensure oxmysql` より後）
3. 起動時に `sql/schema.sql` が自動で流れる（`Config.Db.autoMigrate`）
4. `config/items.lua` に扱う品目の**相対価値**を書く。金額ではなく比を書く
5. `config/config.lua` の `Config.Anchor` に基準アイテム 1 つの希望価格を書くと、
   そこから `currency_scale` が決まり全品目の金額が定まる

## コマンド

権限は ACE `dyn_economy.admin`（コンソールは常に可）。

```
/dyn_quote <item> [数量] [sell|buy]   見積り。合計・平均単価・現在単価・税・在庫を出す
/dyn_price [絞り込み]                 品目一覧と現在価格、均衡在庫に対する比率
/dyn_cost <item>                      レシピ原価と、そこから決まる買取下限
/dyn_setstock <item> <値>             仮想在庫を直接いじる（動作確認用）
/dyn_econ [key] [値]                  currency_scale / cpi_mult / income_mult の確認と設定
/dyn_reload                           config と DB を読み直す
```

## exports

```lua
-- 見積り。在庫は動かさない
exports['dyn_economy']:QuoteSell(item, qty, identifier)  --> { ok, total, unitAvg, priceNow, tax, stock }
exports['dyn_economy']:QuoteBuy(item, qty, identifier)

-- 確定。仮想在庫を動かし dyn_npc_tx に記録する
exports['dyn_economy']:CommitSell(identifier, item, qty, shopId)
exports['dyn_economy']:CommitBuy(identifier, item, qty, shopId)

-- 一覧表示用
exports['dyn_economy']:GetItemInfo(item)  --> { npcBuy, npcSell, stock, targetStock, matCost, ... }
```

`Quote` と `Commit` を分けているのは、メニュー表示と決済の間に価格が動いても表示額で
確定させないため。**`Commit` の戻り値が正**。

**呼び出し側の責務**: 所持金と現物の検証・移動は店舗リソース側で行う。
このリソースは価格の計算と仮想在庫の更新しかしない。
金銭処理を持たせるとフレームワークごとに書き換える必要が出るため、意図的に分けてある。

## テスト

FiveM を起動せず、素の Lua で走る。

```bash
apt install lua5.4      # 初回のみ
./tests/run_all.sh
```

- `tests/run.lua` — 価格式とレシピ原価の純粋関数。閉形式の積分を数値積分と突き合わせている
- `tests/integration.lua` — config → state → pricing の価格スタック全体

## ファイル構成

```
shared/pricing_math.lua   価格式の純粋関数。FiveM API を一切参照しない（テスト可能性のための制約）
server/recipes_core.lua   レシピ原価の再帰計算。同上
server/state.lua          設定と仮想在庫のインメモリ状態。DB は起動時と定期書き戻しだけ
server/pricing.lua        価格スタック。価格の決まり方はこのファイルに閉じている
server/recipes.lua        DB からレシピ表を読み、原価計算に注入する
server/ledger.lua         取引ログと価格履歴
server/exports.lua        外部リソース向け API
```
