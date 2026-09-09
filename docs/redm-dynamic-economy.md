# RedM 動的経済 Mod — 設計ドキュメント

需要と供給で NPC 売買価格を変動させ、さらにプレイヤー間取引を仲介・データ化するリソース群の設計。
**この文書は設計のみ。実装は未着手。**

作業ブランチ: `claude/redm-npc-price-dynamics-y3jdl5`

---

## 1. 解決したい課題

| 課題 | 現状 | 本 Mod での対処 |
|---|---|---|
| 農業の単一作物ゲー | 「回収量が多く単価が高い」作物だけ植えれば最適解になる | 売れば売るほど買取単価が下がる（限界価格）。1 種に寄せると自分で価格を壊す |
| NPC が無限の金蛇口 | NPC 買取価格が固定なので金が無限に湧く | 仮想在庫プールを持たせ、供給過多で価格が沈む。時間経過で緩やかに回復 |
| 作れば作るほど損な品が出る | 素材原価 > 完成品の NPC 買取価格 | 全レシピを DB 化し、素材の現在価格から原価を再計算して下限価格に反映 |
| プレイヤー間取引が育たない | NPC のほうが手軽で確実 | NPC には常に大きなスプレッド（安く買い高く売る）を持たせ、委託所（エスクロー）の手数料をそれより十分小さくする |
| 取引実態が見えない | 手渡し取引はログに残らない | 委託所を経由させ、約定を全て DB 化。実勢価格（VWAP）を算出して NPC 価格にも反映 |
| サーバーごとに物価が違う | 価格を Mod にハードコードすると導入先で破綻する | 価格を「相対指数 × サーバー固有スケール」に分解し、導入時と運用中に自動較正（§6） |
| 成長速度が意図とズレる | 「○日でこのくらい」の狙いがあっても実測が合っているか分からない | 目標曲線を宣言し、コホート中央値との誤差で金のソース側を自動補正（§7・既定 OFF） |
| 手数料が消えるだけ | NPC スプレッドで抜いた金がどこにも行かない | 税として国庫に記帳し、プレイヤーが立てた組合への補助金として還流（§9） |
| 突出した資産家がいる | 平均を取ると 1 人の大富豪でサーバー全体の物価が歪む | 起動時センサスで中央値と MAD を使い、外れ値は統計から除外・総額には算入（§6.4） |

**設計の中心的な考え方**: NPC は「価格の下限を保証する最後の買い手」であって、最適な売り先ではない。
プレイヤー間で捌けるものは NPC に売ると損をする、という価格差を構造的に作る。

---

## 2. リソース構成

フレームワーク（RSGCore / VORP / RedEM:RP）に依存する部分をアダプタ 1 ファイルに閉じ込め、
価格エンジン本体はフレームワーク非依存にする。

```
dyn_economy/                      -- 価格エンジン本体（フレームワーク非依存）
├── fxmanifest.lua
├── config/
│   ├── config.lua                -- グローバル係数、更新間隔、各レイヤーのトグル（§7.7）
│   ├── items.lua                 -- アイテム別パラメータ（price_index, elasticity 等）
│   └── categories.lua            -- カテゴリ既定値（農作物 / 鉱物 / 加工品 / 動物素材）
├── server/
│   ├── main.lua                  -- 起動、DB マイグレーション、定期タスク
│   ├── pricing.lua               -- 価格式（本文書 §4）
│   ├── recipes.lua               -- レシピ原価の再帰計算（§5）
│   ├── calibration.lua           -- サーバー固有スケールの自動較正（§6）
│   ├── progression.lua           -- 目標成長曲線ターゲティング（§7・既定 OFF）
│   ├── census.lua                -- 起動時／日次の資産センサスと健全性チェック（§6.4）
│   ├── ledger.lua                -- 取引記録・価格履歴の書き込み
│   └── exports.lua               -- 外部リソース向け API（§10）
├── client/
│   └── ui.lua                    -- 価格表示・変動インジケータ
└── sql/
    └── schema.sql

dyn_economy_bridge/               -- フレームワークアダプタ（差し替え対象はここだけ）
├── fxmanifest.lua
└── server/
    ├── rsgcore.lua
    ├── vorp.lua
    └── redemrp.lua

dyn_market/                       -- プレイヤー間取引の仲介（委託所 / エスクロー）
├── fxmanifest.lua
├── server/
│   ├── orders.lua                -- 出品・購入・キャンセル・期限切れ返却
│   └── settlement.lua            -- 決済と手数料、約定ログ
├── client/
│   └── menu.lua
└── sql/
    └── schema.sql

dyn_guilds/                       -- 国庫・税・組合・補助金（§9、既定 OFF）
├── fxmanifest.lua
├── server/
│   ├── treasury.lua              -- 税の記帳と国庫残高（§9.1）
│   ├── guilds.lua                -- 申請・承認・メンバー管理（§9.3）
│   └── subsidy.lua               -- 補助金の算定と支払い（週次バッチ / §9.4）
├── client/
│   └── cityhall.lua              -- 市役所の申請・掲示メニュー
└── sql/
    └── schema.sql
```

分割の理由: 価格エンジンだけ先に入れて既存店舗に噛ませる運用ができ、委託所と組合は後から追加できる。
どのリソースも単体で起動しない選択ができ、起動しなければその機能は完全に存在しないのと同じになる。

---

## 3. データベーススキーマ

MySQL / MariaDB（`oxmysql` 前提）。すべて `dyn_` プレフィックス。

### 3.1 アイテム定義と状態

```sql
CREATE TABLE IF NOT EXISTS dyn_items (
  item            VARCHAR(64)  NOT NULL PRIMARY KEY,
  category        VARCHAR(32)  NOT NULL DEFAULT 'misc',
  base_price      DECIMAL(12,2) NOT NULL,        -- 基準価格 P0（NPC 買取の基準）
  target_stock    DECIMAL(14,2) NOT NULL,        -- 均衡在庫 S0
  elasticity      DECIMAL(5,3)  NOT NULL DEFAULT 0.500, -- 価格弾力性 e
  min_mult        DECIMAL(5,3)  NOT NULL DEFAULT 0.200, -- 価格下限倍率
  max_mult        DECIMAL(5,3)  NOT NULL DEFAULT 3.000, -- 価格上限倍率
  half_life_min   INT           NOT NULL DEFAULT 720,   -- 在庫が均衡へ戻る半減期（分）
  npc_spread      DECIMAL(5,3)  NOT NULL DEFAULT 0.300, -- NPC 販売価格 = 買取価格 /(1-spread)
  npc_sellable    TINYINT(1)    NOT NULL DEFAULT 1,     -- プレイヤー→NPC 売却可否
  npc_buyable     TINYINT(1)    NOT NULL DEFAULT 1,     -- NPC→プレイヤー 購入可否
  enabled         TINYINT(1)    NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS dyn_item_state (
  item            VARCHAR(64)  NOT NULL PRIMARY KEY,
  virtual_stock   DECIMAL(14,2) NOT NULL,        -- 現在の仮想在庫 S
  cached_buy      DECIMAL(12,2) NOT NULL,        -- NPC 買取単価（キャッシュ）
  cached_sell     DECIMAL(12,2) NOT NULL,        -- NPC 販売単価（キャッシュ）
  mat_cost        DECIMAL(12,2) NULL,            -- レシピ原価（§5、なければ NULL）
  updated_at      DATETIME     NOT NULL,
  CONSTRAINT fk_state_item FOREIGN KEY (item) REFERENCES dyn_items(item) ON DELETE CASCADE
);
```

`virtual_stock` は実在庫ではなく「市場にどれだけ物が溢れているか」の指標。
プレイヤーが NPC に売れば増え、NPC から買えば減り、時間経過で `target_stock` へ戻る。

### 3.2 NPC 売買ログ

```sql
CREATE TABLE IF NOT EXISTS dyn_npc_tx (
  id          BIGINT AUTO_INCREMENT PRIMARY KEY,
  identifier  VARCHAR(64) NOT NULL,              -- citizenid / charidentifier
  item        VARCHAR(64) NOT NULL,
  direction   ENUM('sell','buy') NOT NULL,       -- sell = プレイヤーが NPC に売った
  qty         INT NOT NULL,
  unit_price  DECIMAL(12,2) NOT NULL,            -- 実際の平均約定単価
  total       DECIMAL(14,2) NOT NULL,
  stock_before DECIMAL(14,2) NOT NULL,
  stock_after  DECIMAL(14,2) NOT NULL,
  shop        VARCHAR(64) NULL,                  -- 店舗識別子（地域差分の分析用）
  created_at  DATETIME NOT NULL,
  INDEX idx_item_time (item, created_at),
  INDEX idx_ident_time (identifier, created_at)
);
```

このテーブルが「いくらで何個売ったか / 買ったか」の一次データ。
価格エンジンはこれを直接読んで価格を決めるのではなく、書き込み時に `virtual_stock` を更新する
（読み取り時に毎回集計すると重いため）。テーブルは分析・監査・巻き戻し用。

### 3.3 レシピ

```sql
CREATE TABLE IF NOT EXISTS dyn_recipes (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  output_item VARCHAR(64) NOT NULL,
  output_qty  INT NOT NULL DEFAULT 1,
  source      VARCHAR(64) NOT NULL,              -- 抽出元リソース名（rsg-crafting 等）
  UNIQUE KEY uq_out_src (output_item, source)
);

CREATE TABLE IF NOT EXISTS dyn_recipe_inputs (
  recipe_id   INT NOT NULL,
  item        VARCHAR(64) NOT NULL,
  qty         DECIMAL(10,3) NOT NULL,
  PRIMARY KEY (recipe_id, item),
  CONSTRAINT fk_ri_recipe FOREIGN KEY (recipe_id) REFERENCES dyn_recipes(id) ON DELETE CASCADE
);
```

### 3.4 価格履歴（グラフ・分析用）

```sql
CREATE TABLE IF NOT EXISTS dyn_price_history (
  item         VARCHAR(64) NOT NULL,
  bucket_at    DATETIME NOT NULL,                -- 1 時間単位に丸めた時刻
  npc_buy      DECIMAL(12,2) NOT NULL,
  npc_sell     DECIMAL(12,2) NOT NULL,
  player_vwap  DECIMAL(12,2) NULL,               -- 委託所の加重平均約定単価
  vol_npc_sell INT NOT NULL DEFAULT 0,
  vol_npc_buy  INT NOT NULL DEFAULT 0,
  vol_player   INT NOT NULL DEFAULT 0,
  PRIMARY KEY (item, bucket_at)
);
```

### 3.5 委託所（プレイヤー間取引）

```sql
CREATE TABLE IF NOT EXISTS dyn_market_orders (
  id          BIGINT AUTO_INCREMENT PRIMARY KEY,
  seller      VARCHAR(64) NOT NULL,
  item        VARCHAR(64) NOT NULL,
  qty         INT NOT NULL,                      -- 残数量
  qty_initial INT NOT NULL,
  unit_price  DECIMAL(12,2) NOT NULL,            -- 売り手の希望単価
  metadata    JSON NULL,                         -- 品質・耐久など
  status      ENUM('open','filled','cancelled','expired') NOT NULL DEFAULT 'open',
  created_at  DATETIME NOT NULL,
  expires_at  DATETIME NOT NULL,
  INDEX idx_item_status (item, status, unit_price)
);

CREATE TABLE IF NOT EXISTS dyn_market_trades (
  id          BIGINT AUTO_INCREMENT PRIMARY KEY,
  order_id    BIGINT NOT NULL,
  seller      VARCHAR(64) NOT NULL,
  buyer       VARCHAR(64) NOT NULL,
  item        VARCHAR(64) NOT NULL,
  qty         INT NOT NULL,
  unit_price  DECIMAL(12,2) NOT NULL,
  fee         DECIMAL(12,2) NOT NULL,
  created_at  DATETIME NOT NULL,
  INDEX idx_item_time (item, created_at)
);

CREATE TABLE IF NOT EXISTS dyn_market_escrow (
  order_id    BIGINT NOT NULL PRIMARY KEY,       -- 預かり中の現物（インベントリから隔離）
  item        VARCHAR(64) NOT NULL,
  qty         INT NOT NULL,
  metadata    JSON NULL
);
```

---

## 4. 価格式

### 4.1 基本形

仮想在庫 `S` に対する限界価格（1 個あたりの買取価格）:

```
p(S) = P0 * (S0 / S)^e          … e = elasticity, S0 = target_stock
p(S) = clamp(p(S), P0*min_mult, P0*max_mult)
```

- `S = S0` のとき `p = P0`（均衡）
- 供給過多（`S > S0`）で価格が下がり、品薄（`S < S0`）で上がる
- `e` が大きいほど敏感。農作物 0.6〜0.8、鉱物 0.4、加工品 0.3 程度を想定

### 4.2 一括売却は 1 個ずつ積分する（重要）

100 個まとめて売っても最初の 1 個と同じ単価、では「単価が高い作物を大量生産」を止められない。
数量 `q` を売却したときの受取総額は連続的な積分で求める:

```
Total_sell(S, q) = ∫[S → S+q] P0 * (S0/x)^e dx
                 = P0 * S0^e * ( (S+q)^(1-e) - S^(1-e) ) / (1-e)      (e ≠ 1)
平均単価 = Total_sell / q
```

購入（NPC から買う）は在庫が減る向きの積分:

```
Total_buy(S, q) = ∫[S-q → S] P0 * (S0/x)^e dx / (1 - npc_spread)
```

上下限クランプは積分後にも掛ける（`q * P0 * min_mult` を下回らない、等）。

**効果**: 単一作物を 500 個抱えて売りに行くと平均単価が明確に落ち、
10 種類を 50 個ずつ売ったほうが総額が高くなる。これが多品目栽培への誘導になる。

### 4.3 時間による均衡回帰

在庫は放置すると `S0` に指数的に戻る（NPC が売り捌いた / 消費したという想定）:

```
S(t + Δt) = S0 + (S(t) - S0) * 2^(-Δt / half_life_min)
```

`half_life_min` が短いほど価格が早く回復する。腐りやすい農作物は短め（例 360 分 = 6 時間）、
金塊のような蓄財品は長め（例 4320 分 = 3 日）にすると「毎日ちまちま売る」が最適戦略になり、
一気に大量投入するプレイに勝つ。

サーバー再起動をまたいでも `updated_at` からの経過時間で一度に計算すればよい（毎 tick 不要）。

### 4.4 スプレッド

```
npc_sell_price = npc_buy_price / (1 - npc_spread)
```

この差額は消滅させず、**税として国庫に記帳する**（§9.1）。プレイヤーから見た金額は同じで、
「消えた」が「国庫に入った」に変わるだけ。貯まった税は組合への補助金の原資になる（§9.4）。

`npc_spread = 0.30` なら、NPC から買って NPC に売り戻すと 30% 損する。
一方、委託所の手数料は 3%（§8）。**この 27 ポイントの差がプレイヤー間取引の動機**になる。
NPC 買い戻しによる裁定（安く買って高く売る）も同時に塞げる。

---

### 4.5 物価水準（CPI）レイヤー — 需給とは別軸で持つ

§4.1〜4.3 の需給変動は「**アイテム個別・短期**（数時間〜数日）」の動き。
それとは別に「**サーバー全体・長期**」の物価水準を、独立した 1 つの値として持つ。

```
cpi_mult          … サーバー全体の物価水準倍率（既定 1.0）
category_mult[c]  … カテゴリ別の物価倍率（季節・イベント用、既定 1.0）
```

分けておく理由は 3 つ。

1. **原因が説明できる** — 値上がりを「需給で +40% / 物価水準で +12%」と分解して UI に出せる。
   1 本の数値に混ぜてしまうと、高いのが一時的な品薄なのか経済全体の膨張なのか誰にも分からない
2. **独立に止められる** — 物価水準だけ凍結して需給変動は残す、という運用ができる（§7.7）
3. **入力が違う** — 需給は売買ログから、物価水準は次の 4 つから決まる

| `cpi_mult` を動かすもの | 節 | 既定 |
|---|---|---|
| 所持金追従（購買力の固定） | §6.5 | OFF |
| マネーサプライ PI 制御 | §6.7 | OFF |
| 目標成長曲線ターゲティング | §7 | OFF |
| 手動・季節・イベント設定 | 下記 | 常時可 |

つまり**既定では `cpi_mult = 1.0` のまま動かず、需給変動だけが効く**。
較正レイヤーを有効にすると、その出力がすべてこの 1 つの数に集約される。

#### 季節・イベントによる手動の物価操作

```lua
Config.PriceLevel = {
  seasonal = {
    winter = { food = 1.25, fur = 0.85 },   -- 冬は食料が高く、毛皮は供給過多で安い
    summer = { food = 0.90 },
  },
  events = {
    -- /dyn_pricelevel set food 1.4 7d  のように期間付きで手動指定もできる
  },
  rampPerDay = 0.05,   -- 目標値へ 1 日 5% ずつ寄せる。切り替わった瞬間に価格を飛ばさない
}
```

季節やイベントで価格を動かしても、需給の履歴は汚れない。イベントが終われば `rampPerDay` で
元に戻る。ここが「需給と物価水準を分けておく」いちばん実務的な利点。

### 4.6 価格スタック（合成順序）

最終価格は次の順で合成する。**実装もこの順で 1 つの関数に閉じ込める。**
価格の決まり方が複数箇所に散らばると、後から誰も追えなくなるため。

| # | 段 | 掛かるもの | 節 |
|---|---|---|---|
| 1 | 相対価値 | `price_index[item]` | §6.1 |
| 2 | 通貨スケール | `× currency_scale` | §6.1 |
| 3 | **物価水準** | `× cpi_mult × category_mult[cat]` | §4.5 |
| 4 | 成長曲線補正 | `× income_mult`（買取側のみ） | §7 |
| 5 | **需給** | `× (S0/S)^e`（数量は積分） | §4.1〜4.2 |
| 6 | 個人補正 | `× personal_glut`（連投による追加減価） | §11.1 |
| 7 | 下限 | `max(…, レシピ原価 × craft_margin, base × min_mult)` | §5 |
| 8 | 上限 | `min(…, base × max_mult)` | §4.1 |
| 9 | 税 | 買取 `× (1 - tax_sell)` / 販売 `× (1 + tax_buy)` | §9.1 |
| 10 | 丸め | サーバーの通貨単位に合わせる | — |

3 段目（全体の水準）と 5 段目（個別の需給）が独立した軸で、これが今回の分離の要点。
4 段目は買取側にだけ掛かる（§7.3）。

**各段の乗数は `dyn_npc_tx.price_breakdown` に JSON で保存する。**

```json
{"index":1.00,"scale":0.82,"cpi":1.12,"cat":1.00,"income":0.97,
 "supply":0.61,"personal":1.00,"floor":null,"cap":null,"tax":0.70}
```

これがあると「あのとき何であんな値段だったのか」を後から完全に再現できる。
経済 Mod の運用で最も困るのが再現不能な価格クレームなので、この 1 列は必ず入れる。

## 5. レシピ原価と価格の下限

### 5.1 レシピの取り込み

各クラフト系リソースの Lua 定義から `output_item / output_qty / inputs` を抽出し、
`dyn_recipes` / `dyn_recipe_inputs` に投入するインポータを用意する。
取り込み対象の候補（フレームワーク確定後に確定）:

| フレームワーク | 想定リソース |
|---|---|
| RSGCore | `rsg-crafting`, `rsg-blacksmith`, `rsg-farming`, `rsg-cooking` |
| VORP | `vorp_crafting`, `vorp_inventory` の item 定義 |
| RedEM:RP | `redemrp_crafting` |

インポータは起動時に自動実行ではなく、管理コマンド（`/dyn_import_recipes`）で明示的に走らせ、
差分を出力してから反映する。レシピ表は変わりにくいので毎回パースする必要はない。

### 5.2 原価の再帰計算

```
cost(item) = Σ ( price_buy(input_i) * qty_i ) / output_qty
```

- 素材がさらにレシピを持つ場合は再帰。循環参照は探索済み集合で検出して打ち切る
- 最大深さ 6 程度で制限
- 素材が `dyn_items` に無い（＝NPC 価格が未定義）場合はその素材のみ `base_price` にフォールバック

### 5.3 下限価格への反映

```
floor(item) = max( P0 * min_mult , cost(item) * craft_margin )     -- craft_margin 既定 1.10
npc_buy_price = max( p(S) , floor(item) )
```

これで「素材を買って作って売ると必ず赤字」という状態が構造的に発生しなくなる。
逆に `cost * craft_margin` が `p(S)` を上回り続けるアイテムは
「クラフトしても NPC には売らずプレイヤーに売るべき品」として UI にマークを出す。

原価は素材価格が動くたびに変わるので、`mat_cost` は 15 分周期のバッチで再計算してキャッシュする。

---

## 6. サーバーごとの物価・所持金の差を吸収する（自動較正）

`base_price` を Mod 側にハードコードすると、導入先ごとに破綻する。
物価の絶対額・通貨の桁・プレイヤーの所持金・作物の収穫倍率・MOD 構成が全部違うため。

そこで価格を **「アイテム間の相対価値」と「そのサーバー固有のスケール」に分解**し、
後者を導入時と運用中に自動較正する。管理者が手で埋めるべき数値は原則ゼロを目指す。

### 6.1 価格の分解

```
P0[item] = price_index[item] * currency_scale * global_mult
```

| 要素 | 持ち主 | 意味 |
|---|---|---|
| `price_index[item]` | Mod（サーバー横断） | アイテム間の相対価値。「小麦 1 に対して鹿皮は 8」といった比だけを持つ。単位なし |
| `currency_scale` | サーバー固有・スカラー 1 個 | そのサーバーの物価水準。通貨の桁の違いを丸ごと吸収する |
| `global_mult` | サーバー固有・運用中に変動 | マネーサプライ制御（§6.7）が動かす補正。既定 1.0 |

`dyn_items` に `price_index` 列を追加し、`base_price` は導出値としてキャッシュする列に変える。
これで「サーバーごとに全アイテムの価格を書き直す」作業が **スカラー 1 個の較正**に縮む。

### 6.2 導入時の自動較正（bootstrap）

**A. 既存サーバーへの後乗せ** — 既存 NPC 店舗の固定価格表 `P_existing[i]` から逆算する:

```
currency_scale = median_i ( P_existing[i] / price_index[i] )
```

- 平均でなく**中央値**。一部だけ極端に安い／高く設定された品に引きずられないため
- 比の分布が広すぎる場合（IQR > 中央値の 50%）は、`price_index` がそのサーバーの価値観と
  合っていないというサインなので、較正を自動適用せず**外れ値アイテムの一覧を出力**する。
  管理者はそれを見て `price_index` を個別に上書きするか、そのまま承認する
- 出力例: `tobacco: 既存 4.00 / 指数から 12.30 (3.1x 安い) — 意図的な設定か要確認`

**B. 新規サーバー** — 基準アイテムを 1 つ選び、その希望価格を書くだけ:

```lua
Config.Anchor = { item = 'corn', price = 0.75 }   -- これだけで全アイテムの初期価格が決まる
```

### 6.3 初期所持金の自動決定

新規キャラの開始所持金も、金額をベタ書きせず**そのサーバーの物価から導出**する。

```lua
Config.Economy = {
  startingMode    = 'basket',   -- 'basket' | 'curve' | 'fixed'
  startingBaskets = 1.5,        -- 基準バスケット何個分から始めるか
  startingFixed   = 100,        -- startingMode='fixed' のときだけ使う
}
```

| モード | 計算 | 使いどころ |
|---|---|---|
| `basket` | `starting_cash = startingBaskets × basket_price` | 推奨。物価が動けば初期資金も自動で追従する |
| `curve` | `starting_cash = curve(day = 0)`（§7 の目標曲線の 0 日目） | §7 を使う場合。曲線の起点と初期資金が必ず一致する |
| `fixed` | 固定額 | 既存サーバーの現行値をそのまま踏襲したいとき |

`basket` が既定。「開始時にパン 3 個と弾薬 1 箱が買える」といった**体験の定義**が
サーバーの通貨の桁に依存しなくなる。

**既存キャラの所持金は絶対に触らない。** 適用されるのは新規作成キャラのみ。
物価が上がっても過去のプレイヤーに配り直したりはしない（§6.5 が物価側で吸収する役割）。

### 6.4 起動時の資産センサスと健全性チェック

較正の入力になる「サーバー全体の所持金」を、**サーバー起動時**と日次で棚卸しする。

```lua
Config.Census = {
  onStartup      = true,
  startupDelay   = 60,      -- 他リソースの読み込みと competing しないよう 60 秒待つ
  daily          = true,
  include        = { 'cash', 'bank' },   -- 集計に含める財布（§13 の確認事項）
  outlierMAD     = 5.0,     -- 中央値 + 5×MAD を超えたら外れ値
  driftTolerance = 0.25,    -- 総額のズレ許容 ±25%
}
```

#### 外れ値の扱い — 「除外はするが、無かったことにはしない」

飛び抜けた金額を持つプレイヤーは**必ずいる**前提で作る。

| 用途 | 外れ値を | 理由 |
|---|---|---|
| 中央値・分位数・時給の統計 | **除外する** | 1 人の大富豪にサーバー全体の物価を動かされないため |
| 総額（マネーサプライ）の照合 | **含める** | 存在する金は存在する。無視すると総額が合わなくなる |
| 運営への報告 | **一覧化する** | 複製バグ・不正・単に稼いだ人、の切り分けは人間がやる |

外れ値の判定は平均・標準偏差ではなく **中央値と MAD**（中央絶対偏差）を使う。
平均と標準偏差は外れ値自身に引きずられるので、大富豪が 1 人いるだけで基準が壊れる。

```
MAD      = median( |x_i - median(x)| )
outlier  ⟺ x_i > median(x) + outlierMAD × MAD × 1.4826
```

検出された外れ値は `dyn_wealth_outlier` に記録するだけで、**自動での没収・処罰は一切しない**。
正当に稼いだプレイヤーを Mod が勝手に罰する事故のほうが、経済の歪みよりはるかに重い。

#### 総額の健全性チェック — 「めちゃくちゃズレていなければ良い」

```
expected_total = 前回センサスの総額
               + ( Mod 経由の金の純増 )        -- dyn_npc_tx と国庫の記録から算出
               + ( 記録済みの外部イベント )     -- 管理者による付与など、申告があるもの

drift = | actual_total - expected_total | / max(expected_total, 1)
```

| drift | 判定 | 動作 |
|---|---|---|
| `≤ driftTolerance`（既定 25%） | 正常 | 較正を通常どおり実行 |
| `> driftTolerance` | 異常 | **較正を自動 hold**。警告ログと運営通知を出す |

hold の理由: ズレたまま較正すると、複製バグや管理者の大量付与の結果を
「正常な経済成長」と誤認して**全アイテムを値上げしてしまう**。
一度そうなると原因を消しても価格は戻らないので、疑わしい時点で止めるほうが安い。

```
[dyn_economy] 資産センサス異常: 総額が予測より +182% (予測 1,240,000 / 実測 3,498,000)
              Mod 外の入出金または複製の可能性があります。自動較正を保留しました。
              上位乖離: Arthur_M (+1,900,000) / John_S (+310,000)
              確認後 /dyn_census --accept で保留を解除してください。
```

**hold 中も §4 の需給変動は止めない。** 止めると店が全部固定価格になってゲームが壊れるため、
止めるのは「長期の較正レイヤー（§6.5〜6.7・§7）」だけにする。

#### 実装上の注意

- 金額の一覧取得は 1 クエリ。中央値と MAD は SQL でやりにくいので Lua 側で計算する
  （1 万件でもソート込みで数十 ms なので問題にならない）
- 起動直後はフレームワークの DB 接続が確立していないことがあるので `startupDelay` を必ず入れる
- センサス結果は `dyn_econ_snapshot` に追記し、前回値との差分を残す

### 6.5 所持金分布への追従（購買力を一定に保つ）

サーバーの総資産は時間とともに増える（新規プレイヤー流入・稼ぎの蓄積）。
物価が固定のままだと、古参にとって全アイテムが実質タダになる。

日次スナップショットを取り、**所持金の中央値**を基準に `currency_scale` を動かす:

```
purchasing_power(t) = money_median(t) / basket_price(t)
scale(t+1) = scale(t) * ( 1 + k * ( purchasing_power(t) / purchasing_power_target - 1 ) )
scale(t+1) = clamp( scale(t+1), scale(t) * 0.98, scale(t) * 1.02 )   -- 1 日 ±2% まで
```

- `money_median` は**直近 14 日にログインしたプレイヤー**のみを対象にする（放置キャラを除外）
- `basket_price` は代表アイテム 10〜20 品の加重平均（バスケットは固定して比較可能にする）
- 平均でなく中央値。少数の富豪がサーバー全体の物価を吊り上げないため
- `p90 / median` の比も記録しておくと、格差が開いたときに気づける

**「全部同じ倍率を掛けたら相対価格は変わらないので無意味では？」への回答**:
シンクとソースで連動の強さを変えることで、意味のある効果になる。

```
npc_sell_price（NPC が売る = 金のシンク）  … scale に完全連動   （係数 1.0）
npc_buy_price （NPC が買う = 金のソース）  … 連動を弱める       （係数 β = 0.5）
```

サーバーが豊かになるほど「買うものは高くなるが、稼ぎは同じだけ上がらない」。
金蛇口が自動で締まり、際限のないインフレが止まる。β は 0.3〜0.7 で調整する。

### 6.6 収集効率アンカー（サーバー差の本命）

サーバーによって作物の収穫倍率・動物のスポーン量・スクリプトの効率が全く違う。
つまり **「そのアイテムが 1 時間に何個手に入るか」がサーバー固有**であり、
ここを実測しない限り「農業で単価の高い作物だけが最適」は防げない。

決めるべきは単価ではなく**時給**にする:

```
R_i     = そのアイテムを扱うプレイヤーの、プレイ時間あたり NPC 売却数（個/時）
hourly_i = R_i * npc_buy_price(i)          -- そのアイテムだけをやり続けた場合の時給
```

`R_i` は `dyn_npc_tx` の売却数を、そのプレイヤーの当日プレイ時間で割って推定する
（`dyn_item_yield` に日次集計）。目標時給バンドから外れたら `price_index` を日次補正:

```
if hourly_i > W_hi:  price_index[i] *= max(0.97, W_hi / hourly_i)   -- 1 日 -3% まで
if hourly_i < W_lo:  price_index[i] *= min(1.03, W_lo / hourly_i)   -- 1 日 +3% まで
```

- `W_lo / W_hi` は**サーバー内の実測中央時給から自動で決める**（例: 中央値の 0.7〜1.3 倍）。
  絶対額で書かないので、どのサーバーでもそのまま動く
- 標本が薄いと暴れるので、`unique_sellers >= 5` かつ `playtime_hours >= 20` を満たす
  アイテムだけ補正する。それ以外は据え置き
- 収穫倍率を 3 倍にする MOD を入れても、数日で価格が 1/3 側に寄って釣り合う

**これが「回収量が多く単価も高いものだけ栽培される」への根本対策**であり、
同時にサーバー間の差を人手なしで吸収する仕組みでもある。
§4 の仮想在庫が「短期（数時間〜数日）の需給」を、ここが「長期（数週間）の均衡」を担当する。

### 6.7 マネーサプライの PI 制御

最後の安全網。全体の金の総量の増え方そのものを目標値に寄せる。

```
g      = ( money_total(t) - money_total(t-1) ) / money_total(t-1)     -- 日次成長率（実測）
e      = g - g_target                                                  -- g_target 既定 0.00
I      = clamp( I + e , -0.5, 0.5 )                                    -- 積分項（ワインドアップ防止）
global_mult_buy  = clamp( 1 - (Kp*e + Ki*I) , 0.70, 1.30 )   -- NPC 買取（ソース）を絞る
global_mult_sell = clamp( 1 + (Kp*e + Ki*I) , 0.70, 1.30 )   -- NPC 販売（シンク）を上げる
```

`Kp = 2.0, Ki = 0.5` 程度から。インフレが続けば稼ぎが減り物価が上がるので自動で収束する。
デフレ（プレイヤーが減って金が消える）側にも同じだけ効く。

### 6.8 追加テーブル（§3 に加える）

```sql
CREATE TABLE IF NOT EXISTS dyn_econ_config (
  k           VARCHAR(64) NOT NULL PRIMARY KEY,   -- currency_scale, global_mult_buy, ...
  v           DECIMAL(18,6) NOT NULL,
  updated_at  DATETIME NOT NULL
);

CREATE TABLE IF NOT EXISTS dyn_econ_snapshot (
  snapshot_at    DATETIME NOT NULL PRIMARY KEY,
  money_total    DECIMAL(18,2) NOT NULL,
  money_median   DECIMAL(14,2) NOT NULL,          -- 直近14日ログイン者のみ
  money_p90      DECIMAL(14,2) NOT NULL,
  active_players INT NOT NULL,
  basket_price   DECIMAL(14,4) NOT NULL,
  currency_scale DECIMAL(14,6) NOT NULL,
  median_hourly  DECIMAL(14,4) NULL               -- 実測の中央時給（W_lo/W_hi の元）
);

CREATE TABLE IF NOT EXISTS dyn_item_yield (
  item            VARCHAR(64) NOT NULL,
  day             DATE NOT NULL,
  qty_sold        INT NOT NULL,
  unique_sellers  INT NOT NULL,
  playtime_hours  DECIMAL(10,2) NOT NULL,         -- 売却者の当日合計プレイ時間
  est_rate        DECIMAL(12,4) NOT NULL,         -- R_i = qty_sold / playtime_hours
  est_hourly      DECIMAL(12,2) NOT NULL,         -- R_i * npc_buy_price
  PRIMARY KEY (item, day)
);
```

```sql
CREATE TABLE IF NOT EXISTS dyn_wealth_outlier (
  detected_at DATETIME      NOT NULL,
  identifier  VARCHAR(64)   NOT NULL,
  amount      DECIMAL(16,2) NOT NULL,
  median_ref  DECIMAL(16,2) NOT NULL,          -- 検出時点の中央値
  mad_score   DECIMAL(10,3) NOT NULL,          -- 中央値から MAD 何個分離れていたか
  reviewed    TINYINT(1)    NOT NULL DEFAULT 0,-- 運営が確認済みか
  PRIMARY KEY (detected_at, identifier)
);
```

`dyn_items` への追加列: `price_index DECIMAL(12,4)`, `pinned TINYINT(1) DEFAULT 0`。
`dyn_npc_tx` への追加列: `price_breakdown JSON`（§4.6）、`tax_amount DECIMAL(12,2)`（§9.1）。

### 6.9 較正の安全装置

自動較正は「静かに経済を壊す」事故が起きやすいので、以下を必ず入れる。

| 装置 | 内容 |
|---|---|
| 日次・小刻み・クランプ | 全ての較正は 1 日 1 回、変化幅に上限（scale ±2%、index ±3%、mult ±30%） |
| ドライラン | `/dyn_calibrate --dry-run` で「何がどれだけ動くか」の差分表だけ出す。適用は別コマンド |
| ピン留め | `dyn_items.pinned = 1` のアイテムは較正対象外。ストーリー上の固定価格品や換金専用品に使う |
| キルスイッチ | `Config.Calibration.enabled = false` で §6.7〜6.7 を全停止。§4 の需給変動だけが残る |
| 監査ログ | 較正のたびに変更前後を `dyn_econ_snapshot` と差分ログに残し、いつでも巻き戻せる |
| 標本下限 | 標本が閾値未満のアイテム・日は較正しない。導入直後は §6.2 の初期値のまま動く |

### 6.10 導入手順への影響

新規サーバーでも既存サーバーでも、管理者の作業は次の 3 つだけになる。

1. `Config.Anchor`（新規）を 1 行書く、または既存店舗の価格表を指定する（後乗せ）
2. `/dyn_calibrate --dry-run` を見て、外れ値アイテムだけ手で直す
3. 2 週間ほど動かしてから較正を有効化する（それまでは実測データが溜まらない）

---

## 7. 目標成長曲線ターゲティング（既定 OFF）

「サーバー開始から ○日で、プレイヤーはだいたい △ くらい稼いでいてほしい」という**目標曲線を宣言し、
実測がそこからズレたら価格側を自動で寄せる**機能。§6 の較正が「サーバー間の差を埋める」のに対し、
これは「運営が意図した成長速度に乗せる」ためのもの。

**この機能は既定で OFF。**（§7.7 のトグル表）
経済に最も強く介入するレイヤーなので、他が安定してから有効にする前提で作る。

### 7.1 目標曲線の宣言

```lua
Config.Progression = {
  enabled     = false,        -- ★既定 OFF
  basis       = 'playtime',   -- 'playtime' = プレイ時間基準 / 'calendar' = 加入からの経過日数
  hoursPerDay = 2.0,          -- basis='playtime' のとき「1 日」を何時間とみなすか
  metric      = 'earned',     -- 'earned' = 累計獲得額 / 'networth' = 現在の総資産

  curve = {                   -- ここが「○日でこのくらい」の宣言そのもの
    { day = 1,  value =    50 },
    { day = 3,  value =   180 },
    { day = 7,  value =   500 },
    { day = 14, value =  1200 },
    { day = 30, value =  3000 },
    { day = 90, value = 12000 },
  },

  tolerance    = 0.15,        -- ±15% の不感帯。この中なら何もしない
  maxDailyAdj  = 0.03,        -- 1 日あたりの補正上限 ±3%
  minSamples   = 5,           -- コホートの最低人数。これ未満は無視
  sinkCoupling = 0.0,         -- >0 なら NPC 販売価格も逆向きに動かす（0〜1）
  bucketWeight = { early = 2.0, mid = 1.0, late = 0.5 },  -- どの層を優先して合わせるか
}
```

曲線の点と点の間は **log-log 線形補間**。成長は逓減するのが自然なので、直線補間より素直に繋がる。

**`basis` の選び方**:

| 値 | 「1 日」の意味 | 向いている運営 |
|---|---|---|
| `playtime` | 実プレイ 2 時間 = 1 日（`hoursPerDay`） | 推奨。週末だけ来る人も同じ体験曲線に乗る |
| `calendar` | 初回ログインからの実日数 | 「開始 1 か月でこの装備」のような季節・シーズン運営 |

`calendar` は放置勢が置き去りになる代わり、廃人の突出を抑えやすい。既定は `playtime`。

**`metric` の選び方**: `earned`（累計獲得額）を推奨。`networth` は「使った分」で下がるので、
散財するプレイヤーがいるとサーバー全体の価格が上がってしまい、制御として素直でない。

### 7.2 実測（コホート中央値）

プレイヤーを在籍度でバケットに分け、**各バケットの中央値**を実測値とする。
個人を狙い撃ちせず、その層の「ふつうの人」がどこにいるかだけを見る。

| バケット | 範囲（basis の単位） | 重み |
|---|---|---|
| early | 0〜7 日 | 2.0 |
| mid | 7〜30 日 | 1.0 |
| late | 30 日〜 | 0.5 |

- 中央値なので、上澄みの廃人 1 人がサーバー全体の価格を動かすことはない
- `minSamples` 未満のバケットは計算から除外（サーバー開設直後は late が空なので自然にそうなる）
- 直近 14 日にログインしていないプレイヤーは除外

### 7.3 補正の計算

比較するのは比なので、**対数で扱う**（「2 倍稼ぎすぎ」と「半分しか稼げていない」を対称に扱うため）。

```
r_b = median_value(b) / target( day(b) )          -- バケット b の達成率
E   = Σ ( w_b · n_b · ln r_b ) / Σ ( w_b · n_b )  -- 重み付き対数平均の誤差

if |E| <= ln(1 + tolerance):  補正なし（不感帯）

income_mult ← income_mult · exp( -Kp · E )
income_mult ← clamp( income_mult, 前日値 ± maxDailyAdj )
income_mult ← clamp( income_mult, 0.50, 2.00 )    -- 絶対的な安全域
```

`Kp = 0.5` 程度から。目標の 2 倍稼がれていても 1 日で半減はせず、±3%/日で数週間かけて寄せる。

**適用先**: `npc_buy_price`（プレイヤーが NPC に売る＝金のソース）にのみ掛ける。
販売価格にも同率で掛けると相殺されて効かない。物価を動かしたい場合だけ `sinkCoupling` を上げ、
`npc_sell_price` を `income_mult^(-sinkCoupling)` で逆向きに動かす。

### 7.4 §6 の較正との優先順位（重要）

§6.7 のマネーサプライ PI 制御と本機能は、どちらも同じ `global_mult` を奪い合うので、
**両方を素のまま有効にすると発振する**。次のように役割を分ける。

| Progression | マネーサプライ PI（§6.7） | 動作 |
|---|---|---|
| OFF | ON | §6.7 が主。金の総量の成長率を目標に寄せる |
| ON | 自動で**ガード役に降格** | Progression が `global_mult` を決め、§6.7 は「暴走したときだけ効く上下限」として働く |
| ON | OFF | Progression のみ。最もシンプル |

`§6.6` の収集効率アンカーは `price_index`（アイテム**間**の相対価格）を動かし、
Progression は `global_mult`（**全体**の水準）を動かすので、この 2 つは干渉しない。併用してよい。

### 7.5 追加テーブル（§3 に加える）

```sql
CREATE TABLE IF NOT EXISTS dyn_player_progress (
  identifier      VARCHAR(64) NOT NULL PRIMARY KEY,
  first_seen      DATETIME NOT NULL,
  last_seen       DATETIME NOT NULL,
  playtime_hours  DECIMAL(12,2) NOT NULL DEFAULT 0,
  earned_total    DECIMAL(16,2) NOT NULL DEFAULT 0,   -- NPC 売却＋委託所売上の累計
  spent_total     DECIMAL(16,2) NOT NULL DEFAULT 0,
  networth        DECIMAL(16,2) NOT NULL DEFAULT 0,   -- 現金＋銀行（§13 の確認事項）
  updated_at      DATETIME NOT NULL,
  INDEX idx_last_seen (last_seen)
);

CREATE TABLE IF NOT EXISTS dyn_progress_curve (       -- 曲線を DB に置き、再起動なしで編集可能にする
  day_index    DECIMAL(8,2) NOT NULL PRIMARY KEY,
  target_value DECIMAL(16,2) NOT NULL
);

CREATE TABLE IF NOT EXISTS dyn_progress_eval (        -- 判断の履歴。なぜその倍率になったかを後から追える
  evaluated_at DATETIME NOT NULL,
  bucket       VARCHAR(16) NOT NULL,
  n            INT NOT NULL,
  median_value DECIMAL(16,2) NOT NULL,
  target_value DECIMAL(16,2) NOT NULL,
  ratio        DECIMAL(10,4) NOT NULL,
  applied_mult DECIMAL(10,4) NOT NULL,
  coverage     DECIMAL(6,3) NULL,
  PRIMARY KEY (evaluated_at, bucket)
);
```

### 7.6 到達可能性の検査（coverage）

**価格を動かしても届かない場合がある。** クエスト報酬・給料・強盗・他 Mod の収入など、
この Mod が触れない収入源が大きいと、いくら NPC 買取を絞っても目標に乗らない。

```
coverage = ( Mod 経由の収入 ) / ( そのプレイヤーの総収入増加分 )
```

- `coverage < 0.5` のバケットが続く場合は、**補正を打ち切って警告を出す**
  （「Day 1〜7 層の収入の 68% が Mod 外です。給料・クエスト報酬側の調整が必要」）
- 無理に倍率を下げ続けると、Mod が扱う品目だけ極端に安くなり経済が歪むため、
  ここで止めるのは機能ではなく**安全装置**として必須

### 7.7 較正レイヤーのオン/オフ一覧

全レイヤーを独立に切れるようにする。上から順に介入が強くなる。

| レイヤー | 設定キー | 既定 | 切ったときの挙動 |
|---|---|---|---|
| 需給による価格変動（§4） | `Config.Dynamic.enabled` | **ON** | 全て固定価格になる。Mod の意味がほぼ無くなる |
| レシピ原価の下限（§5） | `Config.Recipes.enabled` | **ON** | 下限は `min_mult` のみ。作ると赤字の品が出うる |
| 導入時 bootstrap 較正（§6.2） | `Config.Calibration.bootstrap` | **ON** | `price_index × Config.Anchor` の初期値のまま |
| 所持金追従（§6.5） | `Config.Calibration.wealth` | OFF | 物価が固定され、長期的にインフレする |
| 収集効率アンカー（§6.6） | `Config.Calibration.yield` | OFF | 高効率アイテムの是正が §4 の短期変動のみになる |
| マネーサプライ PI（§6.7） | `Config.Calibration.moneySupply` | OFF | 金の総量の制御なし |
| **目標成長曲線（§7）** | `Config.Progression.enabled` | **OFF** | 本節の機能が全停止。他レイヤーは影響を受けない |
| 物価水準レイヤー（§4.5） | `Config.PriceLevel.enabled` | **ON** | `cpi_mult` が 1.0 に固定。需給変動だけが効く |
| 委託所（§8） | 別リソース | — | リソースを起動しなければよい |
| 税の記帳（§9.1） | `Config.Treasury.enabled` | **ON** | スプレッド分は従来どおり消滅。プレイヤー体験は同じ |
| 組合・補助金（§9） | `Config.Guilds.enabled` | OFF | 申請も補助も動かない。国庫は貯まり続ける |

すべて `dyn_econ_config` にも同じキーを置き、**再起動なしで管理コマンドから切り替えられる**ようにする。
事故ったときに真っ先に必要になるのはコンフィグ編集ではなく、その場で止める手段のため。

```
/dyn_toggle progression off        -- 即時停止。global_mult は 1.0 へ 1 日 3% で戻る
/dyn_toggle guilds on              -- 組合と補助金を有効化（§9）
/dyn_census                        -- 資産センサスを手動実行（§6.4）
/dyn_toggle list                   -- 現在のオン/オフ状態
```

停止時に倍率を即座に 1.0 に戻すと価格が飛ぶので、**ランプダウン**（1 日 3% ずつ戻す）にする。

### 7.8 診断コマンド

```
/dyn_progress
```

```
基準: playtime (2.0h = 1日) / 指標: earned / 状態: ON

バケット   人数   経過日   実測中央値      目標      達成率   重み
early       23     3.4       412          215      1.92x     2.0
mid         14    18.2      2,840        1,780     1.60x     1.0
late         6    52.0      9,100        6,400     1.42x     0.5

重み付き対数平均誤差 E = +0.548  (目標比 +73%)
不感帯 ±15% → 超過。 income_mult 1.000 → 0.970 (下限クランプ -3%/日)
この調子なら目標帯に入るまで 約 18 日
coverage: early 0.81 / mid 0.74 / late 0.62   … 良好

--dry-run 中: 適用していません。/dyn_progress --apply で反映
```

`--dry-run` を既定にし、明示的に `--apply` するまで反映しない。日次バッチも同じ計算を使う。

### 7.9 この機能の限界（把握したうえで使う）

- **全員を曲線に乗せることはできない。** 中央値を寄せるだけで、廃人と月イチ勢の差は残る（残すべき）
- **曲線を途中で大きく変えない。** 変えた瞬間に大きな誤差が出て、数週間ずっと補正が掛かり続ける。
  変更時は `income_mult` を 1.0 にリセットしてから始める
- **サーバー人口が少ないと機能しない。** `minSamples` を満たさず、ほぼ常に補正なしになる。
  16 人規模なら early/mid の 2 バケットに減らすか、`minSamples = 3` まで下げる
- **これは経済の調整であってゲームデザインではない。** 「7 日で 500」が体験として妥当かどうかは
  この機能では判断できない。数字が合っていてもつまらない可能性は普通にある

---

## 8. プレイヤー間取引の仲介（委託所）

手渡し取引は記録できないので、**記録できる取引のほうが得になる**設計にする。禁止はしない。

### 8.1 フロー

```
1. 出品   売り手が委託所 NPC で item / qty / 希望単価 を指定
          → 現物をインベントリから引き上げ dyn_market_escrow へ（二重売却の防止）
          → dyn_market_orders に status='open' で登録
2. 閲覧   買い手はメニューで item を検索。安い順に並ぶ。
          参考情報として NPC 買取価格・NPC 販売価格・直近 24h の VWAP を同時表示
3. 約定   買い手が購入 → 代金を引き落とし、手数料 3% を差し引いて売り手の口座へ入金
          → escrow から買い手インベントリへ現物を移す
          → dyn_market_trades に記録し、qty を減算（0 で status='filled'）
4. 期限   expires_at を過ぎた open 注文は現物を売り手へ返却し status='expired'
```

### 8.2 価格エンジンへのフィードバック

委託所の約定は**仮想在庫を動かさない**（プレイヤー間で物が移動しただけで市場から消えていない）。
ただし `dyn_price_history.player_vwap` に反映し、次の 2 つに使う:

- **UI**: 「NPC 買取 1.20 / 実勢 1.85」のように並べて表示し、NPC に売る損を可視化する
- **基準価格の緩やかな補正（任意・既定オフ）**: 実勢価格が長期間 `P0` から乖離した場合に
  `P0` 自体を日次で 1% ずつ寄せる。初期運用では切っておき、経済が安定してから検討する

### 8.3 手数料設計

| 項目 | 既定値 | 意図 |
|---|---|---|
| 出品手数料 | 0 | 出品のハードルを下げる |
| 約定手数料 | 3%（売り手負担） | NPC スプレッド 30% より圧倒的に有利 |
| 出品上限 | 1 人 20 件 | DB とメニューの肥大化防止 |
| 有効期限 | 72 時間 | 死んだ注文の滞留防止 |

---

## 9. 税収と組合（ギルド）補助金

NPC スプレッドと委託所手数料で徴収した金を**消滅させず国庫に記帳し**、
プレイヤーが自主的に立ち上げた組合への補助金として還流させる仕組み。

### 9.1 スプレッドを税として記帳する

§4.4 のスプレッドは、現状ただ金が消えるだけ。これを明示的な税に置き換える。

```
fair_value = §4.6 の 8 段目までの価格（税抜きの「公正価格」）

プレイヤーが NPC に売る:  受取 = fair_value × (1 - tax_sell)    差額 → 国庫
プレイヤーが NPC から買う: 支払 = fair_value × (1 + tax_buy)    差額 → 国庫
```

`tax_sell + tax_buy` が従来の `npc_spread` に相当する。
**プレイヤーが払う額・受け取る額は今までと 1 円も変わらない。**
変わるのは「消えていた」が「国庫に入って行き先が見える」ようになることだけ。

委託所の約定手数料（§8.3 の 3%）も同じく国庫に入る。

税率は品目やカテゴリごとに変えられる。「贅沢品は税率高め、生活必需品は低め」といった
運営の意思表示がそのまま経済の形になる。

### 9.2 国庫はマネーサプライの外に置く（重要）

国庫の残高は誰の財布にも入っていないので、§6.7 と §7 の計算では**流通量から除外する**。

```
M_circulating = Σ プレイヤーの所持金        ← 制御器が見るのはこちら
M_treasury    = 国庫残高                    ← 流通していない。別枠で管理
```

補助金を出すと `M_treasury → M_circulating` に移る。**新規発行ではない**ので、
インフレ要因としては小さく、制御器は「シンクが一時的に弱まった」として扱えばよい。

ただし放っておくと国庫は永久に積み上がり、実質的に強いデフレ圧になる。
そこで**国庫の目標残高**を決め、超過分は自動で補助金予算に回す。

```lua
Config.Treasury = {
  enabled       = true,    -- 既定 ON（記帳するだけ。ゲームの挙動は変わらない）
  reserveMonths = 3.0,     -- 月間税収の 3 か月分を準備金として保持
  -- 準備金を超えた分が §9.4 の補助金予算の原資になる
}
```

### 9.3 組合の設立（自己申告 → 運営承認）

**NPC は置かない。** プレイヤーが自分たちで名乗り、市役所に申請書を出す。

```
1. 発起人が /guild apply
   … 名称・カテゴリ・目的・初期メンバー（既定 3 名以上）を入力
   → status = 'pending'。市役所の掲示板メニューに申請が載る

2. 運営が内容を確認する（ゲーム内で市役所窓口の RP をしてもよい）

3. /guild approve <id>  または  /guild reject <id> <理由>
   ★ 承認できるのは運営のみ。自動承認は無し

4. status = 'approved' になって初めて補助金の対象になる
```

- **設立そのものは自由。** 承認されなくても組合として名乗り活動できる。補助金が出ないだけ
- 承認は取り消せる（`/guild revoke`）。活動のない組合は 90 日で自動失効
- 却下理由は申請者に通知され、修正して再申請できる

| カテゴリ | 例 | 補助対象になりうるもの |
|---|---|---|
| `farming` | 農協 | 種、肥料、農具の修理費 |
| `mining` | 鉱山組合 | ツルハシ、ダイナマイト、灯油 |
| `hunting` | 猟師組合 | 弾薬、罠、皮なめし材 |
| `crafting` | 職人ギルド | 素材、炉の燃料 |
| `ranching` | 畜産組合 | 飼料、獣医費 |

カテゴリは `Config.Guilds.categories` で自由に追加できる。

### 9.4 補助金の出し方 — 2 モード

**モード B（実績払い・既定・推奨）**

週次で、その週に実際に**生産・出荷した実績**に応じて後から支払う。

```
補助額 = Σ ( 出荷量_i × unit_amount_i )     … 対象品目ごとの単価補助
上限   = min( 1人1日上限 × 7 , 組合の週次上限 , 予算残 )
```

農協なら「その週に出荷した作物 1 個につき ○」。種を買っただけでは出ないので、
**買って売り戻すだけの裁定が成立しない。**

**モード A（購入時割引・即時）**

承認済み組合のメンバーが対象アイテムを NPC から買うとき、支払いの X% を国庫が負担する。
体験は分かりやすいが濫用に弱い（§9.5）ので、使うなら上限を厳しくする。

```lua
Config.Guilds = {
  enabled = false,               -- ★既定 OFF
  subsidy = {
    mode        = 'accrual',     -- 'accrual'（実績払い・既定） | 'instant'（購入時割引）
    payoutDay   = 'monday',
    monthlyBudgetRatio = 0.40,   -- 直近3か月の税収平均の 40% を月次予算にする
  },
}
```

### 9.5 濫用対策

モード A の穴は明確: **組合を作る → 補助で安く種を買う → その種を売る → 差額が利益。**

モード A を使う場合の必須対策:

- 補助を受けた個体に metadata `subsidized = true` を付ける
- `subsidized` な品は **NPC 売却不可・委託所出品不可**
- 消費（植える・使う）でフラグは消える。**生産物には引き継がない**
- それでも抜け道は残るので、1 人 1 日あたりの補助上限を厳しく設定する

モード B（実績払い）は、そもそも「実際に出荷した量」にしか払わないので、この穴が構造的に無い。
既定を B にしているのはこのため。

共通の制約:

| 制約 | 既定値 |
|---|---|
| 1 人 1 日あたりの補助上限 | §7 の目標曲線の day 1 相当額（無ければバスケット 1 個分） |
| 組合ごとの月次上限 | 月次予算 ÷ 承認済み組合数 |
| 全体の月次予算 | 直近 3 か月の税収平均 × 40% |
| 加入から補助対象になるまでの待機 | 7 日（作って即もらうのを防ぐ） |
| 兼任 | 1 キャラ 1 組合まで |
| 国庫が準備金を割ったら | 補助を自動停止。`/guild status` に停止理由を表示 |

**多重アカウントで組合を量産する動きは、承認が運営の手動である以上そこで止まる。**
「承認を人間がやる」という設計判断の実質的な意味はここにある。自動承認にすると
上の制約をいくら積んでも抜けられる。

### 9.6 テーブル

```sql
CREATE TABLE IF NOT EXISTS dyn_treasury_ledger (
  id            BIGINT AUTO_INCREMENT PRIMARY KEY,
  created_at    DATETIME NOT NULL,
  direction     ENUM('in','out') NOT NULL,
  source        VARCHAR(32) NOT NULL,      -- npc_tax_sell / npc_tax_buy / market_fee / subsidy
  amount        DECIMAL(14,2) NOT NULL,
  balance_after DECIMAL(16,2) NOT NULL,
  ref_type      VARCHAR(32) NULL,          -- dyn_npc_tx / dyn_market_trades / dyn_subsidy_payouts
  ref_id        BIGINT NULL,
  note          VARCHAR(255) NULL,
  INDEX idx_time (created_at),
  INDEX idx_source_time (source, created_at)
);

CREATE TABLE IF NOT EXISTS dyn_guilds (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  name          VARCHAR(64) NOT NULL UNIQUE,
  category      VARCHAR(32) NOT NULL,
  purpose       VARCHAR(255) NULL,
  founder       VARCHAR(64) NOT NULL,
  status        ENUM('pending','approved','rejected','revoked','dissolved') NOT NULL DEFAULT 'pending',
  applied_at    DATETIME NOT NULL,
  decided_at    DATETIME NULL,
  decided_by    VARCHAR(64) NULL,          -- 承認/却下した運営の識別子（監査用）
  reject_reason VARCHAR(255) NULL,
  last_active   DATETIME NULL,             -- 90日無活動で自動失効の判定に使う
  INDEX idx_status (status)
);

CREATE TABLE IF NOT EXISTS dyn_guild_members (
  guild_id    INT NOT NULL,
  identifier  VARCHAR(64) NOT NULL,
  role        ENUM('founder','officer','member') NOT NULL DEFAULT 'member',
  joined_at   DATETIME NOT NULL,
  PRIMARY KEY (guild_id, identifier),
  UNIQUE KEY uq_one_guild (identifier),    -- 1 キャラ 1 組合
  CONSTRAINT fk_gm_guild FOREIGN KEY (guild_id) REFERENCES dyn_guilds(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS dyn_guild_subsidy_rules (
  guild_id    INT NOT NULL,
  item        VARCHAR(64) NOT NULL,
  mode        ENUM('accrual','instant') NOT NULL DEFAULT 'accrual',
  rate        DECIMAL(5,3) NULL,           -- instant: 支払いの何割を国庫が負担するか
  unit_amount DECIMAL(12,2) NULL,          -- accrual: 出荷 1 個あたりの補助額
  daily_cap   DECIMAL(12,2) NULL,
  enabled     TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (guild_id, item),
  CONSTRAINT fk_gsr_guild FOREIGN KEY (guild_id) REFERENCES dyn_guilds(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS dyn_subsidy_payouts (
  id          BIGINT AUTO_INCREMENT PRIMARY KEY,
  guild_id    INT NOT NULL,
  identifier  VARCHAR(64) NOT NULL,
  item        VARCHAR(64) NOT NULL,
  qty         INT NOT NULL,
  amount      DECIMAL(12,2) NOT NULL,
  mode        ENUM('accrual','instant') NOT NULL,
  period      VARCHAR(16) NULL,            -- accrual: '2026-W37'
  paid_at     DATETIME NOT NULL,
  INDEX idx_guild_period (guild_id, period),
  INDEX idx_ident_time (identifier, paid_at)
);
```

### 9.7 コマンド

**プレイヤー**

```
/guild apply <名称> <カテゴリ>     申請を出す
/guild info [id]                   組合の情報・承認状態・今期の補助実績
/guild join <id> / leave           加入・脱退
/guild subsidy                     今週の補助見込み額と残り上限
```

**運営**

```
/guild list pending                承認待ちの一覧
/guild approve <id>                承認
/guild reject <id> <理由>          却下（理由は申請者に通知）
/guild revoke <id> <理由>          承認の取り消し
/treasury                          国庫残高・今月の税収内訳・補助支出
/treasury budget [金額]            月次予算の確認・上書き
```

### 9.8 トグル

| 機能 | 設定キー | 既定 | 切ったときの挙動 |
|---|---|---|---|
| 税の記帳 | `Config.Treasury.enabled` | **ON** | スプレッド分は従来どおり消滅する。プレイヤー体験は同じ |
| 組合・補助金 | `Config.Guilds.enabled` | **OFF** | 申請も補助も一切動かない。国庫は貯まり続ける |
| 補助モード | `Config.Guilds.subsidy.mode` | `accrual` | — |

税の記帳だけ先に ON にしておくと、**組合を実装する前に「どれだけ税が集まるのか」の
実測値が手に入る**。補助金の予算規模はその数字を見てから決めればよい。

---

## 10. 外部リソース向け API（exports）

既存の店舗リソースからは、この 4 つを呼ぶだけで動的価格に乗る。

```lua
-- 見積り（在庫は動かさない）
exports['dyn_economy']:QuoteSell(item, qty)  --> { total, unitAvg, priceNow }
exports['dyn_economy']:QuoteBuy(item, qty)   --> { total, unitAvg, priceNow }

-- 確定（在庫を動かし dyn_npc_tx に記録する）
exports['dyn_economy']:CommitSell(identifier, item, qty, shopId)  --> { ok, total, unitAvg }
exports['dyn_economy']:CommitBuy(identifier, item, qty, shopId)   --> { ok, total, unitAvg }
```

`Quote` と `Commit` を分けるのは、メニュー表示と実際の決済の間に価格が動いても
表示額で確定させない（＝同時売却による抜け穴を作らない）ため。`Commit` の戻り値が正。

### 10.1 決済の順序（実装済み）

順序を間違えると金か現物が増える。ブリッジの `txflow.lua` はこの順に固定してある。

| 方向 | 順序 |
|---|---|
| 売却 | 見積り → 所持数の確認 → **現物を引く** → 価格を確定 → 入金 |
| 購入 | 見積り → 所持容量の確認 → 所持金の確認 → 価格を確定 → 支払い → **現物を渡す** |

- 売却で現物を先に引くのは、引けなければ何も起きていない状態で止まれるから
- インベントリ操作は yield する。**所持金の確認と価格の確定の間で yield してはいけない**
  （確認した残高と実際に引く額がズレる）。yield する所持容量の確認を先に済ませる
- 途中で失敗したら、金は返し、現物は戻し、`VoidCommit` で仮想在庫と取引記録も戻す。
  取引の行は消さず `voided = 1` を立てる。何が起きたかを残すほうが後の調査で役に立つ

### 10.2 既存店舗への組み込み方針

**フレームワークは VORP に確定**（vorp_core 3.3 / vorp_inventory 4.5）。
ブリッジは `resources/dyn_economy_bridge` に実装済み。他フレームワーク向けは書かない。

店舗リソース側は、固定価格の計算と決済を次の 1 行に置き換える。

```lua
local res = exports['dyn_economy_bridge']:SellToNpc(source, item, qty, shopId)
local res = exports['dyn_economy_bridge']:BuyFromNpc(source, item, qty, shopId)
```

所持金・インベントリの操作と、失敗時の巻き戻しはブリッジ側で完結する。

アダプタが提供すべき関数は 4 つだけ:
`GetIdentifier(src)` / `GetMoney(src)` / `AddMoney(src, amt)` / `RemoveMoney(src, amt)`
＋ `AddItem` / `RemoveItem` / `GetItemCount`。

較正（§6）のために、さらに 2 つを追加で要求する:
`GetAllPlayersMoney()`（オフライン含む全キャラの所持金一覧。DB 直読みで可）と `GetPlaytimeSeconds(identifier, since)`（プレイ時間。取れないフレームワークでは 自前の接続ログテーブルで代替する）。


### 10.3 他リソースとの干渉（VORP エコシステム）

実際に配布物のソースを読んで確認した干渉点と、その回避方法。
検出はブリッジの `server/compat.lua` が起動時に行う。**他リソースの設定は書き換えない** —
勝手に他人のリソースを変更するほうが事故が大きいので、こちらが降りるか警告を出すかに留める。

| 相手 | 何が起きるか | 対処 | 自動検出 |
|---|---|---|---|
| **vorp_stores** の `RandomPrices = true` | 再起動のたびに価格をランダムに振り直す。需給の結果が毎回消える | vorp_stores 側で `false` にする | ○ 起動時に警告 |
| **vorp_stores** の `DynamicStore = true` | 店舗ごとの在庫上限を独自に持ち、仮想在庫と二重管理になる | vorp_stores 側で `false` にする | ○ 起動時に警告 |
| **vorp_inventory に未登録の品目** | 売買のたびに `Item [x] does not exist in DB.` がコンソールに出続け、`canCarryItem` が常に false を返して購入が全部失敗する | `items` テーブルに追加するか品目から外す | ○ 起動時に自動無効化 |
| **武器** | 武器は `items` ではなく `loadout` 側で管理され、`addItem` / `subItem` が効かない | 武器は扱わない | ○ 未登録として自動無効化 |
| **劣化アイテム**（`maxDegradation > 0`） | 価格エンジンは個体の劣化度を見ないので、状態の悪い品を満額で売れてしまう（vorp_stores は `percentage / 100` を価格に掛けている） | 既定で除外。承知のうえで扱うなら `allowDegradable = true` | ○ 起動時に自動無効化 |
| **`OnItemCreated` / `OnItemRemoved` を listen する他スクリプト**（クエスト進行・ログ・アンチチート） | 決済の巻き戻しでイベントが再発火し、二重にカウントされる | 通常の売買では発火させ（普通の店と同じ挙動）、巻き戻しだけ `allow = true` で抑止する | — 実装済み |
| **vorp_banking** | 所持金が `character.money` ではなく `bank_users` テーブルにある | §6.4 のセンサスは両方を合算しないと総額の drift が常に大きく出る | — Phase 5.6 で対応 |
| **gold / ROL 建ての品目** | vorp_stores は品目ごとに cash / gold を選べるが、価格エンジンは単一通貨を前提にしている | gold 建ての品目は `dyn_items` に入れない | — 運用で回避 |
| **給料・クエスト報酬・強盗など Mod 外の収入** | §7 の目標成長曲線が届かなくなる | §7.6 の coverage 検査が補正を打ち切る | — §7 実装時 |

**DB ドライバの衝突は無い。** vorp_core 3.3 と vorp_inventory 4.5 はどちらも
`@oxmysql/lib/MySQL.lua` を読み込んでいるので、oxmysql は必ず存在する。

---

## 11. 運用パラメータの初期値（叩き台）

| カテゴリ | elasticity | half_life | min_mult | max_mult | npc_spread |
|---|---|---|---|---|---|
| 農作物 | 0.70 | 360 分 | 0.15 | 2.00 | 0.35 |
| 動物素材 | 0.60 | 480 分 | 0.20 | 2.50 | 0.30 |
| 鉱物 | 0.45 | 1440 分 | 0.30 | 2.50 | 0.25 |
| 加工品 | 0.30 | 2880 分 | 0.50 | 2.00 | 0.20 |
| 高級品・貴金属 | 0.35 | 4320 分 | 0.40 | 3.00 | 0.25 |

農作物の弾力性を最も高く、下限を最も低くしてある。これが「単価の高い作物だけ植える」への直接の対策。

### 11.1 濫用対策

- **同一人物の連投**: 直近 1 時間に同一 `identifier` × 同一 `item` の売却が閾値を超えたら追加減価（`personal_glut` 係数）
- **店舗ごとの分散売り**: 仮想在庫はサーバー全体で 1 つ。店舗を変えても価格は同じ
- **精算アイテムの複製バグ**: `dyn_npc_tx` に `stock_before/after` を残しているので、
  異常な流入量を SQL 一発で検出できる（`SELECT item, SUM(qty) FROM dyn_npc_tx WHERE direction='sell' GROUP BY item`）

---

## 12. 実装フェーズ

**実装状況**:
- Phase 1〜2 … `resources/dyn_economy`（[README](../resources/dyn_economy/README.md)）
- Phase 3 … `resources/dyn_economy_bridge`（[README](../resources/dyn_economy_bridge/README.md)）。
  VORP アダプタと決済フローは実装済み。残るのは既存店舗リソース側の呼び出し差し替え

FiveM を起動せずに走るテストが `tests/` にあり、`./tests/run_all.sh` で実行できる。

| Phase | 内容 | 完了条件 |
|---|---|---|
| 1 ✅ | スキーマ作成、`dyn_items` の初期投入（既存店舗の固定価格から自動生成） | テーブルが作られ、全取扱品に行がある |
| 2 ✅ | `pricing.lua`（§4）＋ exports（§10）。既存店舗はまだ触らない | `/dyn_quote <item> <qty>` で価格が返る |
| 3 ⏳ | ブリッジ経由で既存 NPC 店舗を `Quote/Commit` に置換 | ブリッジは実装済み。店舗リソース側の差し替えが残り |
| 4 | レシピインポータと原価計算（§5） | `mat_cost` が埋まり、下限価格が効く |
| 5 | 価格履歴の 1 時間バケット集計、UI の価格変動表示 | 直近推移が見える |
| 5.5 | §6.2 の bootstrap 較正とドライラン。既存店舗の価格表から `currency_scale` を逆算 | `/dyn_calibrate --dry-run` が差分表を出す |
| 5.6 | 起動時の資産センサスと総額健全性チェック（§6.4）、初期所持金の導出（§6.3） | 起動ログに中央値・外れ値・drift が出る |
| 5.7 | 税の記帳と国庫（§9.1 / §9.2）。補助金はまだ出さない | 国庫に税が貯まり `/treasury` で内訳が見える |
| 6 | 委託所（§8） | 出品・購入・返却・手数料が動作し `dyn_market_trades` に残る |
| 7 | 日次スナップショットと `dyn_item_yield` の集計（§6.5 / §6.6）。較正はまだ適用しない | 2 週間分のデータが溜まり、時給分布が見える |
| 8 | 収集効率アンカーと購買力追従を有効化（§6.5 / §6.6） | 高効率アイテムの `price_index` が自動で下がり始める |
| 9 | マネーサプライ PI 制御（§6.7） | 日次のマネー成長率が目標帯に収束 |
| 10 | `dyn_player_progress` の集計と `/dyn_progress --dry-run`（§7）。適用はしない | 目標曲線に対する現在地が表で見える |
| 11 | 目標成長曲線の適用を有効化（§7、任意） | 重み付き誤差が不感帯に収束 |
| 12 | 組合の申請・承認と実績払い補助金（§9.3〜9.5、任意） | 承認された組合に週次で補助が振り込まれる |
| 13 | 実データを見ながらパラメータ調整（§11） | 単一作物への集中が実測で緩和 |

Phase 3 までで「価格が動く」、Phase 6 で「プレイヤー間取引が有利になる」、
Phase 8 で「サーバー差が自動で埋まる」、Phase 11 で「狙った成長速度に乗る」、
Phase 12 で「抜かれた税が組合に還ってくる」。
Phase 1〜3 だけ入れても単体で価値がある構成にしてある。

**較正（Phase 7 以降）は必ず実測データが溜まってから**。導入直後に有効にすると、
標本の薄い初期ログだけを見て価格が大きく歪む。
Phase 10〜11 の目標成長曲線は最も介入が強いので、Phase 8〜9 が安定してから最後に入れる。
Phase 5.7（税の記帳）だけは早めに入れておくとよい。挙動を変えずに
「どれだけ税が集まるのか」の実測が取れ、Phase 12 の補助金予算をその数字から決められる。

---

## 13. 未確定・要確認

1. ~~**フレームワーク**~~ — **VORP に確定**（vorp_core 3.3 / vorp_inventory 4.5）。ブリッジ実装済み
2. ~~**インベントリ**~~ — vorp_inventory。metadata 省略時は `{}` ではなく `nil` を渡す必要がある
   （`{}` は Lua では truthy なので「メタデータ一致検索」に入り常に 0 件になる）
3. **既存の NPC 店舗リソース名**と、現在の固定価格表の所在（Lua ハードコードか DB か）
   — これが分かれば §6.2 の bootstrap 較正を実データで回し、`price_index` を生成できる
4. **既存 DB に売買ログがあるか** — あれば初期の `virtual_stock` をそこから逆算して滑らかに移行できる
5. **通貨** — 単一通貨か、金塊など第二通貨があるか
6. **プレイ時間の取得手段** — 較正（§6.6）は「プレイ時間あたりの獲得量」が要るので、
   フレームワークが playtime を持っているか、なければ接続ログを自前で取る必要がある
7. **全キャラの所持金を集計できるか** — 銀行残高が別テーブル・別リソースの場合、
   §6.5 のマネーサプライ計算にどこまで含めるかを決める（現金のみ / 現金＋銀行 / ＋資産）
8. **既存店舗の RandomPrices / DynamicStore を落としてよいか** — vorp_stores を使っている場合、
   両方 false にしないと価格と在庫を二重に制御することになる（§10.3）
9. **狙っている成長速度** — §7 を使うなら「○日でだいたい△」の想定値。
   まだ無ければ Phase 10 の `--dry-run` で 2 週間実測を眺めてから決めればよい
10. **Mod 外の収入源** — 給料・クエスト報酬・強盗など。§7.6 の coverage に直結する
11. **市役所の扱い** — 組合申請の窓口を既存の市役所リソースに相乗りさせるか、
    独自メニューを立てるか。RP 上の運用（窓口 NPC を置くか、Discord 申請か）も含めて要決定
12. **承認できる権限者** — `/guild approve` を誰が撃てるか（ACE 権限 / 特定の job / 特定の identifier）
13. ~~**銀行残高の所在**~~ — **vorp_banking は `bank_users` テーブル**に置く。
    §6.4 のセンサスは `characters.money` と `bank_users` を合算する必要がある
14. **想定同時接続数** — 委託所の注文数とキャッシュ戦略に影響（16 人規模ならキャッシュは単純な in-memory で足りる）
