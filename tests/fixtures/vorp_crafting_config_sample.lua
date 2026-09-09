-- vorp_crafting の config.lua から、取り込みのテストに必要な形だけを抜き出したもの。
-- 実物の書式（Items / Reward / take / TakeItems / Type / UseCurrencyMode）を残してある。
Config = {}

Config.defaultlang = "en_lang"
Config.Locations = {
    { name = 'Blackwater', id = 'blackwater', x = -872.222, y = -1390.924, z = 43.573 },
}

Config.Crafting = {
    {   -- 普通のレシピ。salt は take = false なので道具扱い
        Text = "Meat Bfast",
        Items = {
            { name = "meat", count = 2, take = true },
            { name = "salt", count = 1, take = false },
        },
        Reward = { { name = "consumable_breakfast", count = 1 } },
        Type = "item",
        UseCurrencyMode = false,
    },
    {   -- take を書いていない = 消費される（既定）。出力が 2 個
        Text = "Seasoned Small Game",
        Items = {
            { name = "consumable_game", count = 1 },
            { name = "salt", count = 1 },
        },
        Reward = { { name = "cookedsmallgame", count = 2 } },
        Type = "item",
    },
    {   -- 同じ素材が複数行に分かれている
        Text = "Double Wheat Bread",
        Items = {
            { name = "wheat", count = 2 },
            { name = "wheat", count = 3 },
            { name = "water", count = 1 },
        },
        Reward = { { name = "bread", count = 1 } },
    },
    {   -- 武器。addItem / subItem が効かないので取り込まない
        Text = "Cattleman Revolver",
        Items = { { name = "iron_ore", count = 5 } },
        Reward = { { name = "weapon_revolver_cattleman", count = 1 } },
        Type = "weapon",
    },
    {   -- 金で買うので素材原価にならない
        Text = "Bought Coffee",
        Items = {},
        Reward = { { count = 1 } },
        UseCurrencyMode = true,
        CurrencyType = 0,
    },
    {   -- 出力が複数。按分できないので取り込まない
        Text = "Butchered Deer",
        Items = { { name = "deer_carcass", count = 1 } },
        Reward = {
            { name = "animal_meat", count = 3 },
            { name = "animal_pelt", count = 1 },
        },
    },
    {   -- 何も消費しない
        Text = "Free Sample",
        Items = { { name = "wheat", count = 1 } },
        Reward = { { name = "sample", count = 1 } },
        TakeItems = false,
    },
    {   -- bread を作る別ルート。最初のものだけ採る
        Text = "Bread from Flour",
        Items = { { name = "flour", count = 1 } },
        Reward = { { name = "bread", count = 1 } },
    },
    {   -- 消費される素材が 1 つも無い（全部道具）
        Text = "Tool Only",
        Items = { { name = "hammer", count = 1, take = false } },
        Reward = { { name = "nothing", count = 1 } },
    },
}
