-- 所持金の操作。金額の判定はすべてここ（サーバー側）で行い、
-- クライアントからの数値は一切信用しない。

Money = {}

local ACCOUNTS = { cash = true, bank = true }

local function sanitize(amount)
    amount = tonumber(amount)
    if not amount then return nil end

    amount = math.floor(amount)
    if amount <= 0 then return nil end
    if amount > Config.MoneyLimit then return nil end

    return amount
end

--- 残高を取得する。
---@param player table
---@param account string 'cash' | 'bank'
---@return number
function Money.get(player, account)
    if not player or not ACCOUNTS[account] then return 0 end
    return player.money[account] or 0
end

--- 加算する。金額が不正なら false。
---@param player table
---@param account string
---@param amount number
---@param reason string|nil
---@return boolean ok
function Money.add(player, account, amount, reason)
    if not player or not ACCOUNTS[account] then return false end

    amount = sanitize(amount)
    if not amount then return false end

    local after = math.min((player.money[account] or 0) + amount, Config.MoneyLimit)
    player.money[account] = after
    player.sync()

    GainLog.write('money', '入金', {
        player = player.name,
        citizenid = player.citizenid,
        account = account,
        amount = amount,
        balance = after,
        reason = reason or '-',
    })

    return true
end

--- 減算する。残高不足なら false を返し、残高は変えない。
---@param player table
---@param account string
---@param amount number
---@param reason string|nil
---@return boolean ok
function Money.remove(player, account, amount, reason)
    if not player or not ACCOUNTS[account] then return false end

    amount = sanitize(amount)
    if not amount then return false end

    local before = player.money[account] or 0
    if before < amount then return false end

    player.money[account] = before - amount
    player.sync()

    GainLog.write('money', '出金', {
        player = player.name,
        citizenid = player.citizenid,
        account = account,
        amount = amount,
        balance = player.money[account],
        reason = reason or '-',
    })

    return true
end

--- 残高を直接指定する（管理操作用）。
---@param player table
---@param account string
---@param amount number
---@param reason string|nil
---@return boolean ok
function Money.set(player, account, amount, reason)
    if not player or not ACCOUNTS[account] then return false end

    amount = tonumber(amount)
    if not amount then return false end

    amount = math.max(0, math.min(math.floor(amount), Config.MoneyLimit))
    player.money[account] = amount
    player.sync()

    GainLog.write('money', '残高を設定', {
        player = player.name,
        citizenid = player.citizenid,
        account = account,
        balance = amount,
        reason = reason or '-',
    })

    return true
end
