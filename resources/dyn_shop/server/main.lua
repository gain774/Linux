--[[
  店舗のサーバー側。

  価格は一切持たない。表示も決済も dyn_economy_bridge 経由で、
  金額の決定権は価格エンジンにある。ここがやるのは
  「誰が、どの店で、何を、いくつ」の検証だけ。
]]

local lastTrade = {}   -- src -> os.clock() ミリ秒

local function nowMs()
    return math.floor(os.clock() * 1000)
end

local function playerDistance(src, shop)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local p = GetEntityCoords(ped)
    return #(p - shop.coords)
end

local function gameHour()
    -- サーバー側でゲーム内時刻を持っていない構成でも動くよう、
    -- 時刻管理リソースがあればそれを使い、無ければ実時間で判定する。
    if GetResourceState('vorp_weather') == 'started' then
        local ok, h = pcall(function() return exports.vorp_weather:getHour() end)
        if ok and type(h) == 'number' then return h end
    end
    return tonumber(os.date('%H'))
end

local function validate(src, shopId, item, direction)
    local shop = ShopConfig.shops[shopId]
    if not shop then return nil, nil, 'unknown_shop' end

    local ok, err = ShopGuard.validate(shop, {
        item        = item,
        direction   = direction,
        hour        = gameHour(),
        distance    = playerDistance(src, shop),
        now         = nowMs(),
        lastTradeAt = item and lastTrade[src] or nil,
        cooldownMs  = ShopConfig.tradeCooldownMs,
        maxDistance = ShopConfig.interactDistance,
    })
    if not ok then return nil, shop, err end
    return true, shop, nil
end

--- メニューに出す一覧を組み立てる。価格は毎回引き直す（表示用の見積り）
local function buildMenu(src, shopId, shop)
    local out = { shopId = shopId, label = shop.label, sell = {}, buy = {} }

    for _, item in ipairs(shop.sell or {}) do
        local q = exports.dyn_economy_bridge:Quote(src, item, 1, 'sell')
        local info = exports.dyn_economy:GetItemInfo(item)
        if q and q.ok and info then
            out.sell[#out.sell + 1] = {
                item = item, unit = q.priceNow,
                -- 均衡在庫に対する比率。安い理由が需給なのか一目で分かるようにする
                supply = info.targetStock > 0 and (info.stock / info.targetStock) or 1.0,
            }
        end
    end

    for _, item in ipairs(shop.buy or {}) do
        local q = exports.dyn_economy_bridge:Quote(src, item, 1, 'buy')
        if q and q.ok then
            out.buy[#out.buy + 1] = { item = item, unit = q.priceNow }
        end
    end

    return out
end

RegisterNetEvent('dyn_shop:open', function(shopId)
    local src = source
    local ok, shop, err = validate(src, shopId, nil, 'sell')
    if not ok then
        return TriggerClientEvent('dyn_shop:denied', src, err)
    end
    TriggerClientEvent('dyn_shop:menu', src, buildMenu(src, shopId, shop))
end)

RegisterNetEvent('dyn_shop:trade', function(shopId, item, qty, direction)
    local src = source

    -- 「所持数すべて」はサーバー側で解決する。クライアントが送ってきた数量は信用しない
    if qty == 'all' then
        qty = (direction == 'sell') and exports.dyn_economy_bridge:GetItemCount(src, item) or 0
    end

    qty = tonumber(qty)
    if not qty or qty <= 0 or qty % 1 ~= 0 then
        return TriggerClientEvent('dyn_shop:denied', src, 'qty_invalid')
    end

    local ok, shop, err = validate(src, shopId, item, direction)
    if not ok then
        return TriggerClientEvent('dyn_shop:denied', src, err)
    end

    lastTrade[src] = nowMs()

    local res
    if direction == 'sell' then
        res = exports.dyn_economy_bridge:SellToNpc(src, item, qty, shopId)
    else
        res = exports.dyn_economy_bridge:BuyFromNpc(src, item, qty, shopId)
    end

    -- 失敗時のプレイヤーへの通知はブリッジ側が済ませている（二重に出さない）
    if res and res.ok then
        TriggerClientEvent('dyn_shop:traded', src, direction, item, qty, res.total)
    end
    -- 取引で価格が動くので、成否にかかわらずメニューを引き直す
    TriggerClientEvent('dyn_shop:menu', src, buildMenu(src, shopId, shop))
end)

AddEventHandler('playerDropped', function()
    lastTrade[source] = nil
end)
