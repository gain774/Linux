--[[
  国庫。dyn_economy の取引通知を拾って税を記帳する。

  価格エンジンには何も要求しない。取引の通知を一方向に受けるだけなので、
  このリソースを起動しなければ挙動は従来どおり（スプレッド分は消滅する）に戻る。
]]

local balance = 0.0

local function money(v) return ('%s%.2f'):format(TreasuryConfig.label, v or 0) end

--- 記帳を 1 件書く。DB が無ければメモリ上の残高だけ動かす。
local function record(entry)
    if not entry then return end
    balance = TreasuryMath.apply(balance, entry)
    if not TreasuryDb.isReady() then return end
    TreasuryDb.insert([[
        INSERT INTO dyn_treasury_ledger
            (created_at, direction, source, amount, balance_after, ref_type, ref_id, note)
        VALUES (NOW(), ?, ?, ?, ?, ?, ?, ?)
    ]], { entry.direction, entry.source, entry.amount, balance,
          entry.refType, entry.refId, entry.note })
end

AddEventHandler('dyn_economy:committed', function(tx)
    if not TreasuryConfig.enabled then return end
    record(TreasuryMath.entryForCommit(tx))
end)

AddEventHandler('dyn_economy:voided', function(tx)
    if not TreasuryConfig.enabled then return end
    record(TreasuryMath.entryForVoid(tx))
end)

--- 直近 30 日の税収。準備金の計算に使う
local function monthlyIncome()
    if not TreasuryDb.isReady() then return 0 end
    local row = TreasuryDb.query([[
        SELECT COALESCE(SUM(CASE WHEN direction = 'in' THEN amount ELSE -amount END), 0) AS total
        FROM dyn_treasury_ledger
        WHERE created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
    ]])
    return row and row[1] and tonumber(row[1].total) or 0
end

exports('GetBalance', function() return balance end)

--- 補助金に回せる額（§9.2）。補助金の実装はまだ無いが、
--- 予算がいくらになるのかを先に見られるようにしておく。
exports('GetSpendable', function()
    local free, reserve = TreasuryMath.spendable(balance, monthlyIncome(), TreasuryConfig.reserveMonths)
    return { spendable = free, reserve = reserve, balance = balance }
end)

RegisterCommand('treasury', function(src)
    if src ~= 0 and not IsPlayerAceAllowed(tostring(src), 'dyn_economy.admin') then return end
    local function reply(msg)
        if src == 0 then print(msg)
        else TriggerClientEvent('chat:addMessage', src, { args = { 'treasury', msg } }) end
    end

    local income = monthlyIncome()
    local free, reserve = TreasuryMath.spendable(balance, income, TreasuryConfig.reserveMonths)
    reply(('国庫 %s / 直近30日の税収 %s'):format(money(balance), money(income)))
    reply(('  準備金 %s（%.1f か月分） / 補助金に回せる額 %s')
        :format(money(reserve), TreasuryConfig.reserveMonths, money(free)))

    if TreasuryDb.isReady() then
        local rows = TreasuryDb.query([[
            SELECT source, SUM(amount) AS total, COUNT(*) AS n
            FROM dyn_treasury_ledger
            WHERE created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
            GROUP BY source ORDER BY total DESC
        ]]) or {}
        for _, r in ipairs(rows) do
            reply(('  %-14s %10s  (%d 件)'):format(r.source, money(tonumber(r.total)), r.n))
        end
    end
end, false)

CreateThread(function()
    Wait(1000)
    if not TreasuryConfig.enabled then
        print('[dyn_treasury] 無効（TreasuryConfig.enabled = false）')
        return
    end

    if MySQL then
        TreasuryDb.setReady(true)
        if TreasuryConfig.autoMigrate then TreasuryDb.migrate() end
        local row = TreasuryDb.query('SELECT balance_after FROM dyn_treasury_ledger ORDER BY id DESC LIMIT 1')
        balance = (row and row[1] and tonumber(row[1].balance_after)) or 0.0
    else
        print('^3[dyn_treasury] oxmysql が無いためメモリ上だけで動作します^0')
    end

    print(('[dyn_treasury] 起動完了: 国庫 %s'):format(money(balance)))
end)
