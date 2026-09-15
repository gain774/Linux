--[[
  店舗のクライアント側。ブリップ・プロンプト・メニューだけ。

  価格も在庫もここでは一切保持しない。表示している値はサーバーが送ってきた
  そのときの見積りで、実際の金額は決済の戻り値が正（サーバーが再計算する）。
]]

local MenuData     = exports.vorp_menu:GetMenuData()
local promptGroup  = GetRandomIntInRange(0, 0xffffff)
local prompts      = {}
local nearShop     = nil
local menuOpen     = false

local function label(text)
    return CreateVarString(10, 'LITERAL_STRING', text)
end

local function money(v)
    return ('$%.2f'):format(v or 0)
end

-- 需給の状態を一目で分かるようにする。数字だけだと安い理由が伝わらない
local function supplyTag(ratio)
    if not ratio then return '' end
    if ratio >= 1.6 then return ' <span style="color:#c66;">供給過多</span>'
    elseif ratio >= 1.15 then return ' <span style="color:#c96;">やや余剰</span>'
    elseif ratio <= 0.6 then return ' <span style="color:#6c9;">品薄</span>'
    elseif ratio <= 0.85 then return ' <span style="color:#9c9;">やや品薄</span>'
    end
    return ''
end

local function setupBlips()
    for _, shop in pairs(ShopConfig.shops) do
        if shop.blip then
            local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, shop.coords)
            SetBlipSprite(blip, shop.blip.sprite, true)
            Citizen.InvokeNative(0x9CB1A1623062F402, blip, shop.blip.name or shop.label)
        end
    end
end

--[[
  物売り（vendor ped）をその場に立たせる。店舗の建物は要らない — 露店として
  外に立たせる運用を想定している（購入できる物件ができたら屋内に移す）。

  モデルの読み込みに失敗しても機能は止めない。取引の可否は shop.coords への
  距離だけで判定しているので、ped が出せなくても店としては引き続き機能する
  （見た目だけ「誰もいない場所でメニューが開く」に戻るだけ）。
]]
local shopPeds = {}

local function spawnShopPed(id, shop)
    if not shop.ped or not shop.ped.model then return end

    local hash = GetHashKey(shop.ped.model)
    RequestModel(hash)

    local waited = 0
    while not HasModelLoaded(hash) and waited < 3000 do
        Wait(50)
        waited = waited + 50
    end
    if not HasModelLoaded(hash) then
        print(('[dyn_shop] ped モデル "%s" を読み込めませんでした（%s）。NPC無しで動作します')
            :format(shop.ped.model, id))
        return
    end

    local ped = CreatePed(4, hash, shop.coords.x, shop.coords.y, shop.coords.z - 1.0,
        shop.heading or 0.0, false, false)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    SetModelAsNoLongerNeeded(hash)
    if shop.ped.scenario then
        TaskStartScenarioInPlace(ped, shop.ped.scenario, 0, true)
    end
    shopPeds[id] = ped
end

local function setupPeds()
    for id, shop in pairs(ShopConfig.shops) do
        spawnShopPed(id, shop)
    end
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, ped in pairs(shopPeds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
end)

local function setupPrompts()
    for id, shop in pairs(ShopConfig.shops) do
        local p = PromptRegisterBegin()
        PromptSetControlAction(p, 0x760A9C6F)              -- G
        PromptSetText(p, label(shop.label))
        PromptSetEnabled(p, true)
        PromptSetVisible(p, true)
        PromptSetStandardMode(p, true)
        PromptSetGroup(p, promptGroup)
        PromptRegisterEnd(p)
        prompts[id] = p
    end
end

local function openQuantityMenu(shopId, item, direction, unit, displayLabel, desc)
    local elements = {}
    for _, q in ipairs(ShopConfig.quantities) do
        if q ~= 'all' or direction == 'sell' then
            local text = (q == 'all') and '所持数すべて' or tostring(q)
            local hint  = (type(q) == 'number') and (' … 目安 ' .. money(unit * q)) or ''
            elements[#elements + 1] = { label = text .. hint, value = q }
        end
    end

    MenuData.Open('default', GetCurrentResourceName(), 'dyn_shop_qty', {
        title      = displayLabel or item,
        subtext    = desc or ((direction == 'sell') and '売る数量' or '買う数量'),
        elements   = elements,
        itemHeight = '4vh',
    }, function(data)
        MenuData.CloseAll()
        menuOpen = false
        -- 数量が all のときはサーバー側で所持数に解決する
        TriggerServerEvent('dyn_shop:trade', shopId, item, data.current.value, direction)
    end, function()
        MenuData.CloseAll()
        menuOpen = false
        TriggerServerEvent('dyn_shop:open', shopId)
    end)
end

local function openShopMenu(payload)
    local elements = {}

    for _, e in ipairs(payload.sell) do
        local fixedTag = e.fixed and ' <span style="opacity:.6;">[固定]</span>' or ''
        -- 個人間取引のほうが高ければ、NPC に売る損が一目で分かるように出す（§8.2）
        local vwapTag = e.vwap and (' <span style="opacity:.6;">(個人間実勢 %s)</span>'):format(money(e.vwap)) or ''
        elements[#elements + 1] = {
            label = ('売る: %s <span style="opacity:.7;">%s / 個</span>%s%s%s')
                :format(e.label, money(e.unit), supplyTag(e.supply), fixedTag, vwapTag),
            desc  = e.desc,
            value = { item = e.item, dir = 'sell', unit = e.unit, label = e.label, desc = e.desc },
        }
    end
    for _, e in ipairs(payload.buy) do
        local fixedTag = e.fixed and ' <span style="opacity:.6;">[固定]</span>' or ''
        elements[#elements + 1] = {
            label = ('買う: %s <span style="opacity:.7;">%s / 個</span>%s')
                :format(e.label, money(e.unit), fixedTag),
            desc  = e.desc,
            value = { item = e.item, dir = 'buy', unit = e.unit, label = e.label, desc = e.desc },
        }
    end

    if #elements == 0 then
        elements[1] = { label = '今は取引できる品がありません', value = false }
    end

    menuOpen = true
    MenuData.Open('default', GetCurrentResourceName(), 'dyn_shop_main', {
        title      = payload.label,
        subtext    = '価格は需給で変動します',
        elements   = elements,
        itemHeight = '4vh',
    }, function(data)
        local v = data.current.value
        if not v then return end
        MenuData.CloseAll()
        openQuantityMenu(payload.shopId, v.item, v.dir, v.unit, v.label, v.desc)
    end, function()
        MenuData.CloseAll()
        menuOpen = false
    end)
end

RegisterNetEvent('dyn_shop:menu', function(payload)
    -- 取引後の引き直しでも同じ経路を通る。開いていなければ何もしない
    if menuOpen or not payload then
        MenuData.CloseAll()
    end
    openShopMenu(payload)
end)

RegisterNetEvent('dyn_shop:denied', function(reason)
    local messages = {
        unknown_shop = 'その店は存在しません',
        closed       = '営業時間外です',
        out_of_range = '店から離れすぎています',
        too_fast     = '少し待ってください',
        qty_invalid  = '数量が正しくありません',
    }
    MenuData.CloseAll()
    menuOpen = false
    TriggerEvent('vorp:TipRight', messages[reason] or ('取引できません: ' .. tostring(reason)), 4000)
end)

RegisterNetEvent('dyn_shop:traded', function(direction, item, qty, total, label)
    local verb = (direction == 'sell') and '売却' or '購入'
    TriggerEvent('vorp:TipRight', ('%s %s x%d — %s'):format(verb, label or item, qty, money(total)), 4000)
end)

CreateThread(function()
    setupBlips()
    setupPrompts()
    setupPeds()

    while true do
        local sleep = 1000
        local coords = GetEntityCoords(PlayerPedId())
        nearShop = nil

        for id, shop in pairs(ShopConfig.shops) do
            if #(coords - shop.coords) <= ShopConfig.interactDistance then
                nearShop = id
                sleep = 0
                break
            end
        end

        if nearShop and not menuOpen then
            PromptSetActiveGroupThisFrame(promptGroup, label(ShopConfig.shops[nearShop].label))
            if PromptHasStandardModeCompleted(prompts[nearShop]) then
                TriggerServerEvent('dyn_shop:open', nearShop)
                Wait(500)
            end
        end

        Wait(sleep)
    end
end)
