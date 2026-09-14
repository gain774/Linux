--[[
  個人間取引のクライアント側。表示と入力の受け付けだけ。

  ここで見せている数量・金額は毎回サーバーが送ってくる dyn_trade:sync が正。
  クライアントは何も検証しない（検証は全部サーバー側 = server/main.lua）。

  vorp_menu はリスト型メニューを重ねて開く想定ではないため（dyn_shop の
  数量サブメニューと同じ理由）、サブメニューを開くときは一旦メインの取引メニューを
  閉じ、閉じたら直前の状態（lastSync）で再度開き直す。
]]

local MenuData = exports.vorp_menu:GetMenuData()
local Core

CreateThread(function()
    while not Core do
        local ok, core = pcall(function() return exports.vorp_core:GetCore() end)
        if ok and core then Core = core else Wait(500) end
    end
end)

local tradeMenu = nil
local inTrade = false
local lastSync = nil

local function money(v)
    return ('%s%.2f'):format(Config.currencyLabel or '$', v or 0)
end

local function closeTradeMenu()
    if tradeMenu then tradeMenu.close(true, true, false) end
    tradeMenu = nil
end

local function render(sync)
    lastSync = sync
    if not sync then
        inTrade = false
        return closeTradeMenu()
    end
    inTrade = true
    closeTradeMenu()

    local elements = {}
    elements[#elements + 1] = { label = ('取引相手: %s'):format(sync.otherName), value = false }
    elements[#elements + 1] = { label = ('手数料 %.0f%%（現金部分から徴収されます）'):format((sync.feeRate or 0) * 100), value = false }

    elements[#elements + 1] = { label = '― あなたの提示 ―', value = false }
    for _, e in ipairs(sync.mine.items) do
        local hint = e.refPrice and (' <span style="opacity:.6;">(定価目安 %s)</span>'):format(money(e.refPrice)) or ''
        elements[#elements + 1] = {
            label = ('削除: %s x%d%s'):format(e.label, e.qty, hint),
            value = { action = 'removeItem', item = e.item },
        }
    end
    elements[#elements + 1] = { label = '+ アイテムを追加', value = { action = 'addItem' } }
    elements[#elements + 1] = { label = ('現金を設定: %s'):format(money(sync.mine.cash)), value = { action = 'setCash' } }

    elements[#elements + 1] = { label = '― 相手の提示 ―', value = false }
    if #sync.other.items == 0 then
        elements[#elements + 1] = { label = '（品目なし）', value = false }
    end
    for _, e in ipairs(sync.other.items) do
        local hint = e.refPrice and (' <span style="opacity:.6;">(定価目安 %s)</span>'):format(money(e.refPrice)) or ''
        elements[#elements + 1] = { label = ('%s x%d%s'):format(e.label, e.qty, hint), value = false }
    end
    elements[#elements + 1] = { label = ('相手の現金: %s'):format(money(sync.other.cash)), value = false }

    elements[#elements + 1] = { label = '― 状態 ―', value = false }
    elements[#elements + 1] = {
        label = sync.mine.confirmed and '確認済み（押すと取り消せます）' or '内容を確認する',
        value = { action = sync.mine.confirmed and 'unconfirm' or 'confirm' },
    }
    elements[#elements + 1] = {
        label = ('相手: %s'):format(sync.other.confirmed and '確認済み' or '未確認'),
        value = false,
    }
    elements[#elements + 1] = { label = '取引をキャンセル', value = { action = 'cancel' } }

    tradeMenu = MenuData.Open('default', GetCurrentResourceName(), 'dyn_trade_main', {
        title = '個人取引',
        subtext = '双方が「内容を確認する」を押すと成立します。内容を変えると確認は解除されます',
        elements = elements,
        itemHeight = '4vh',
    }, function(data)
        local v = data.current.value
        if not v then return end

        if v.action == 'removeItem' then
            TriggerServerEvent('dyn_trade:removeItem', v.item)
        elseif v.action == 'addItem' then
            openInventoryPicker()
        elseif v.action == 'setCash' then
            openCashInput()
        elseif v.action == 'confirm' then
            TriggerServerEvent('dyn_trade:confirm')
        elseif v.action == 'unconfirm' then
            TriggerServerEvent('dyn_trade:unconfirm')
        elseif v.action == 'cancel' then
            TriggerServerEvent('dyn_trade:cancel')
        end
    end, function()
        -- 戻る/ESC で閉じたときも交渉自体を打ち切る（サーバー側にセッションだけ残さない）
        if inTrade then TriggerServerEvent('dyn_trade:cancel') end
    end)
end

--- メインメニューを一旦閉じてサブメニュー的な入力を出し、終わったら元の状態で開き直す
function openCashInput()
    local sync = lastSync
    closeTradeMenu()
    local shim = MenuData.Open('default', GetCurrentResourceName(), 'dyn_trade_cash', {
        title = '現金を設定', elements = { { label = '入力してください', value = false } },
    }, function() end, function() end)

    shim.displayInput({
        inputType = 'number',
        header = '現金を設定',
        description = '相手に渡す現金額を入力してください（0で取り消し）',
        buttons = { confirm = '設定', cancel = 'キャンセル' },
    }, function(value)
        local amount = tonumber(value)
        shim.close(true, true, false)
        if amount then TriggerServerEvent('dyn_trade:setCash', amount) end
        if inTrade then render(sync) end
    end, function()
        shim.close(true, true, false)
        if inTrade then render(sync) end
    end)
end

--- 所持品から品目を選び、数量を入力して提示に追加する
function openInventoryPicker()
    local sync = lastSync
    closeTradeMenu()

    local items = Core.Callback.TriggerAwait('dyn_trade:getInventory', {}) or {}
    if #items == 0 then
        TriggerEvent('vorp:TipRight', '追加できる所持品がありません', 3000)
        if inTrade then render(sync) end
        return
    end

    -- 同じ品目が複数スタックに分かれていても数量は合算して 1 行にまとめる
    local merged, order = {}, {}
    for _, it in ipairs(items) do
        if not merged[it.name] then
            merged[it.name] = { label = it.label or it.name, count = 0 }
            order[#order + 1] = it.name
        end
        merged[it.name].count = merged[it.name].count + (it.count or 0)
    end

    local elements = {}
    for _, name in ipairs(order) do
        local e = merged[name]
        elements[#elements + 1] = { label = ('%s x%d'):format(e.label, e.count), value = name }
    end

    local pickMenu
    pickMenu = MenuData.Open('default', GetCurrentResourceName(), 'dyn_trade_pick', {
        title = '提示する品を選ぶ',
        elements = elements,
        itemHeight = '4vh',
    }, function(data, menu)
        local item = data.current.value
        if not item then return end
        menu.displayInput({
            inputType = 'number',
            header = '数量',
            description = ('%s をいくつ提示しますか？'):format(merged[item].label),
            buttons = { confirm = '追加', cancel = 'キャンセル' },
        }, function(value)
            local qty = math.floor(tonumber(value) or 0)
            pickMenu.close(true, true, false)
            if qty > 0 then TriggerServerEvent('dyn_trade:addItem', item, qty) end
            if inTrade then render(sync) end
        end, function()
            pickMenu.close(true, true, false)
            if inTrade then render(sync) end
        end)
    end, function()
        pickMenu.close(true, true, false)
        if inTrade then render(sync) end
    end)
end

RegisterNetEvent('dyn_trade:invited', function(fromName)
    local menu = MenuData.Open('default', GetCurrentResourceName(), 'dyn_trade_invite', {
        title = '取引の申し込み',
        elements = { { label = fromName .. ' から取引の申し込みが来ています', value = false } },
    }, function() end, function() end)

    menu.displayInput({
        inputType = 'yesno',
        header = '取引の申し込み',
        description = ('%s から取引を申し込まれました。受けますか？'):format(fromName),
        buttons = { confirm = 'はい', cancel = 'いいえ' },
    }, function(response)
        menu.close(true, true, false)
        TriggerServerEvent('dyn_trade:respond', response == true)
    end, function()
        menu.close(true, true, false)
        TriggerServerEvent('dyn_trade:respond', false)
    end)
end)

RegisterNetEvent('dyn_trade:open', function()
    -- 実体は次に飛んでくる dyn_trade:sync が作る。ここでは何もしない
end)

RegisterNetEvent('dyn_trade:sync', function(sync)
    render(sync)
end)

RegisterNetEvent('dyn_trade:closed', function(reason)
    inTrade = false
    closeTradeMenu()
    if reason then TriggerEvent('vorp:TipRight', reason, Config.notifyDuration or 4000) end
end)
