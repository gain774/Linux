--[[
  組合・補助金（§9.3〜9.5）。

  NPC は置かない。自己申告 → 運営承認。承認されるまでは補助が出ないだけで、
  組合として名乗って活動すること自体は自由。

  州ごと・週ごとに税収を分ける（ユーザー要望）。dyn_treasury が集計した
  「その州・その週の純税収」を読み、その週分だけを補助金の原資にする。
  国庫の全体像（GetBalance など）には一切触らない — 州別週次の予算は
  国庫本体とは別枠の、この機能専用の配分ロジック。
]]

local ACE = 'dyn_economy.admin'

local function isAdmin(src)
    return src == 0 or IsPlayerAceAllowed(tostring(src), ACE)
end

local function money(v) return ('%s%.2f'):format(GuildConfig.label or '$', v or 0) end

local function reply(src, msg)
    if src == 0 then print(msg)
    else TriggerClientEvent('chat:addMessage', src, { args = { 'guild', msg } }) end
end

local function currentPeriod() return GuildMath.weekLabel(os.time()) end

-- ============================== 出荷実績の記録（accrual の原資） ==============================

--[[
  NPC への売却をすべて拾って積む。組合に入っているかどうかはここでは見ない
  （後から /guild join しても、入る前の分は補助対象にならないよう、
  支払い計算の側でメンバーの加入日と突き合わせて絞る）。
]]
AddEventHandler('dyn_economy:committed', function(tx)
    if not GuildConfig.enabled or not GuildDb.isReady() then return end
    if not tx or tx.direction ~= 'sell' or not tx.identifier or not tx.item then return end
    local qty = tonumber(tx.qty)
    if not qty or qty <= 0 then return end

    GuildDb.execute([[
        INSERT INTO dyn_guild_shipments (identifier, item, period, qty)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE qty = qty + VALUES(qty)
    ]], { tx.identifier, tx.item, currentPeriod(), qty })

    -- 組合員なら最終活動時刻も更新する（90日無活動失効の判定に使う）
    local row = GuildDb.query([[
        SELECT g.id FROM dyn_guilds g
        JOIN dyn_guild_members m ON m.guild_id = g.id
        WHERE m.identifier = ? AND g.status = 'approved'
    ]], { tx.identifier })
    if row and row[1] then
        GuildDb.execute('UPDATE dyn_guilds SET last_active = NOW() WHERE id = ?', { row[1].id })
    end
end)

-- ============================== 参照クエリ ==============================

local function guildOfIdentifier(identifier)
    local rows = GuildDb.query([[
        SELECT g.*, m.role, m.joined_at FROM dyn_guilds g
        JOIN dyn_guild_members m ON m.guild_id = g.id
        WHERE m.identifier = ?
    ]], { identifier })
    return rows and rows[1] or nil
end

local function memberCount(guildId)
    local rows = GuildDb.query('SELECT COUNT(*) AS n FROM dyn_guild_members WHERE guild_id = ?', { guildId })
    return rows and rows[1] and tonumber(rows[1].n) or 0
end

local function approvedCountInState(state)
    local rows = GuildDb.query("SELECT COUNT(*) AS n FROM dyn_guilds WHERE state = ? AND status = 'approved'", { state })
    return rows and rows[1] and tonumber(rows[1].n) or 0
end

-- ============================== プレイヤーコマンド ==============================

local function cmdApply(src, args)
    local identifier = GuildAdapter.getIdentifier(src)
    if not identifier then return reply(src, 'キャラクターを読み込めませんでした') end
    if guildOfIdentifier(identifier) then return reply(src, 'すでに組合に所属しています（1キャラ1組合）') end

    local name, category, state = args[1], args[2], args[3]
    local ok, err = GuildMath.validateApplication(
        { name = name, category = category, state = state, founder = identifier },
        GuildConfig.categories, GuildConfig.states)
    if not ok then
        return reply(src, ('使い方: /guild apply <名称> <カテゴリ: %s> <州: %s>'):format(
            table.concat(GuildConfig.categories, '/'), table.concat(GuildConfig.states, '/')))
    end

    if not GuildDb.isReady() then return reply(src, 'DB に接続できないため申請できません') end
    local existing = GuildDb.query('SELECT id FROM dyn_guilds WHERE name = ?', { name })
    if existing and existing[1] then return reply(src, 'その名称はすでに使われています') end

    local id = GuildDb.insert([[
        INSERT INTO dyn_guilds (name, category, purpose, founder, state, status, applied_at, last_active)
        VALUES (?, ?, ?, ?, ?, 'pending', NOW(), NOW())
    ]], { name, category, nil, identifier, state })
    if not id then return reply(src, '申請に失敗しました') end

    GuildDb.execute([[
        INSERT INTO dyn_guild_members (guild_id, identifier, role, joined_at) VALUES (?, ?, 'founder', NOW())
    ]], { id, identifier })

    reply(src, ('申請しました（#%s）。承認には最低 %d 人のメンバーが必要です。/guild join %s で仲間を誘ってください')
        :format(tostring(id), GuildConfig.minFounders, tostring(id)))
end

local function cmdJoin(src, args)
    local identifier = GuildAdapter.getIdentifier(src)
    if not identifier then return reply(src, 'キャラクターを読み込めませんでした') end
    if guildOfIdentifier(identifier) then return reply(src, 'すでに組合に所属しています（1キャラ1組合）') end

    local guildId = tonumber(args[1])
    if not guildId then return reply(src, '使い方: /guild join <id>') end
    if not GuildDb.isReady() then return reply(src, 'DB に接続できません') end

    local rows = GuildDb.query('SELECT id, name, status FROM dyn_guilds WHERE id = ?', { guildId })
    local guild = rows and rows[1]
    if not guild then return reply(src, 'その組合は存在しません') end
    if guild.status == 'rejected' or guild.status == 'dissolved' then
        return reply(src, 'その組合は活動していません')
    end

    local inserted = GuildDb.execute([[
        INSERT INTO dyn_guild_members (guild_id, identifier, role, joined_at) VALUES (?, ?, 'member', NOW())
    ]], { guildId, identifier })
    if not inserted then return reply(src, '加入に失敗しました（既に別の組合にいませんか）') end
    reply(src, ('%s に加入しました'):format(guild.name))
end

local function cmdLeave(src)
    local identifier = GuildAdapter.getIdentifier(src)
    if not identifier then return reply(src, 'キャラクターを読み込めませんでした') end
    local guild = guildOfIdentifier(identifier)
    if not guild then return reply(src, 'どの組合にも所属していません') end
    GuildDb.execute('DELETE FROM dyn_guild_members WHERE identifier = ?', { identifier })
    reply(src, ('%s を脱退しました'):format(guild.name))
end

local function cmdInfo(src, args)
    local guild
    if args[1] then
        local rows = GuildDb.query('SELECT * FROM dyn_guilds WHERE id = ?', { tonumber(args[1]) })
        guild = rows and rows[1]
    else
        local identifier = GuildAdapter.getIdentifier(src)
        guild = identifier and guildOfIdentifier(identifier)
    end
    if not guild then return reply(src, '組合が見つかりません（/guild info <id> か、自分が所属している組合が対象です）') end

    reply(src, ('#%s %s [%s / %s] 状態:%s'):format(
        tostring(guild.id), guild.name, guild.category, guild.state, guild.status))
    reply(src, ('  発起人 %s / メンバー %d 人'):format(guild.founder, memberCount(guild.id)))
    if guild.status == 'pending' then
        reply(src, ('  承認には最低 %d 人必要（現在 %d 人）'):format(GuildConfig.minFounders, memberCount(guild.id)))
    elseif guild.status == 'rejected' then
        reply(src, ('  却下理由: %s'):format(guild.reject_reason or '(記載なし)'))
    end
end

local function cmdSubsidy(src)
    local identifier = GuildAdapter.getIdentifier(src)
    if not identifier then return reply(src, 'キャラクターを読み込めませんでした') end
    local guild = guildOfIdentifier(identifier)
    if not guild then return reply(src, 'どの組合にも所属していません') end
    if guild.status ~= 'approved' then return reply(src, 'この組合はまだ承認されていません（補助対象外）') end

    local period = currentPeriod()
    local income = exports.dyn_treasury and exports.dyn_treasury:GetStateWeekIncome(guild.state, period) or 0
    local budget = GuildMath.weeklyBudget(income, GuildConfig.subsidy.weeklyBudgetRatio)
    local cap = GuildMath.perGuildCap(budget, approvedCountInState(guild.state))

    reply(src, ('%s（%s）今週(%s)の見込み: 州の週次予算 %s / 承認組合数で割った上限 %s')
        :format(guild.name, guild.state, period, money(budget), money(cap)))

    local paid = GuildDb.query([[
        SELECT COALESCE(SUM(amount), 0) AS total FROM dyn_subsidy_payouts
        WHERE guild_id = ? AND period = ?
    ]], { guild.id, period })
    reply(src, ('  今週すでに支払い済み: %s（accrual は週の切り替わりでまとめて支払われます）')
        :format(money(paid and paid[1] and tonumber(paid[1].total) or 0)))
end

-- ============================== 運営コマンド ==============================

--[[
  以下 approve/reject/revoke の中身は、チャットコマンドと管理者ダッシュボード
  (dyn_admin, NUI) の両方から呼べるように export もしている。「誰が承認したか」
  の識別子だけ呼び出し側が用意して渡す（コンソールなら 'console'、NUI 経由なら
  そのプレイヤーの識別子）。
]]
local function approveGuild(guildId, adminIdentifier)
    if not guildId then return false, 'bad_id' end
    local rows = GuildDb.query("SELECT * FROM dyn_guilds WHERE id = ? AND status = 'pending'", { guildId })
    local guild = rows and rows[1]
    if not guild then return false, 'not_found' end
    if not GuildMath.canApprove(memberCount(guildId), GuildConfig.minFounders) then
        return false, 'not_enough_members'
    end
    GuildDb.execute([[
        UPDATE dyn_guilds SET status = 'approved', decided_at = NOW(), decided_by = ? WHERE id = ?
    ]], { adminIdentifier, guildId })
    return true, guild
end

local function rejectGuild(guildId, reason, adminIdentifier)
    if not guildId then return false, 'bad_id' end
    local rows = GuildDb.query("SELECT * FROM dyn_guilds WHERE id = ? AND status = 'pending'", { guildId })
    local guild = rows and rows[1]
    if not guild then return false, 'not_found' end
    GuildDb.execute([[
        UPDATE dyn_guilds SET status = 'rejected', decided_at = NOW(), decided_by = ?, reject_reason = ? WHERE id = ?
    ]], { adminIdentifier, (reason and reason ~= '') and reason or nil, guildId })
    return true, guild
end

local function revokeGuild(guildId, reason, adminIdentifier)
    if not guildId then return false, 'bad_id' end
    local rows = GuildDb.query("SELECT * FROM dyn_guilds WHERE id = ? AND status = 'approved'", { guildId })
    local guild = rows and rows[1]
    if not guild then return false, 'not_found' end
    GuildDb.execute([[
        UPDATE dyn_guilds SET status = 'revoked', decided_at = NOW(), decided_by = ?, reject_reason = ? WHERE id = ?
    ]], { adminIdentifier, (reason and reason ~= '') and reason or nil, guildId })
    return true, guild
end

--- 承認待ち一覧（メンバー数つき）。/guild list pending とダッシュボードで共有する
local function pendingSummary()
    local rows = GuildDb.query("SELECT id, name, category, state, founder, applied_at FROM dyn_guilds WHERE status = 'pending' ORDER BY applied_at") or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = { id = r.id, name = r.name, category = r.category, state = r.state,
                           founder = r.founder, memberCount = memberCount(r.id), appliedAt = r.applied_at }
    end
    return out
end

local function adminIdentifierFor(src)
    return (src == 0) and 'console' or (GuildAdapter.getIdentifier(src) or tostring(src))
end

local function cmdListPending(src)
    if not isAdmin(src) then return reply(src, '権限がありません') end
    local list = pendingSummary()
    if #list == 0 then return reply(src, '承認待ちの申請はありません') end
    for _, g in ipairs(list) do
        reply(src, ('#%s %s [%s/%s] 発起人:%s メンバー%d人'):format(
            tostring(g.id), g.name, g.category, g.state, g.founder, g.memberCount))
    end
end

local APPROVE_ERRORS = {
    bad_id = '使い方: /guild approve <id>', not_found = '承認待ちの申請が見つかりません',
}
local function cmdApprove(src, args)
    if not isAdmin(src) then return reply(src, '権限がありません') end
    local ok, result = approveGuild(tonumber(args[1]), adminIdentifierFor(src))
    if not ok then
        if result == 'not_enough_members' then
            return reply(src, ('人数が足りません（%d 人必要）'):format(GuildConfig.minFounders))
        end
        return reply(src, APPROVE_ERRORS[result] or ('失敗: ' .. tostring(result)))
    end
    reply(src, ('%s を承認しました'):format(result.name))
end

local function cmdReject(src, args)
    if not isAdmin(src) then return reply(src, '権限がありません') end
    local guildId = tonumber(args[1])
    local reason = table.concat(args, ' ', 2)
    if not guildId then return reply(src, '使い方: /guild reject <id> <理由>') end
    local ok, result = rejectGuild(guildId, reason, adminIdentifierFor(src))
    if not ok then return reply(src, '承認待ちの申請が見つかりません') end
    reply(src, ('%s を却下しました'):format(result.name))
end

local function cmdRevoke(src, args)
    if not isAdmin(src) then return reply(src, '権限がありません') end
    local guildId = tonumber(args[1])
    local reason = table.concat(args, ' ', 2)
    if not guildId then return reply(src, '使い方: /guild revoke <id> <理由>') end
    local ok, result = revokeGuild(guildId, reason, adminIdentifierFor(src))
    if not ok then return reply(src, '承認済みの組合が見つかりません') end
    reply(src, ('%s の承認を取り消しました'):format(result.name))
end

--- ダッシュボード（dyn_admin）向け。承認者の識別子は呼び出し側が用意する
exports('ListPendingGuilds', pendingSummary)
exports('ListApprovedGuilds', function()
    local rows = GuildDb.query("SELECT id, name, category, state FROM dyn_guilds WHERE status = 'approved' ORDER BY name") or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = { id = r.id, name = r.name, category = r.category, state = r.state, memberCount = memberCount(r.id) }
    end
    return out
end)
exports('ApproveGuild', function(guildId, adminIdentifier) return approveGuild(guildId, adminIdentifier or 'admin_ui') end)
exports('RejectGuild', function(guildId, reason, adminIdentifier) return rejectGuild(guildId, reason, adminIdentifier or 'admin_ui') end)
exports('RevokeGuild', function(guildId, reason, adminIdentifier) return revokeGuild(guildId, reason, adminIdentifier or 'admin_ui') end)

RegisterCommand('guild', function(src, args)
    if not GuildConfig.enabled then return reply(src, '組合機能は無効です（GuildConfig.enabled = false）') end
    local sub = args[1]
    local rest = {}
    for i = 2, #args do rest[#rest + 1] = args[i] end

    if sub == 'apply'   then return cmdApply(src, rest) end
    if sub == 'join'    then return cmdJoin(src, rest) end
    if sub == 'leave'   then return cmdLeave(src) end
    if sub == 'info'    then return cmdInfo(src, rest) end
    if sub == 'subsidy' then return cmdSubsidy(src) end
    if sub == 'list' and rest[1] == 'pending' then return cmdListPending(src) end
    if sub == 'approve' then return cmdApprove(src, rest) end
    if sub == 'reject'  then return cmdReject(src, rest) end
    if sub == 'revoke'  then return cmdRevoke(src, rest) end

    reply(src, '使い方: /guild apply|join|leave|info|subsidy <名称> ... （運営: list pending / approve / reject / revoke）')
end, false)

-- ============================== 週次の実績払い（accrual） ==============================

--[[
  1人1日あたりの補助上限。config で明示が無ければ dyn_economy のアンカー価格から導出する
]]
local function memberDailyCap()
    local anchorPrice
    if GetResourceState('dyn_economy') == 'started' then
        local ok, info = pcall(function() return exports.dyn_economy:GetItemInfo('corn') end)
        if ok and info then anchorPrice = info.npcBuy end
    end
    return GuildMath.perPersonDailyCap(
        GuildConfig.subsidy.perPersonDailyCap, anchorPrice,
        GuildConfig.subsidy.anchorMultiplier, GuildConfig.subsidy.fallbackDailyCap)
end

--- period 週の出荷実績のうち、guildId のメンバーの分だけを抜き出す
local function shipmentsForGuild(guildId, period)
    local rows = GuildDb.query([[
        SELECT s.identifier, s.item, s.qty, m.joined_at
        FROM dyn_guild_shipments s
        JOIN dyn_guild_members m ON m.identifier = s.identifier AND m.guild_id = ?
        WHERE s.period = ?
    ]], { guildId, period }) or {}
    return rows
end

local function subsidyRulesForGuild(guildId)
    local rows = GuildDb.query('SELECT * FROM dyn_guild_subsidy_rules WHERE guild_id = ?', { guildId }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[r.item] = { unitAmount = tonumber(r.unit_amount), enabled = (r.enabled == 1 or r.enabled == true) }
    end
    return out
end

--- period 週について、guild 1 件分の支払いを確定させる
local function payoutGuildForPeriod(guild, period, dailyCap)
    local income = exports.dyn_treasury and exports.dyn_treasury:GetStateWeekIncome(guild.state, period) or 0
    local budget = GuildMath.weeklyBudget(income, GuildConfig.subsidy.weeklyBudgetRatio)
    local guildCap = GuildMath.perGuildCap(budget, approvedCountInState(guild.state))
    if guildCap <= 0 then return 0 end

    local shipRows = shipmentsForGuild(guild.id, period)
    if #shipRows == 0 then return 0 end

    local shipments, members = {}, {}
    local nowT = os.time()
    for _, r in ipairs(shipRows) do
        shipments[#shipments + 1] = { identifier = r.identifier, item = r.item, qty = tonumber(r.qty) }
        local joinedAtUnix = r.joined_at and os.time({
            year = tonumber(r.joined_at:sub(1, 4)), month = tonumber(r.joined_at:sub(6, 7)),
            day = tonumber(r.joined_at:sub(9, 10)), hour = tonumber(r.joined_at:sub(12, 13)) or 0,
            min = tonumber(r.joined_at:sub(15, 16)) or 0, sec = tonumber(r.joined_at:sub(18, 19)) or 0,
        }) or nowT
        members[r.identifier] = { eligible = GuildMath.isWaitOver(joinedAtUnix, nowT, GuildConfig.joinWaitDays) }
    end

    local result = GuildMath.accrualPayout(shipments, subsidyRulesForGuild(guild.id), members,
        { memberDailyCap = dailyCap, guildWeeklyCap = guildCap })
    if result.total <= 0 then return 0 end

    for identifier, amount in pairs(result.byMember) do
        -- オンラインなら addCurrency、オフラインなら characters テーブルへ直接加算する
        -- （§6.4 のセンサスと同じく、VORP のキャラクターテーブルへの直接アクセスは
        --   このプロジェクトで既に使っている手段）
        local paidOnline = false
        for _, playerId in ipairs(GetPlayers()) do
            if GuildAdapter.getIdentifier(tonumber(playerId)) == identifier then
                GuildAdapter.addMoney(tonumber(playerId), amount)
                GuildAdapter.notify(tonumber(playerId), ('組合補助金 %s を受け取りました（%s）'):format(money(amount), period))
                paidOnline = true
                break
            end
        end
        if not paidOnline then
            GuildDb.execute('UPDATE characters SET money = money + ? WHERE charidentifier = ?', { amount, identifier })
        end
    end

    for _, line in ipairs(result.lines) do
        GuildDb.insert([[
            INSERT INTO dyn_subsidy_payouts (guild_id, identifier, item, qty, amount, mode, period, paid_at)
            VALUES (?, ?, ?, ?, ?, 'accrual', ?, NOW())
        ]], { guild.id, line.identifier, line.item, line.qty, line.amount, period })
    end

    TriggerEvent('dyn_guild:subsidyPaid', { amount = result.total, state = guild.state, note = guild.name .. ' 週次補助' })
    return result.total
end

--- 承認済みの全組合について、指定した週の分をまとめて支払う
local function runWeeklyPayout(period)
    if not GuildConfig.enabled or not GuildDb.isReady() then return end
    if GuildConfig.subsidy.mode ~= 'accrual' then return end -- instant モードは購入時に即時処理（別経路、§9.4 モードA・未実装）

    local guilds = GuildDb.query("SELECT * FROM dyn_guilds WHERE status = 'approved'") or {}
    local cap = memberDailyCap()
    local paidTotal = 0
    for _, guild in ipairs(guilds) do
        paidTotal = paidTotal + payoutGuildForPeriod(guild, period, cap)
    end
    if paidTotal > 0 then
        print(('[dyn_guild] %s の週次補助金を支払いました（合計 %s）'):format(period, money(paidTotal)))
    end
end

--- 90 日間、出荷（last_active 更新）が無い承認済み組合を自動失効させる
local function expireInactiveGuilds()
    if not GuildDb.isReady() then return end
    local guilds = GuildDb.query("SELECT id, name, last_active FROM dyn_guilds WHERE status = 'approved'") or {}
    local nowT = os.time()
    for _, g in ipairs(guilds) do
        if g.last_active then
            local lastT = os.time({
                year = tonumber(g.last_active:sub(1, 4)), month = tonumber(g.last_active:sub(6, 7)),
                day = tonumber(g.last_active:sub(9, 10)), hour = tonumber(g.last_active:sub(12, 13)) or 0,
                min = tonumber(g.last_active:sub(15, 16)) or 0, sec = tonumber(g.last_active:sub(18, 19)) or 0,
            })
            if GuildMath.isInactive(lastT, nowT, GuildConfig.inactivityDays) then
                GuildDb.execute("UPDATE dyn_guilds SET status = 'dissolved', decided_at = NOW(), reject_reason = '90日間無活動のため自動失効' WHERE id = ?", { g.id })
                print(('[dyn_guild] %s を無活動のため自動失効させました'):format(g.name))
            end
        end
    end
end

RegisterCommand('dyn_guild_payout', function(src, args)
    -- 動作確認・取りこぼし救済用の手動トリガ。通常は週の切り替わりで自動実行される
    if not isAdmin(src) then return reply(src, '権限がありません') end
    local period = args[1] or currentPeriod()
    runWeeklyPayout(period)
    reply(src, ('%s の週次補助金処理を実行しました'):format(period))
end, false)

CreateThread(function()
    Wait(1500)
    if not GuildConfig.enabled then
        print('[dyn_guild] 無効（GuildConfig.enabled = false）')
        return
    end
    if not MySQL then
        print('^3[dyn_guild] oxmysql が無いため組合機能は動作しません^0')
        return
    end
    GuildDb.setReady(true)
    if GuildConfig.autoMigrate then GuildDb.migrate() end

    local row = GuildDb.query("SELECT v FROM dyn_guild_state WHERE k = 'last_paid_period'")
    local lastPaid = row and row[1] and row[1].v or nil
    print(('[dyn_guild] 起動完了（前回支払い済みの週: %s）'):format(lastPaid or '(なし)'))

    -- 週の切り替わりと無活動失効を 1 時間おきに確認する
    while true do
        local nowPeriod = currentPeriod()
        if lastPaid and lastPaid ~= nowPeriod then
            runWeeklyPayout(lastPaid)
        end
        if lastPaid ~= nowPeriod then
            GuildDb.execute([[
                INSERT INTO dyn_guild_state (k, v) VALUES ('last_paid_period', ?)
                ON DUPLICATE KEY UPDATE v = VALUES(v)
            ]], { nowPeriod })
            lastPaid = nowPeriod
        end
        expireInactiveGuilds()
        Wait(3600 * 1000)
    end
end)
