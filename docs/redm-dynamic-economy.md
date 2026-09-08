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
│   ├── ledger.lua                -- 取引記録・価格履歴の書き込み
│   └── exports.lua               -- 外部リソース向け API（§9）
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
```

分割の理由: 価格エンジンだけ先に入れて既存店舗に噛ませる運用ができ、委託所は後から追加できる。

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

`npc_spread = 0.30` なら、NPC から買って NPC に売り戻すと 30% 損する。
一方、委託所の手数料は 3%（§8）。**この 27 ポイントの差がプレイヤー間取引の動機**になる。
NPC 買い戻しによる裁定（安く買って高く売る）も同時に塞げる。

---

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
| `global_mult` | サーバー固有・運用中に変動 | マネーサプライ制御（§6.5）が動かす補正。既定 1.0 |

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

### 6.3 所持金分布への追従（購買力を一定に保つ）

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

### 6.4 収集効率アンカー（サーバー差の本命）

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

### 6.5 マネーサプライの PI 制御

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

### 6.6 追加テーブル（§3 に加える）

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

`dyn_items` への追加列: `price_index DECIMAL(12,4)`, `pinned TINYINT(1) DEFAULT 0`。

### 6.7 較正の安全装置

自動較正は「静かに経済を壊す」事故が起きやすいので、以下を必ず入れる。

| 装置 | 内容 |
|---|---|
| 日次・小刻み・クランプ | 全ての較正は 1 日 1 回、変化幅に上限（scale ±2%、index ±3%、mult ±30%） |
| ドライラン | `/dyn_calibrate --dry-run` で「何がどれだけ動くか」の差分表だけ出す。適用は別コマンド |
| ピン留め | `dyn_items.pinned = 1` のアイテムは較正対象外。ストーリー上の固定価格品や換金専用品に使う |
| キルスイッチ | `Config.Calibration.enabled = false` で §6.3〜6.5 を全停止。§4 の需給変動だけが残る |
| 監査ログ | 較正のたびに変更前後を `dyn_econ_snapshot` と差分ログに残し、いつでも巻き戻せる |
| 標本下限 | 標本が閾値未満のアイテム・日は較正しない。導入直後は §6.2 の初期値のまま動く |

### 6.8 導入手順への影響

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

§6.5 のマネーサプライ PI 制御と本機能は、どちらも同じ `global_mult` を奪い合うので、
**両方を素のまま有効にすると発振する**。次のように役割を分ける。

| Progression | マネーサプライ PI（§6.5） | 動作 |
|---|---|---|
| OFF | ON | §6.5 が主。金の総量の成長率を目標に寄せる |
| ON | 自動で**ガード役に降格** | Progression が `global_mult` を決め、§6.5 は「暴走したときだけ効く上下限」として働く |
| ON | OFF | Progression のみ。最もシンプル |

`§6.4` の収集効率アンカーは `price_index`（アイテム**間**の相対価格）を動かし、
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
  networth        DECIMAL(16,2) NOT NULL DEFAULT 0,   -- 現金＋銀行（§12 の確認事項）
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
| 所持金追従（§6.3） | `Config.Calibration.wealth` | OFF | 物価が固定され、長期的にインフレする |
| 収集効率アンカー（§6.4） | `Config.Calibration.yield` | OFF | 高効率アイテムの是正が §4 の短期変動のみになる |
| マネーサプライ PI（§6.5） | `Config.Calibration.moneySupply` | OFF | 金の総量の制御なし |
| **目標成長曲線（§7）** | `Config.Progression.enabled` | **OFF** | 本節の機能が全停止。他レイヤーは影響を受けない |
| 委託所（§8） | 別リソース | — | リソースを起動しなければよい |

すべて `dyn_econ_config` にも同じキーを置き、**再起動なしで管理コマンドから切り替えられる**ようにする。
事故ったときに真っ先に必要になるのはコンフィグ編集ではなく、その場で止める手段のため。

```
/dyn_toggle progression off        -- 即時停止。global_mult は 1.0 へ 1 日 3% で戻る
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

## 9. 外部リソース向け API（exports）

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

### 9.1 既存店舗への組み込み方針

| フレームワーク | 差し込み箇所 |
|---|---|
| RSGCore | `rsg-shops` の売買サーバーイベントで固定価格参照を `Quote/Commit` に置換 |
| VORP | `vorp_stores` の価格取得部を置換。`vorp_inventory` の addItem/subItem はそのまま |
| RedEM:RP | 各店舗リソースの売却ハンドラを置換 |

アダプタが提供すべき関数は 4 つだけ:
`GetIdentifier(src)` / `GetMoney(src)` / `AddMoney(src, amt)` / `RemoveMoney(src, amt)`
＋ `AddItem` / `RemoveItem` / `GetItemCount`。

較正（§6）のために、さらに 2 つを追加で要求する:
`GetAllPlayersMoney()`（オフライン含む全キャラの所持金一覧。DB 直読みで可）と `GetPlaytimeSeconds(identifier, since)`（プレイ時間。取れないフレームワークでは 自前の接続ログテーブルで代替する）。

---

## 10. 運用パラメータの初期値（叩き台）

| カテゴリ | elasticity | half_life | min_mult | max_mult | npc_spread |
|---|---|---|---|---|---|
| 農作物 | 0.70 | 360 分 | 0.15 | 2.00 | 0.35 |
| 動物素材 | 0.60 | 480 分 | 0.20 | 2.50 | 0.30 |
| 鉱物 | 0.45 | 1440 分 | 0.30 | 2.50 | 0.25 |
| 加工品 | 0.30 | 2880 分 | 0.50 | 2.00 | 0.20 |
| 高級品・貴金属 | 0.35 | 4320 分 | 0.40 | 3.00 | 0.25 |

農作物の弾力性を最も高く、下限を最も低くしてある。これが「単価の高い作物だけ植える」への直接の対策。

### 10.1 濫用対策

- **同一人物の連投**: 直近 1 時間に同一 `identifier` × 同一 `item` の売却が閾値を超えたら追加減価（`personal_glut` 係数）
- **店舗ごとの分散売り**: 仮想在庫はサーバー全体で 1 つ。店舗を変えても価格は同じ
- **精算アイテムの複製バグ**: `dyn_npc_tx` に `stock_before/after` を残しているので、
  異常な流入量を SQL 一発で検出できる（`SELECT item, SUM(qty) FROM dyn_npc_tx WHERE direction='sell' GROUP BY item`）

---

## 11. 実装フェーズ

| Phase | 内容 | 完了条件 |
|---|---|---|
| 1 | スキーマ作成、`dyn_items` の初期投入（既存店舗の固定価格から自動生成） | テーブルが作られ、全取扱品に行がある |
| 2 | `pricing.lua`（§4）＋ exports（§9）。既存店舗はまだ触らない | `/dyn_quote <item> <qty>` で価格が返る |
| 3 | ブリッジ経由で既存 NPC 店舗を `Quote/Commit` に置換 | 売買が動的価格で通り `dyn_npc_tx` に記録される |
| 4 | レシピインポータと原価計算（§5） | `mat_cost` が埋まり、下限価格が効く |
| 5 | 価格履歴の 1 時間バケット集計、UI の価格変動表示 | 直近推移が見える |
| 5.5 | §6.2 の bootstrap 較正とドライラン。既存店舗の価格表から `currency_scale` を逆算 | `/dyn_calibrate --dry-run` が差分表を出す |
| 6 | 委託所（§8） | 出品・購入・返却・手数料が動作し `dyn_market_trades` に残る |
| 7 | 日次スナップショットと `dyn_item_yield` の集計（§6.3 / §6.4）。較正はまだ適用しない | 2 週間分のデータが溜まり、時給分布が見える |
| 8 | 収集効率アンカーと購買力追従を有効化（§6.3 / §6.4） | 高効率アイテムの `price_index` が自動で下がり始める |
| 9 | マネーサプライ PI 制御（§6.5） | 日次のマネー成長率が目標帯に収束 |
| 10 | `dyn_player_progress` の集計と `/dyn_progress --dry-run`（§7）。適用はしない | 目標曲線に対する現在地が表で見える |
| 11 | 目標成長曲線の適用を有効化（§7、任意） | 重み付き誤差が不感帯に収束 |
| 12 | 実データを見ながらパラメータ調整（§10） | 単一作物への集中が実測で緩和 |

Phase 3 までで「価格が動く」、Phase 6 で「プレイヤー間取引が有利になる」、
Phase 8 で「サーバー差が自動で埋まる」、Phase 11 で「狙った成長速度に乗る」。
Phase 1〜3 だけ入れても単体で価値がある構成にしてある。

**較正（Phase 7 以降）は必ず実測データが溜まってから**。導入直後に有効にすると、
標本の薄い初期ログだけを見て価格が大きく歪む。
Phase 10〜11 の目標成長曲線は最も介入が強いので、Phase 8〜9 が安定してから最後に入れる。

---

## 12. 未確定・要確認

1. **フレームワーク**（RSGCore / VORP / RedEM:RP）— 未確定。確定次第 §9.1 のブリッジを 1 本だけ実装する
2. **インベントリ**（`ox_inventory` を使っているか、フレームワーク標準か）— metadata の扱いが変わる
3. **既存の NPC 店舗リソース名**と、現在の固定価格表の所在（Lua ハードコードか DB か）
4. **既存 DB に売買ログがあるか** — あれば初期の `virtual_stock` をそこから逆算して滑らかに移行できる
5. **通貨** — 単一通貨か、金塊など第二通貨があるか
6. **プレイ時間の取得手段** — 較正（§6.4）は「プレイ時間あたりの獲得量」が要るので、
   フレームワークが playtime を持っているか、なければ接続ログを自前で取る必要がある
7. **全キャラの所持金を集計できるか** — 銀行残高が別テーブル・別リソースの場合、
   §6.3 のマネーサプライ計算にどこまで含めるかを決める（現金のみ / 現金＋銀行 / ＋資産）
8. **狙っている成長速度** — §7 を使うなら「○日でだいたい△」の想定値。
   まだ無ければ Phase 10 の `--dry-run` で 2 週間実測を眺めてから決めればよい
9. **Mod 外の収入源** — 給料・クエスト報酬・強盗など。§7.6 の coverage に直結する
10. **想定同時接続数** — 委託所の注文数とキャッシュ戦略に影響（16 人規模ならキャッシュは単純な in-memory で足りる）
