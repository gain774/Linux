-- 銀行・ATM のサーバー側。金額の判定と残高の増減は全てここで行う。

local core = exports['gain_core']

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

    -- 口座の明細なので bank の動きだけを出す。
    -- 符号は delta から取る。kind の一覧を UI 側に持たせると、
    -- 種別が増えるたびに符号が狂う
    local history = MySQL.query.await([[
        SELECT kind, amount, delta, counterparty, reason, created_at
        FROM gain_transactions
        WHERE citizenid = ? AND account = 'bank'
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

    -- 現金と口座を同時に動かす。片方だけ反映されることが起きない
    local ok, err = core:MoveMoney(src, 'cash', 'bank', amount,
        { kind = 'deposit', reason = '預け入れ' })
    if not ok then
        core:Notify(src, err == 'limit' and '口座の上限を超えます。' or _L('not_enough_cash'), 'error')
        return
    end

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

    local ok, err = core:MoveMoney(src, 'bank', 'cash', amount,
        { kind = 'withdraw', reason = '引き出し' })
    if not ok then
        core:Notify(src, err == 'limit' and '現金の上限を超えます。' or _L('not_enough_bank'), 'error')
        return
    end

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

    -- 先に送金者から引く。台帳に載る額が実際に引かれた額（手数料込）になる。
    -- 手数料の内訳は reason に残す。
    if not core:RemoveMoney(src, 'bank', total, {
        kind = 'transfer_out', counterparty = targetId,
        reason = fee > 0 and ('送金 手数料 $%d'):format(fee) or '送金',
    }) then
        core:Notify(src, _L('not_enough_bank'), 'error')
        return
    end

    -- 相手がオンラインかオフラインかの判定と入金は gain_core に任せる。
    -- ここで存在確認の SELECT を挟むと、その yield の間に相手が接続して
    -- 競合する。判定と実行を1箇所に寄せることで窓を消す。
    local ok, err = core:AddMoneyOffline(targetId, 'bank', amount, {
        kind = 'transfer_in', counterparty = player.citizenid, reason = '入金',
    })

    if not ok then
        -- 入金できなければ全額返す。純差分が 0 になるので照合が通る。
        -- 返金にも失敗したら金が消える。必ず鳴らす
        local refunded = core:AddMoney(src, 'bank', total, {
            kind = 'refund', counterparty = targetId, reason = '送金の失敗を戻した',
        })
        if not refunded then
            core:Log('error', '返金にも失敗した。手動で補填が要る', {
                citizenid = player.citizenid, amount = total,
            })
        end
        core:Notify(src, err == 'limit' and '相手の口座が上限に達しています。'
            or _L('player_not_found'), 'error')
        core:Log('error', '送金の入金に失敗したので返金した', {
            from = player.citizenid, to = targetId, amount = amount, err = err,
        })
        return
    end

    local target = core:GetPlayerByCitizenId(targetId)
    if target then
        core:Notify(target.source, ('%s から $%d が振り込まれました。'):format(player.name, amount), 'success')
    end

    core:Log('money', '送金', {
        from = player.citizenid,
        to = targetId,
        amount = amount,
        fee = fee,
        offline = target == nil,
    })

    core:Notify(src, ('$%d を送金しました。'):format(amount), 'success')
    sendState(src)
end)

-- 所持金の変化を UI に反映させる
AddEventHandler('gain_core:playerLoaded', function(src)
    sendState(src)
end)
