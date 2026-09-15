-- vorp_stores の config.lua から、衝突検出のテストに必要な形だけを抜き出したもの。
-- 実物の書式（行末コメント、コメントアウトされた行、店舗ごとの繰り返し）を残してある。
Config = {}

Config.Stores = {
    Valentine = {
        StoreHoursAllowed = true,
        RandomPrices = true,          -- prices will be random every restart
        distanceOpenStore = 3.0,
        DynamicStore = true,          -- selling increases store stock
    },
    Blackwater = {
        StoreHoursAllowed = true,
        RandomPrices = false,
        DynamicStore = false,
    },
    Strawberry = {
        -- RandomPrices = true,       -- コメントアウトされているので検出しない
        DynamicStore = true,
    },
}
