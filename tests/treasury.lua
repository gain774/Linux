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

print()
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
