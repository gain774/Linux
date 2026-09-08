--[[
  アイテムの設定と仮想在庫のインメモリ状態（§4.3 / §6.1）

  DB は起動時の読み込みと定期的な書き戻しにだけ使う。
  価格の問い合わせは毎回 DB を叩かない。
]]
DynState = {}

local items   = {}   -- item -> { 設定 + stock, updatedAt, matCost, dirty }
local econ    = { currency_scale = 1.0, cpi_mult = 1.0 }
local catMult = {}   -- category -> 物価倍率（§4.5、Phase 1〜2 では常に 1.0）

local function nowSec() return os.time() end

local function resolve(itemName, cfg)
    local cat = Categories[cfg.category] or Categories.default
    return {
        item        = itemName,
        category    = cfg.category or 'misc',
        priceIndex  = cfg.priceIndex,
        targetStock = cfg.targetStock or 100,
        elasticity  = cfg.elasticity  or cat.elasticity,
        minMult     = cfg.minMult     or cat.minMult,
        maxMult     = cfg.maxMult     or cat.maxMult,
        halfLifeMin = cfg.halfLifeMin or cat.halfLifeMin,
        spread      = cfg.spread      or cat.spread,
        npcSellable = cfg.npcSellable ~= false,
        npcBuyable  = cfg.npcBuyable  ~= false,
        pinned      = cfg.pinned == true,
        enabled     = cfg.enabled ~= false,
    }
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

    local rows = DynDb.query('SELECT * FROM dyn_items') or {}
    for _, row in ipairs(rows) do
        local it = items[row.item]
        if it then
            it.targetStock = tonumber(row.target_stock) or it.targetStock
            it.elasticity  = tonumber(row.elasticity)   or it.elasticity
            it.minMult     = tonumber(row.min_mult)     or it.minMult
            it.maxMult     = tonumber(row.max_mult)     or it.maxMult
            it.halfLifeMin = tonumber(row.half_life_min) or it.halfLifeMin
            it.spread      = tonumber(row.npc_spread)   or it.spread
            it.priceIndex  = tonumber(row.price_index)  or it.priceIndex
            it.npcSellable = row.npc_sellable == 1
            it.npcBuyable  = row.npc_buyable == 1
            it.pinned      = row.pinned == 1
            it.enabled     = row.enabled == 1
            it.stock       = it.targetStock
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

function DynState.categoryMult(category) return catMult[category] or 1.0 end

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
