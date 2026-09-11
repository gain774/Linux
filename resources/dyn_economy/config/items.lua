--[[
  アイテムの相対価値（§6.1 の price_index）。

  ここに書くのは「小麦 1 に対してトウモロコシは 0.75」という比だけで、
  実際の金額ではない。サーバーの物価水準は currency_scale 側が持つので、
  この表は導入先が変わってもそのまま使える。

  targetStock は「そのアイテムが 1 日にどれくらい市場へ流れるか」の目安。
  実測が溜まったら Phase 5.5 以降の較正が調整する。
]]
Items = {
    -- 農作物（items テーブルで実在確認済み）
    corn           = { category = 'crop',    priceIndex = 0.75, targetStock = 400 },
    wheat          = { category = 'crop',    priceIndex = 1.00, targetStock = 400 },
    potato         = { category = 'crop',    priceIndex = 0.60, targetStock = 400 },
    hop            = { category = 'crop',    priceIndex = 1.30, targetStock = 250 },
    cocoa          = { category = 'crop',    priceIndex = 1.80, targetStock = 150 },
    -- 動物素材
    deerpelt       = { category = 'animal',  priceIndex = 6.00, targetStock =  80 },
    coyotepelt     = { category = 'animal',  priceIndex = 4.50, targetStock =  80 },
    wolfpelt       = { category = 'animal',  priceIndex = 7.00, targetStock =  60 },
    meat           = { category = 'animal',  priceIndex = 1.80, targetStock = 200 },
    fishmeat       = { category = 'animal',  priceIndex = 1.40, targetStock = 200 },
    -- 鉱物
    coal           = { category = 'ore',     priceIndex = 1.60, targetStock = 300 },
    iron           = { category = 'ore',     priceIndex = 3.00, targetStock = 200 },
    gold_nugget    = { category = 'luxury',  priceIndex = 45.0, targetStock =  20 },
    -- 加工品
    flour          = { category = 'crafted', priceIndex = 4.20, targetStock = 120 },
    chewingtobacco = { category = 'crafted', priceIndex = 9.00, targetStock =  80 },
    -- 資材
    water          = { category = 'misc',    priceIndex = 0.10, targetStock = 999, npcSellable = false },
}
