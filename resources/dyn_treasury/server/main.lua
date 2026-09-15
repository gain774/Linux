--[[
  国庫。dyn_economy の取引通知を拾って税を記帳する。

  価格エンジンには何も要求しない。取引の通知を一方向に受けるだけなので、
  このリソースを起動しなければ挙動は従来どおり（スプレッド分は消滅する）に戻る。
]]

local balance = 0.0

--[[
  店舗ID → 所在州。dyn_shop などが起動時に RegisterShopState を呼んで登録する。
  dyn_treasury は dyn_shop を知らなくてよいように、あくまで「登録があれば使う」
  という一方向の受け口にしてある（登録が無ければ全て defaultState 扱い）。
]]
local shopState = {}

local function money(v) return ('%s%.2f'):format(TreasuryConfig.label, v or 0) end

exports('RegisterShopState', function(shopId, state)
    if not shopId or not state then return false end
    shopState[shopId] = state
    return true
end)

exports('CurrentWeekLabel', function() return TreasuryMath.weekLabel(os.time()) end)

--- 記帳を 1 件書く。DB が無ければメモリ上の残高だけ動かす。
local function record(entry)
    if not entry then return end
    balance = TreasuryMath.apply(balance, entry)
    if not TreasuryDb.isReady() then return end
    local period = TreasuryMath.weekLabel(os.time())
    TreasuryDb.insert([[
        INSERT INTO dyn_treasury_ledger
            (created_at, direction, source, amount, balance_after, ref_type, ref_id, note, state, period)
        VALUES (NOW(), ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { entry.direction, entry.source, entry.amount, balance,
          entry.refType, entry.refId, entry.note, entry.state or TreasuryConfig.defaultState, period })
end

AddEventHandler('dyn_economy:committed', function(tx)
    if not TreasuryConfig.enabled then return end
    local state = (tx and shopState[tx.shop]) or TreasuryConfig.defaultState
    record(TreasuryMath.entryForCommit(tx, state))
end)

AddEventHandler('dyn_economy:voided', function(tx)
    if not TreasuryConfig.enabled then return end
    local state = (tx and shopState[tx.shop]) or TreasuryConfig.defaultState
    record(TreasuryMath.entryForVoid(tx, state))
end)

--- dyn_trade（個人間取引）は入っていなくても構わない。入っていれば手数料を記帳する。
--- どの州で成立したかは特定できないので defaultState（既定 'unassigned'）で記帳する
AddEventHandler('dyn_trade:fee', function(payload)
    if not TreasuryConfig.enabled then return end
    record(TreasuryMath.entryForP2PFee(payload, TreasuryConfig.defaultState))
end)

--- dyn_guild（組合・補助金）は入っていなくても構わない。補助金を払ったら
--- 国庫からの出金として記帳する（§9.2: 流通量が増えるので、国庫側は減らす）
AddEventHandler('dyn_guild:subsidyPaid', function(payload)
    if not TreasuryConfig.enabled then return end
    record(TreasuryMath.entryForSubsidy(payload, payload and payload.state))
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

--[[
  指定した州・週の純税収（in - out）。省略時は今週。dyn_guild が
  週次補助金予算の原資として使う。DB が無ければ常に 0（積み上げも予算も無し）
]]
exports('GetStateWeekIncome', function(state, period)
    if not TreasuryDb.isReady() then return 0 end
    period = period or TreasuryMath.weekLabel(os.time())
    local row = TreasuryDb.query([[
        SELECT COALESCE(SUM(CASE WHEN direction = 'in' THEN amount ELSE -amount END), 0) AS total
        FROM dyn_treasury_ledger
        WHERE state = ? AND period = ?
    ]], { state, period })
    return row and row[1] and tonumber(row[1].total) or 0
end)

--- 直近の週について、州ごとの純税収一覧（管理者向け表示・ダッシュボード用）
local function stateBreakdown(period)
    if not TreasuryDb.isReady() then return {} end
    period = period or TreasuryMath.weekLabel(os.time())
    local rows = TreasuryDb.query([[
        SELECT state, period,
               SUM(CASE WHEN direction = 'in' THEN amount ELSE -amount END) AS total,
               COUNT(*) AS n
        FROM dyn_treasury_ledger
        WHERE period = ?
        GROUP BY state ORDER BY total DESC
    ]], { period }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = { state = r.state, period = r.period, total = tonumber(r.total), count = tonumber(r.n) }
    end
    return out
end
exports('GetStateBreakdown', stateBreakdown)

--- 補助金に回せる額（§9.2）。補助金の実装はまだ無いが、
--- 予算がいくらになるのかを先に見られるようにしておく。
exports('GetSpendable', function()
    local free, reserve = TreasuryMath.spendable(balance, monthlyIncome(), TreasuryConfig.reserveMonths)
    return { spendable = free, reserve = reserve, balance = balance }
end)

--- 国庫の状態をテキスト行の配列にする。/treasury コマンドと管理者ダッシュボードで共有する
local function buildTreasuryReport()
    local lines = {}
    local income = monthlyIncome()
    local free, reserve = TreasuryMath.spendable(balance, income, TreasuryConfig.reserveMonths)
    lines[#lines + 1] = ('国庫 %s / 直近30日の税収 %s'):format(money(balance), money(income))
    lines[#lines + 1] = ('  準備金 %s（%.1f か月分） / 補助金に回せる額 %s')
        :format(money(reserve), TreasuryConfig.reserveMonths, money(free))

    if TreasuryDb.isReady() then
        local rows = TreasuryDb.query([[
            SELECT source, SUM(amount) AS total, COUNT(*) AS n
            FROM dyn_treasury_ledger
            WHERE created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
            GROUP BY source ORDER BY total DESC
        ]]) or {}
        for _, r in ipairs(rows) do
            lines[#lines + 1] = ('  %-14s %10s  (%d 件)'):format(r.source, money(tonumber(r.total)), r.n)
        end

        local period = TreasuryMath.weekLabel(os.time())
        lines[#lines + 1] = ('今週（%s）の州別税収:'):format(period)
        for _, r in ipairs(stateBreakdown(period)) do
            lines[#lines + 1] = ('  %-16s %10s  (%d 件)'):format(r.state, money(r.total), r.count)
        end
    end
    return lines
end

exports('BuildReport', buildTreasuryReport)

RegisterCommand('treasury', function(src)
    if src ~= 0 and not IsPlayerAceAllowed(tostring(src), 'dyn_economy.admin') then return end
    local function reply(msg)
        if src == 0 then print(msg)
        else TriggerClientEvent('chat:addMessage', src, { args = { 'treasury', msg } }) end
    end
    for _, line in ipairs(buildTreasuryReport()) do reply(line) end
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
