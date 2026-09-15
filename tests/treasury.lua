--[[
  国庫の記帳判定（dyn_treasury/server/ledger_math.lua）のテスト。
    lua5.4 tests/treasury.lua
]]
local root = (arg[0]:match('^(.*)/tests/treasury%.lua$') or '.')
dofile(root .. '/resources/dyn_treasury/server/ledger_math.lua')

local passed, failed = 0, 0
local function ok(cond, name, extra)
    if cond then passed = passed + 1
    else failed = failed + 1; print(('  FAIL  %s%s'):format(name, extra and ('  -- '..extra) or '')) end
end
local function near(a, b, name, tol)
    tol = tol or 1e-9
    ok(a and math.abs(a - b) <= tol, name, ('expected %.4f got %s'):format(b, tostring(a)))
end
local function group(n) print(n) end

-- テーブルに nil は入れられないので、値を消したいときはこの番兵を渡す
local NIL = {}

local function tx(over)
    local t = { txId = 42, item = 'corn', qty = 10, direction = 'sell', total = 5.9, tax = 1.25 }
    for k, v in pairs(over or {}) do
        t[k] = (v ~= NIL) and v or nil
    end
    return t
end

group('取引からの記帳')
do
    local e = TreasuryMath.entryForCommit(tx())
    ok(e ~= nil, '税があれば記帳する')
    ok(e.direction == 'in', '国庫への入金')
    ok(e.source == 'npc_tax_sell', '買取の税は npc_tax_sell')
    near(e.amount, 1.25, '税額がそのまま入る')
    ok(e.refType == 'dyn_npc_tx' and e.refId == 42, '元の取引を参照できる')
    ok(e.note == 'corn x10', '品目と数量が note に残る')
end
do
    local e = TreasuryMath.entryForCommit(tx({ direction = 'buy' }))
    ok(e.source == 'npc_tax_buy', '販売の税は npc_tax_buy（後から分けて見られる）')
end

group('記帳しない場合')
ok(TreasuryMath.entryForCommit(tx({ tax = 0 })) == nil, '税 0 は記帳しない')
ok(TreasuryMath.entryForCommit(tx({ tax = NIL })) == nil, '税が無い取引は記帳しない')
ok(TreasuryMath.entryForCommit(tx({ tax = -5 })) == nil, '負の税は記帳しない')
ok(TreasuryMath.entryForCommit(tx({ direction = 'steal' })) == nil, '不正な方向は記帳しない')
ok(TreasuryMath.entryForCommit(nil) == nil, 'nil を渡しても落ちない')
ok(TreasuryMath.entryForCommit('corn') == nil, 'テーブル以外を渡しても落ちない')

group('取り消しの打ち消し')
do
    local e = TreasuryMath.entryForVoid(tx())
    ok(e.direction == 'out', '国庫からの出金になる')
    near(e.amount, 1.25, '同額を戻す')
    ok(e.source == 'void_refund', 'source で取り消しと分かる')
    ok(e.note:find('取り消し'), 'note に取り消しと残る')
    ok(e.refId == 42, '元の取引を参照できる')
end
ok(TreasuryMath.entryForVoid(tx({ tax = 0 })) == nil, '税 0 の取り消しは何もしない')

group('残高への適用')
near(TreasuryMath.apply(100, TreasuryMath.entryForCommit(tx())), 101.25, '入金で増える')
near(TreasuryMath.apply(100, TreasuryMath.entryForVoid(tx())), 98.75, '出金で減る')
near(TreasuryMath.apply(100, nil), 100, '記帳が無ければ変わらない')
do
    -- 徴収してから取り消すと、残高は元に戻る
    local b = 0
    b = TreasuryMath.apply(b, TreasuryMath.entryForCommit(tx()))
    b = TreasuryMath.apply(b, TreasuryMath.entryForVoid(tx()))
    near(b, 0, '徴収 → 取り消しで残高が元に戻る（集めていない金が残らない）')
end

group('補助金に回せる額 (§9.2)')
do
    local free, reserve = TreasuryMath.spendable(10000, 2000, 3.0)
    near(reserve, 6000, '準備金 = 月間税収 × 3')
    near(free, 4000, '超過分が予算になる')
end
do
    local free, reserve = TreasuryMath.spendable(5000, 2000, 3.0)
    near(reserve, 6000, '準備金は残高に関係なく決まる')
    near(free, 0, '準備金を割っていたら予算は 0（マイナスにしない）')
end
near((TreasuryMath.spendable(10000, 0, 3.0)), 10000, '税収が無ければ全額が予算')
near((TreasuryMath.spendable(0, 0, 0)), 0, 'すべて 0 でも落ちない')
near((TreasuryMath.spendable(nil, nil, nil)), 0, 'nil を渡しても落ちない')

group('個人間取引(dyn_trade)の手数料記帳')
do
    local e = TreasuryMath.entryForP2PFee({ amount = 3.5, sessionId = 42, note = 'test' })
    ok(e ~= nil, '手数料があれば記帳する')
    ok(e.direction == 'in', '国庫への入りとして記帳する')
    ok(e.source == 'p2p_trade_fee', 'source は p2p_trade_fee')
    near(e.amount, 3.5, '金額がそのまま入る')
    ok(e.refType == 'dyn_p2p_tx' and e.refId == 42, '参照先が dyn_p2p_tx を指す')
end
ok(TreasuryMath.entryForP2PFee({ amount = 0 }) == nil, '手数料 0 は記帳しない')
ok(TreasuryMath.entryForP2PFee({ amount = -1 }) == nil, '負の手数料は記帳しない')
ok(TreasuryMath.entryForP2PFee(nil) == nil, 'nil を渡しても落ちない')
ok(TreasuryMath.entryForP2PFee('x') == nil, '型が違っても落ちない')

group('州別の記帳（RedM は州で分かれているので税を一つに丸めない）')
do
    local e = TreasuryMath.entryForCommit(tx(), 'new_hanover')
    ok(e.state == 'new_hanover', '渡した州がそのまま入る')
end
do
    local e = TreasuryMath.entryForCommit(tx())
    ok(e.state == 'unassigned', '州を渡さなければ unassigned')
end
do
    local e = TreasuryMath.entryForVoid(tx(), 'west_elizabeth')
    ok(e.state == 'west_elizabeth', '取り消しにも州が引き継がれる')
end
do
    local e = TreasuryMath.entryForP2PFee({ amount = 3.5, sessionId = 1 }, 'lemoyne')
    ok(e.state == 'lemoyne', 'P2P手数料にも州を渡せる')
end
do
    local e = TreasuryMath.entryForP2PFee({ amount = 3.5, sessionId = 1 })
    ok(e.state == 'unassigned', 'P2P手数料は州が特定できないので既定 unassigned')
end

group('TreasuryMath.entryForSubsidy（組合補助金の支払い記帳）')
do
    local e = TreasuryMath.entryForSubsidy({ amount = 42.5, payoutId = 7, note = '農協' }, 'new_hanover')
    ok(e ~= nil, '金額があれば記帳する')
    ok(e.direction == 'out', '国庫からの出金として記帳する')
    ok(e.source == 'subsidy', "source は 'subsidy'")
    near(e.amount, 42.5, '金額がそのまま入る')
    ok(e.refType == 'dyn_subsidy_payouts' and e.refId == 7, '参照先が dyn_subsidy_payouts を指す')
    ok(e.state == 'new_hanover', '組合の所属州が入る')
end
ok(TreasuryMath.entryForSubsidy({ amount = 0 }) == nil, '金額 0 は記帳しない')
ok(TreasuryMath.entryForSubsidy({ amount = -1 }) == nil, '負の金額は記帳しない')
ok(TreasuryMath.entryForSubsidy(nil) == nil, 'nil を渡しても落ちない')
do
    local e = TreasuryMath.entryForSubsidy({ amount = 10 })
    ok(e.state == 'unassigned', '州を渡さなければ unassigned')
end

group('TreasuryMath.weekLabel（週次予算サイクルのキー）')
do
    -- 2026-01-01 00:00:00 UTC のタイムスタンプ
    local t = os.time({ year = 2026, month = 1, day = 1, hour = 0, min = 0, sec = 0, isdst = false })
    -- ローカル os.time は環境のTZに依存するので、os.date('!*t', t) で UTC に戻した値と比較する
    local label = TreasuryMath.weekLabel(t)
    ok(label:match('^%d%d%d%d%-W%d%d$') ~= nil, ('"YYYY-Wnn" 形式になる (got %s)'):format(label))
end
do
    local labels = {}
    for day = 0, 20 do
        local t = os.time({ year = 2026, month = 1, day = 1 + day, hour = 12, min = 0, sec = 0 })
        labels[#labels + 1] = TreasuryMath.weekLabel(t)
    end
    -- 同じ週の中では変わらず、7日ごとに進む（厳密な ISO 週ではなく年初からの簡略連番）
    ok(labels[1] == labels[7], '同じ週内では同じラベル')
    ok(labels[1] ~= labels[8], '週をまたぐとラベルが変わる')
end
do
    local t1 = os.time({ year = 2026, month = 6, day = 15, hour = 12, min = 0, sec = 0 })
    local t2 = os.time({ year = 2027, month = 6, day = 15, hour = 12, min = 0, sec = 0 })
    ok(TreasuryMath.weekLabel(t1) ~= TreasuryMath.weekLabel(t2), '年が違えばラベルも違う')
end

print()
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
