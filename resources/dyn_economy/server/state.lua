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
    price_fixed  = 'fixed',
}

--[[
  oxmysql は TINYINT(1) 列を環境によって Lua の 1/0 ではなく true/false で返す
  （mysql2 の typeCast がドライバ設定次第で切り替わるため）。
  `row[col] == 1` だけで判定すると、boolean で返ってきた環境では全品目が
  enabled=false（=取引不可）に化ける。1 と true の両方を真として扱う。
]]
local function isTruthyFlag(v)
    return v == 1 or v == true or v == '1'
end

--[[
  fixed が true の品目は、需給で動く 5 段目（弾力性）を切って基準価格に固定する。
  通貨スケールや物価水準（§4.5）といった経済全体の較正は引き続き乗るので、
  「その品目だけの需給には反応しない」であって「未来永劫 1 円も動かない」ではない。
  銃・弾薬・道具のような、売り込まれても崩れてほしくない品目に使う想定（§11.1 の外側）。
]]
--- baseElasticity は fixed 解除時に戻す先。resolve() で一度だけ確定させ、
--- 以後 applyFixed が it.elasticity を書き換えても消えないようにしておく
local function applyFixed(it, fixed)
    it.fixed = fixed == true
    it.elasticity = it.fixed and 0 or it.baseElasticity
end

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
        label       = cfg.label,
        desc        = cfg.desc,
    }
    for _, key in ipairs(INHERITED) do
        it[key] = cfg[key] or cat[key]
    end
    it.baseElasticity = it.elasticity
    applyFixed(it, cfg.fixed)
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
               min_mult, max_mult, half_life_min, npc_spread, npc_sellable, npc_buyable, pinned, enabled, price_fixed)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON DUPLICATE KEY UPDATE price_index = VALUES(price_index)
        ]], {
            name, it.category, it.priceIndex, 0, it.targetStock, it.elasticity,
            it.minMult, it.maxMult, it.halfLifeMin, it.spread,
            it.npcSellable and 1 or 0, it.npcBuyable and 1 or 0,
            it.pinned and 1 or 0, it.enabled and 1 or 0, it.fixed and 1 or 0,
        })
    end

    -- DB 側は運用中に管理者が触る想定なので、config より DB を優先する
    for _, row in ipairs(DynDb.query('SELECT * FROM dyn_items') or {}) do
        local it = items[row.item]
        if it then
            for col, field in pairs(DB_NUMBERS) do it[field] = tonumber(row[col]) or it[field] end
            for col, field in pairs(DB_FLAGS)   do it[field] = isTruthyFlag(row[col]) end
            applyFixed(it, it.fixed) -- DB の price_fixed=1 が elasticity 列より後に効くようにやり直す
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

--- 固定価格／変動価格の切り替え。運用中の判断なので DB に永続化する
--- （enabled と違い、環境が変わっても引き継ぎたい設定のため）
function DynState.setFixed(itemName, fixed)
    local it = items[itemName]
    if not it then return false end
    applyFixed(it, fixed)
    if DynDb.isReady() then
        DynDb.execute('UPDATE dyn_items SET price_fixed = ?, elasticity = ? WHERE item = ?',
            { it.fixed and 1 or 0, it.elasticity, itemName })
    end
    return true
end

function DynState.setMatCost(itemName, cost)
    local it = items[itemName]
    if not it then return false end
    it.matCost = cost
    it.dirty = true
    return true
end

--- アイテム間の相対価値を書き換える（§6.6 収集効率アンカー用）。
--- DB に永続化する（fixed と同じく、環境をまたいで引き継ぎたい運用値のため）
function DynState.setPriceIndex(itemName, value)
    local it = items[itemName]
    if not it or not value or value <= 0 then return false end
    it.priceIndex = value
    if DynDb.isReady() then
        DynDb.execute('UPDATE dyn_items SET price_index = ? WHERE item = ?', { value, itemName })
    end
    return true
end

function DynState.econ(key) return econ[key] or 1.0 end

--- econ() は未設定キーに 1.0（倍率の既定）を返すが、積分項のように 0 が
--- 正しい既定値のキーもあるので、呼び出し側が既定値を指定できる版
function DynState.econOr(key, default) return econ[key] or default end

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
