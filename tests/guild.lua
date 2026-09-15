--[[
  組合・補助金（dyn_guild/server/guild_math.lua）の純粋関数テスト。
    lua5.4 tests/guild.lua
]]
local root = (arg[0]:match('^(.*)/tests/guild%.lua$') or '.')
dofile(root .. '/resources/dyn_guild/server/guild_math.lua')

local passed, failed = 0, 0
local function ok(cond, name, extra)
    if cond then passed = passed + 1
    else failed = failed + 1; print(('  FAIL  %s%s'):format(name, extra and ('  -- '..extra) or '')) end
end
local function near(a, b, name, tol)
    tol = tol or 1e-6
    ok(a and math.abs(a - b) <= tol, name, ('expected %.4f got %s'):format(b, tostring(a)))
end
local function group(n) print(n) end

local CATS   = { 'farming', 'mining' }
local STATES = { 'new_hanover', 'west_elizabeth' }

group('GuildMath.validateApplication')
do
    local ok1, err1 = GuildMath.validateApplication(
        { name = '農協', category = 'farming', state = 'new_hanover', founder = 'char1' }, CATS, STATES)
    ok(ok1 == true, '妥当な申請は通る')
    ok(err1 == nil, 'エラーは無い')
end
do
    local ok2, err2 = GuildMath.validateApplication({ name = '', category = 'farming', state = 'new_hanover', founder = 'c' }, CATS, STATES)
    ok(ok2 == false and err2 == 'name_required', '名称が空なら拒否')
end
do
    local ok3, err3 = GuildMath.validateApplication({ name = 'x', category = 'weapons', state = 'new_hanover', founder = 'c' }, CATS, STATES)
    ok(ok3 == false and err3 == 'bad_category', '許可されていないカテゴリは拒否')
end
do
    local ok4, err4 = GuildMath.validateApplication({ name = 'x', category = 'farming', state = 'mars', founder = 'c' }, CATS, STATES)
    ok(ok4 == false and err4 == 'bad_state', '許可されていない州は拒否')
end
do
    local ok5, err5 = GuildMath.validateApplication({ name = 'x', category = 'farming', state = 'new_hanover' }, CATS, STATES)
    ok(ok5 == false and err5 == 'founder_required', '発起人が無ければ拒否')
end
ok(select(1, GuildMath.validateApplication(nil, CATS, STATES)) == false, 'nil を渡しても落ちない')

group('GuildMath.canApprove')
ok(GuildMath.canApprove(3, 3) == true, '人数がちょうど足りれば承認できる')
ok(GuildMath.canApprove(2, 3) == false, '人数が足りなければ承認できない')
ok(GuildMath.canApprove(nil, 3) == false, 'nil は 0 人扱い')

group('GuildMath.isInactive / isWaitOver')
do
    local now = 1000000
    ok(GuildMath.isInactive(now - 91 * 86400, now, 90) == true, '91日無活動は失効')
    ok(GuildMath.isInactive(now - 89 * 86400, now, 90) == false, '89日ならまだ失効しない')
    ok(GuildMath.isInactive(nil, now, 90) == false, 'last_active が無ければ失効判定しない')
end
do
    local now = 1000000
    ok(GuildMath.isWaitOver(now - 8 * 86400, now, 7) == true, '8日経てば待機終了')
    ok(GuildMath.isWaitOver(now - 6 * 86400, now, 7) == false, '6日ではまだ')
end

group('GuildMath.perPersonDailyCap')
near(GuildMath.perPersonDailyCap(25, nil, 20, 10), 25, '設定値があればそれを使う')
near(GuildMath.perPersonDailyCap(nil, 2.0, 20, 10), 40, '設定が無ければアンカー価格×倍率')
near(GuildMath.perPersonDailyCap(nil, nil, 20, 10), 10, 'どちらも無ければ最後のフォールバック')
near(GuildMath.perPersonDailyCap(0, 2.0, 20, 10), 40, '0 は「未設定」扱いでアンカーへフォールバックする')

group('GuildMath.weeklyBudget / perGuildCap')
near(GuildMath.weeklyBudget(1000, 0.4), 400, '週次予算 = 純税収 × 比率')
near(GuildMath.weeklyBudget(-100, 0.4), 0, '純税収がマイナスなら予算は 0')
near(GuildMath.perGuildCap(400, 4), 100, '承認組合数で均等割り')
near(GuildMath.perGuildCap(400, 0), 0, '承認組合が0なら上限も0（0除算しない）')

group('GuildMath.weekLabel（dyn_treasury と同一の式）')
do
    -- 年初からの経過日数を7で割った簡略連番なので、確実に同じブロックに入る
    -- 「1月1日」と「1月2日」で比較する（境界は月日に依らないため）
    local t1 = os.time({ year = 2026, month = 1, day = 1, hour = 12, min = 0, sec = 0 })
    local t2 = os.time({ year = 2026, month = 1, day = 2, hour = 12, min = 0, sec = 0 })
    ok(GuildMath.weekLabel(t1) == GuildMath.weekLabel(t2), '同じ週なら同じラベル')
    ok(GuildMath.weekLabel(t1):match('^2026%-W%d%d$') ~= nil, 'YYYY-Www 形式')
end

group('GuildMath.accrualPayout')
do
    local shipments = {
        { identifier = 'a', item = 'corn', qty = 100 },
        { identifier = 'b', item = 'corn', qty = 50 },
    }
    local rules = { corn = { unitAmount = 0.5, enabled = true } }
    local members = { a = { eligible = true }, b = { eligible = true } }
    local r = GuildMath.accrualPayout(shipments, rules, members, { memberDailyCap = 1000, guildWeeklyCap = 1000 })
    near(r.total, 75, '出荷量 × 単価の合計 (100*0.5 + 50*0.5)')
    near(r.byMember.a, 50, 'a の取り分')
    near(r.byMember.b, 25, 'b の取り分')
end
do
    -- 加入前の出荷は対象外（eligible = false）
    local shipments = { { identifier = 'a', item = 'corn', qty = 100 } }
    local rules = { corn = { unitAmount = 1.0, enabled = true } }
    local members = { a = { eligible = false } }
    local r = GuildMath.accrualPayout(shipments, rules, members, {})
    near(r.total, 0, '加入待機中のメンバーの出荷は補助対象外')
end
do
    -- ルールに無い品目・無効化されたルールは対象外
    local shipments = { { identifier = 'a', item = 'wheat', qty = 10 } }
    local rules = { corn = { unitAmount = 1.0, enabled = true } }
    local members = { a = { eligible = true } }
    local r = GuildMath.accrualPayout(shipments, rules, members, {})
    near(r.total, 0, 'ルールが無い品目は対象外')
end
do
    -- メンバーごとの週次上限でクランプされる
    local shipments = { { identifier = 'a', item = 'corn', qty = 1000 } }
    local rules = { corn = { unitAmount = 1.0, enabled = true } }
    local members = { a = { eligible = true } }
    local r = GuildMath.accrualPayout(shipments, rules, members, { memberDailyCap = 10, guildWeeklyCap = 1000 })
    near(r.total, 70, 'メンバー週次上限 = 1日上限×7 でクランプされる (10*7)')
end
do
    -- 組合全体の週次上限を超えたら比例縮小（誰か1人だけ打ち切られない）
    local shipments = {
        { identifier = 'a', item = 'corn', qty = 100 },
        { identifier = 'b', item = 'corn', qty = 100 },
    }
    local rules = { corn = { unitAmount = 1.0, enabled = true } }
    local members = { a = { eligible = true }, b = { eligible = true } }
    local r = GuildMath.accrualPayout(shipments, rules, members, { memberDailyCap = 1000, guildWeeklyCap = 100 })
    near(r.total, 100, '組合の週次上限でクランプされる')
    near(r.byMember.a, 50, '上限超過分は全員に比例して縮小される(a)')
    near(r.byMember.b, 50, '上限超過分は全員に比例して縮小される(b)')
end
do
    local r = GuildMath.accrualPayout({}, {}, {}, {})
    near(r.total, 0, '出荷が無ければ 0')
    ok(#r.lines == 0, '明細も空')
end

print()
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
