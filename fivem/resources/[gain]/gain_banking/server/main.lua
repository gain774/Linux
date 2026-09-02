-- 銀行・ATM のサーバー側。金額の判定と残高の増減は全てここで行う。

local core = exports['gain_core']

local function record(citizenid, kind, amount, counterparty, reason)
    MySQL.insert('INSERT INTO gain_transactions (citizenid, kind, amount, counterparty, reason) VALUES (?, ?, ?, ?, ?)', {
        citizenid, kind, amount, counterparty or '', reason or '',
    })
end

--- 金額として妥当な整数のみを返す。
local function amountOf(value)
    local amount = tonumber(value)
    if not amount then return nil end

    amount = math.floor(amount)
    if amount <= 0 or amount > Config.MoneyLimit then return nil end

    return amount
end

--- 銀行窓口の近くにいるか。ATM は座標をサーバー側で持てないため対象外。
local function nearBank(src)
    local coords = GetEntityCoords(GetPlayerPed(src))

    for _, bank in ipairs(BankConfig.Banks) do
        local distance = #(coords - vector3(bank.x, bank.y, bank.z))
        if distance <= BankConfig.Radius + 3.0 then
            return true
        end
    end

    return false
end

local function sendState(src)
    local player = core:GetPlayer(src)
    if not player then return end

    local history = MySQL.query.await([[
        SELECT kind, amount, counterparty, reason, created_at
        FROM gain_transactions WHERE citizenid = ?
        ORDER BY id DESC LIMIT ?
    ]], { player.citizenid, BankConfig.HistoryLimit }) or {}

    TriggerClientEvent('gain_banking:setState', src, {
        cash = player.money.cash,
        bank = player.money.bank,
        citizenid = player.citizenid,
        history = history,
    })
end

RegisterSafeEvent('gain_banking:requestState', { rate = { max = 5, per = 3000 } }, function(src)
    sendState(src)
end)

RegisterSafeEvent('gain_banking:deposit', { rate = { max = 5, per = 3000 } }, function(src, value)
    local amount = amountOf(value)
    if not amount then
        core:Notify(src, _L('invalid_amount'), 'error')
        return
    end

    local player = core:GetPlayer(src)
    if not player then return end

    if not core:RemoveMoney(src, 'cash', amount, 'deposit') then
        core:Notify(src, _L('not_enough_cash'), 'error')
        return
    end

    core:AddMoney(src, 'bank', amount, 'deposit')
    record(player.citizenid, 'deposit', amount, nil, '預け入れ')
    core:Notify(src, ('$%d を預け入れました。'):format(amount), 'success')
    sendState(src)
end)

RegisterSafeEvent('gain_banking:withdraw', { rate = { max = 5, per = 3000 } }, function(src, value)
    local amount = amountOf(value)
    if not amount then
        core:Notify(src, _L('invalid_amount'), 'error')
        return
    end

    local player = core:GetPlayer(src)
    if not player then return end

    if not core:RemoveMoney(src, 'bank', amount, 'withdraw') then
        core:Notify(src, _L('not_enough_bank'), 'error')
        return
    end

    core:AddMoney(src, 'cash', amount, 'withdraw')
    record(player.citizenid, 'withdraw', amount, nil, '引き出し')
    core:Notify(src, ('$%d を引き出しました。'):format(amount), 'success')
    sendState(src)
end)

RegisterSafeEvent('gain_banking:transfer', { rate = { max = 3, per = 5000 } }, function(src, targetId, value)
    local amount = amountOf(value)
    if not amount then
        core:Notify(src, _L('invalid_amount'), 'error')
        return
    end

    if amount < BankConfig.Transfer.min or amount > BankConfig.Transfer.max then
        core:Notify(src, ('送金額は $%d 〜 $%d です。'):format(
            BankConfig.Transfer.min, BankConfig.Transfer.max), 'error')
        return
    end

    if type(targetId) ~= 'string' or #targetId == 0 or #targetId > 16 then
        core:Notify(src, _L('player_not_found'), 'error')
        return
    end

    local player = core:GetPlayer(src)
    if not player then return end

    if targetId == player.citizenid then
        core:Notify(src, '自分自身には送金できません。', 'error')
        return
    end

    -- 送金は窓口のみ（ATM からは行えない）
    if not nearBank(src) then
        core:Notify(src, '送金は銀行の窓口で行ってください。', 'error')
        return
    end

    local fee = math.floor(amount * BankConfig.Transfer.feeRate)
    local total = amount + fee

    local target = core:GetPlayerByCitizenId(targetId)
    local offline = nil

    if not target then
        offline = MySQL.single.await('SELECT citizenid, firstname, lastname FROM gain_characters WHERE citizenid = ?', { targetId })
        if not offline then
            core:Notify(src, _L('player_not_found'), 'error')
            return
        end
    end

    if not core:RemoveMoney(src, 'bank', total, ('transfer:%s'):format(targetId)) then
        core:Notify(src, _L('not_enough_bank'), 'error')
        return
    end

    if target then
        core:AddMoney(target.source, 'bank', amount, ('transfer:%s'):format(player.citizenid))
        core:Notify(target.source, ('%s から $%d が振り込まれました。'):format(player.name, amount), 'success')
    else
        MySQL.update.await('UPDATE gain_characters SET bank = bank + ? WHERE citizenid = ?', { amount, targetId })
    end

    record(player.citizenid, 'transfer_out', amount, targetId, fee > 0 and ('手数料 $%d'):format(fee) or '送金')
    record(targetId, 'transfer_in', amount, player.citizenid, '入金')

    core:Log('money', '送金', {
        from = player.citizenid,
        to = targetId,
        amount = amount,
        fee = fee,
        offline = offline ~= nil,
    })

    core:Notify(src, ('$%d を送金しました。'):format(amount), 'success')
    sendState(src)
end)

-- 所持金の変化を UI に反映させる
AddEventHandler('gain_core:playerLoaded', function(src)
    sendState(src)
end)
