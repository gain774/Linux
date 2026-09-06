-- オフライン相手への入金。
--
-- 以前はここを gain_banking が生 SQL で書いていて、3つの欠陥があった。
--   ・上限のクランプが無く、DB 上の残高が上限を超え得た
--   ・存在確認の SELECT で yield している間に相手が接続すると、
--     その後の自動保存がメモリ上の古い残高で DB を絶対上書きして送金分が消えた
--   ・書き込みの成否に関わらず履歴だけが残った
--
-- 2つ目は player.save() から cash / bank を外したことで構造的に消えている
-- （メモリは DB へ書き戻されない）。残るのは「オンラインの相手のメモリが
-- 古いままになる」ことなので、入金後に追いつかせる。

--- citizenid からオンラインのプレイヤーを引く。yield しない。
local function findOnline(citizenid)
    for _, p in pairs(GetGainPlayers()) do
        if p.citizenid == citizenid then return p end
    end
    return nil
end

--- オフラインでも届く入金。オンラインならそのまま Money を通す。
---@return boolean ok
---@return string|nil err  not_found / limit / failed
local function addOffline(citizenid, account, amount, m)
    if account ~= 'cash' and account ~= 'bank' then return false, 'invalid' end

    amount = tonumber(amount)
    if not amount or amount <= 0 then return false, 'invalid' end
    amount = math.floor(amount)

    local online = findOnline(citizenid)
    if online then
        return Money.add(online, account, amount, m), nil
    end

    -- 上限を条件に入れる。0 行なら上限超過か相手が存在しない
    local affected = MySQL.update.await(
        ('UPDATE gain_characters SET %s = %s + ? WHERE citizenid = ? AND %s + ? <= ?')
            :format(account, account, account),
        { amount, citizenid, amount, Config.MoneyLimit })

    if not affected or affected < 1 then
        local exists = MySQL.scalar.await(
            'SELECT citizenid FROM gain_characters WHERE citizenid = ?', { citizenid })
        return false, exists and 'limit' or 'not_found'
    end

    local balance = MySQL.scalar.await(
        ('SELECT %s FROM gain_characters WHERE citizenid = ?'):format(account), { citizenid }) or 0

    local kind, reason, counterparty = 'transfer_in', '', ''
    if type(m) == 'table' then
        kind = m.kind or kind
        reason = m.reason or ''
        counterparty = m.counterparty or ''
    end

    MySQL.insert([[
        INSERT INTO gain_transactions
            (citizenid, account, kind, amount, delta, balance, counterparty, reason)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], { citizenid, account, kind, amount, amount, balance, counterparty, reason })

    -- await の間に接続していたら、メモリを DB に追いつかせる。
    -- DB はもう更新済みなので、ここで台帳へ再度積んではいけない
    local late = findOnline(citizenid)
    if late then
        late.money[account] = balance
        late.sync()
    end

    return true
end

exports('AddMoneyOffline', addOffline)
