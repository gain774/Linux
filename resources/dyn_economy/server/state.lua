--[[
  アイテムの設定と仮想在庫のインメモリ状態（§4.3 / §6.1）

  DB は起動時の読み込みと定期的な書き戻しにだけ使う。
  価格の問い合わせは毎回 DB を叩かない。
]]
DynState = {}

local items = {}   -- item -> { 設定 + stock, updatedAt, matCost, dirty }
local econ  = { currency_scale = 1.0, cpi_mult = 1.0 }

local function nowSec() return os.time() end

-- カテゴリ既定値から継承する項目（config/categories.lua のキーと同名）
local INHERITED = { 'elasticity', 'minMult', 'maxMult', 'halfLifeMin', 'spread' }

-- DB 側の運用値で上書きする列 -> 内部フィールド
local DB_NUMBERS = {
    target_stock = 'targetStock', elasticity  = 'elasticity', min_mult = 'minMult',
    max_mult     = 'maxMult',     half_life_min = 'halfLifeMin',
    npc_spread   = 'spread',      price_index = 'priceIndex',
}
local DB_FLAGS = {
    npc_sellable = 'npcSellable', npc_buyable = 'npcBuyable',
    pinned       = 'pinned',      enabled     = 'enabled',
}

local function resolve(itemName, cfg)
    local cat = Categories[cfg.category] or Categories.default
    local it = {
        item        = itemName,
        category    = cfg.category or 'misc',
        priceIndex  = cfg.priceIndex,
        targetStock = cfg.targetStock or 100,
        npcSellable = cfg.npcSellable ~= false,
        npcBuyable  = cfg.npcBuyable  ~= false,
        pinned      = cfg.pinned == true,
        enabled     = cfg.enabled ~= false,
    }
    for _, key in ipairs(INHERITED) do
        it[key] = cfg[key] or cat[key]
    end
    return it
end

--- config/items.lua を読み込み、DB の状態を重ねる
function DynState.load()
    items = {}
    for name, cfg in pairs(Items) do
        local it = resolve(name, cfg)
        it.stock     = it.targetStock
        it.updatedAt = nowSec()
        it.matCost   = nil
        it.dirty     = true
        items[name] = it
    end

    if not DynDb.isReady() then return end

    -- dyn_items に無いものを入れ、あるものは DB 側の運用値を優先する
    for name, it in pairs(items) do
        DynDb.execute([[
            INSERT INTO dyn_items
              (item, category, price_index, base_price, target_stock, elasticity,
               min_mult, max_mult, half_life_min, npc_spread, npc_sellable, npc_buyable, pinned, enabled)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON DUPLICATE KEY UPDATE price_index = VALUES(price_index)
        ]], {
            name, it.category, it.priceIndex, 0, it.targetStock, it.elasticity,
            it.minMult, it.maxMult, it.halfLifeMin, it.spread,
            it.npcSellable and 1 or 0, it.npcBuyable and 1 or 0,
            it.pinned and 1 or 0, it.enabled and 1 or 0,
        })
    end

    -- DB 側は運用中に管理者が触る想定なので、config より DB を優先する
    for _, row in ipairs(DynDb.query('SELECT * FROM dyn_items') or {}) do
        local it = items[row.item]
        if it then
            for col, field in pairs(DB_NUMBERS) do it[field] = tonumber(row[col]) or it[field] end
            for col, field in pairs(DB_FLAGS)   do it[field] = row[col] == 1 end
            it.stock = it.targetStock
        end
    end

    local states = DynDb.query('SELECT item, virtual_stock, mat_cost, UNIX_TIMESTAMP(updated_at) AS ts FROM dyn_item_state') or {}
    for _, row in ipairs(states) do
        local it = items[row.item]
        if it then
            it.stock     = tonumber(row.virtual_stock) or it.stock
            it.matCost   = tonumber(row.mat_cost)
            it.updatedAt = tonumber(row.ts) or nowSec()
            it.dirty     = false
        end
    end

    local cfgRows = DynDb.query('SELECT k, v FROM dyn_econ_config') or {}
    for _, row in ipairs(cfgRows) do
        econ[row.k] = tonumber(row.v)
    end

    print(('[dyn_economy] %d 品目を読み込みました (currency_scale=%.4f)')
        :format(DynState.count(), econ.currency_scale))
end

function DynState.count()
    local n = 0
    for _ in pairs(items) do n = n + 1 end
    return n
end

function DynState.all() return items end

--- 経過時間ぶんの均衡回帰を適用してから返す（§4.3）
function DynState.get(itemName)
    local it = items[itemName]
    if not it then return nil end
    local t = nowSec()
    local dtMin = (t - it.updatedAt) / 60
    if dtMin > 0 then
        local before = it.stock
        it.stock = DynMath.decayStock(it.stock, it.targetStock, dtMin, it.halfLifeMin)
        it.updatedAt = t
        if math.abs(it.stock - before) > 1e-9 then it.dirty = true end
    end
    return it
end

function DynState.setStock(itemName, value)
    local it = DynState.get(itemName)
    if not it then return false end
    it.stock = math.max(value, DynMath.MIN_STOCK)
    it.updatedAt = nowSec()
    it.dirty = true
    return true
end

function DynState.addStock(itemName, delta)
    local it = DynState.get(itemName)
    if not it then return false end
    it.stock = math.max(it.stock + delta, DynMath.MIN_STOCK)
    it.updatedAt = nowSec()
    it.dirty = true
    return true
end

--- 品目を有効／無効にする。ブリッジの起動時検証（§10.3）が使う。
--- 実行時だけの状態で永続化しない。環境が変われば判定も変わるので、
--- 起動のたびに突き合わせ直すほうが正しい。
function DynState.setEnabled(itemName, enabled)
    local it = items[itemName]
    if not it then return false end
    it.enabled = enabled and true or false
    return true
end

function DynState.setMatCost(itemName, cost)
    local it = items[itemName]
    if not it then return false end
    it.matCost = cost
    it.dirty = true
    return true
end

function DynState.econ(key) return econ[key] or 1.0 end

function DynState.setEcon(key, value)
    econ[key] = value
    if DynDb.isReady() then
        DynDb.execute([[
            INSERT INTO dyn_econ_config (k, v, updated_at) VALUES (?, ?, NOW())
            ON DUPLICATE KEY UPDATE v = VALUES(v), updated_at = NOW()
        ]], { key, value })
    end
end

--- カテゴリ別の物価倍率（§4.5）。季節・イベント用に config から与える
function DynState.categoryMult(category)
    local m = Config.PriceLevel.categoryMult
    return m and m[category] or 1.0
end

--- 変化した行だけ書き戻す
function DynState.persist()
    if not DynDb.isReady() then return 0 end
    local n = 0
    for name, it in pairs(items) do
        if it.dirty then
            DynDb.execute([[
                INSERT INTO dyn_item_state (item, virtual_stock, cached_buy, cached_sell, mat_cost, updated_at)
                VALUES (?, ?, ?, ?, ?, FROM_UNIXTIME(?))
                ON DUPLICATE KEY UPDATE
                    virtual_stock = VALUES(virtual_stock),
                    cached_buy    = VALUES(cached_buy),
                    cached_sell   = VALUES(cached_sell),
                    mat_cost      = VALUES(mat_cost),
                    updated_at    = VALUES(updated_at)
            ]], { name, it.stock, it.cachedBuy or 0, it.cachedSell or 0, it.matCost, it.updatedAt })
            it.dirty = false
            n = n + 1
        end
    end
    return n
end
