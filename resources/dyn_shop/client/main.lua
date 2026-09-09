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

local function openQuantityMenu(shopId, item, direction, unit)
    local elements = {}
    for _, q in ipairs(ShopConfig.quantities) do
        if q ~= 'all' or direction == 'sell' then
            local text = (q == 'all') and '所持数すべて' or tostring(q)
            local hint  = (type(q) == 'number') and (' … 目安 ' .. money(unit * q)) or ''
            elements[#elements + 1] = { label = text .. hint, value = q }
        end
    end

    MenuData.Open('default', GetCurrentResourceName(), 'dyn_shop_qty', {
        title      = item,
        subtext    = (direction == 'sell') and '売る数量' or '買う数量',
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
        elements[#elements + 1] = {
            label = ('売る: %s <span style="opacity:.7;">%s / 個</span>%s')
                :format(e.item, money(e.unit), supplyTag(e.supply)),
            value = { item = e.item, dir = 'sell', unit = e.unit },
        }
    end
    for _, e in ipairs(payload.buy) do
        elements[#elements + 1] = {
            label = ('買う: %s <span style="opacity:.7;">%s / 個</span>')
                :format(e.item, money(e.unit)),
            value = { item = e.item, dir = 'buy', unit = e.unit },
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
        openQuantityMenu(payload.shopId, v.item, v.dir, v.unit)
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

RegisterNetEvent('dyn_shop:traded', function(direction, item, qty, total)
    local verb = (direction == 'sell') and '売却' or '購入'
    TriggerEvent('vorp:TipRight', ('%s %s x%d — %s'):format(verb, item, qty, money(total)), 4000)
end)

CreateThread(function()
    setupBlips()
    setupPrompts()

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
