--[[
  店舗の定義。

  **価格はここに書かない。** 価格は全て dyn_economy が決める。
  この設定が持つのは「どの品目をどこで扱うか」だけ。
  固定価格を書ける場所を残すと、結局そちらが正になって動的価格の意味が無くなる。
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
        label  = '雑貨屋（バレンタイン）',
        coords = vector3(-279.0, 803.0, 119.4),
        blip   = { sprite = 1749866775, name = '雑貨屋' },
        hours  = { open = 7, close = 21 },     -- nil なら 24 時間営業
        -- プレイヤーが売れる品目
        sell = { 'corn', 'wheat', 'potato', 'chewingtobacco', 'meat' },
        -- プレイヤーが買える品目
        buy  = { 'corn', 'wheat', 'flour' },
    },

    valentine_butcher = {
        label  = '精肉店（バレンタイン）',
        coords = vector3(-286.0, 776.0, 119.5),
        blip   = { sprite = 1749866775, name = '精肉店' },
        hours  = { open = 8, close = 20 },
        sell = { 'deerpelt', 'coyotepelt', 'wolfpelt', 'meat', 'fishmeat' },
        buy  = { 'meat', 'fishmeat' },
    },

    blackwater_trader = {
        label  = '交易所（ブラックウォーター）',
        coords = vector3(-871.0, -1315.0, 43.6),
        blip   = { sprite = 1749866775, name = '交易所' },
        hours  = nil,                           -- 24 時間
        sell = { 'coal', 'iron', 'gold_nugget', 'deerpelt', 'wolfpelt' },
        buy  = { 'coal', 'iron' },
    },
}
