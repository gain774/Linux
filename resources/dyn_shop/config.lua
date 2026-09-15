--[[
  店舗の定義。

  **価格はここに書かない。** 価格は全て dyn_economy が決める。
  この設定が持つのは「どの品目をどこで扱うか」だけ。
  固定価格を書ける場所を残すと、結局そちらが正になって動的価格の意味が無くなる。

  NPC は「店舗の建物」ではなく、その場に立たせる物売り（vendor ped）として扱う
  （購入できる物件が用意できたら屋内に移す想定）。`ped` が読み込めなかった場合でも
  取引そのものは coords への距離判定だけで動くので、ped 未指定・モデル読み込み
  失敗のどちらでも機能は止まらない（client/main.lua が黙ってフォールバックする）。

  `state` は §9（組合・補助金）の州別週次課税の記帳先。RedM の実在の州名を使う:
  new_hanover / west_elizabeth / new_austin / ambarino / lemoyne
]]
ShopConfig = {}

-- 店舗を開ける距離（メートル）。サーバー側でも同じ値で検証する
ShopConfig.interactDistance = 2.5

-- 同一プレイヤーの取引間隔（ミリ秒）。連打と自動化への最低限の歯止め
ShopConfig.tradeCooldownMs = 500

-- 数量の選択肢。「all」は売却時のみ意味を持つ（所持数すべて）
ShopConfig.quantities = { 1, 5, 10, 25, 50, 'all' }

ShopConfig.shops = {
    valentine_general = {
        label   = '雑貨屋（バレンタイン）',
        state   = 'new_hanover',
        coords  = vector3(-279.0, 803.0, 119.4),
        heading = 20.0,
        ped     = { model = 'u_m_m_rhdgenstoreowner_01', scenario = 'WORLD_HUMAN_STAND_IMPATIENT' },
        blip    = { sprite = 1749866775, name = '雑貨屋' },
        hours   = { open = 7, close = 21 },     -- nil なら 24 時間営業
        -- プレイヤーが売れる品目
        sell = { 'corn', 'wheat', 'potato', 'chewingtobacco', 'meat' },
        -- プレイヤーが買える品目
        buy  = { 'corn', 'wheat', 'flour' },
    },

    valentine_butcher = {
        label   = '精肉店（バレンタイン）',
        state   = 'new_hanover',
        coords  = vector3(-286.0, 776.0, 119.5),
        heading = 160.0,
        ped     = { model = 'u_m_m_rhdgenstoreowner_02', scenario = 'WORLD_HUMAN_STAND_IMPATIENT' },
        blip    = { sprite = 1749866775, name = '精肉店' },
        hours   = { open = 8, close = 20 },
        sell = { 'deerpelt', 'coyotepelt', 'wolfpelt', 'meat', 'fishmeat' },
        buy  = { 'meat', 'fishmeat' },
    },

    blackwater_trader = {
        label   = '交易所（ブラックウォーター）',
        state   = 'west_elizabeth',
        coords  = vector3(-871.0, -1315.0, 43.6),
        heading = 90.0,
        ped     = { model = 'cs_mp_travellingsaleswoman', scenario = 'WORLD_HUMAN_STAND_IMPATIENT' },
        blip    = { sprite = 1749866775, name = '交易所' },
        hours   = nil,                           -- 24 時間
        sell = { 'coal', 'iron', 'gold_nugget', 'deerpelt', 'wolfpelt' },
        buy  = { 'coal', 'iron' },
    },
}
