--[[
  dyn_economy の純粋ロジックの単体テスト。
  FiveM を起動せずに走る:  lua5.4 tests/run.lua
]]

local root = (arg[0]:match('^(.*)/tests/run%.lua$') or '.')
local M  = dofile(root .. '/resources/dyn_economy/shared/pricing_math.lua')
local R  = dofile(root .. '/resources/dyn_economy/server/recipes_core.lua')

local passed, failed = 0, 0
local function ok(cond, name, extra)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print(('  FAIL  %s%s'):format(name, extra and ('  -- ' .. extra) or ''))
    end
end
local function near(a, b, tol, name)
    tol = tol or 1e-6
    local d = math.abs(a - b)
    ok(d <= tol, name, ('expected %.10f got %.10f (diff %.3e)'):format(b, a, d))
end
local function group(name) print(name) end

-- 数値積分。閉形式の実装を独立な方法で検証するための参照実装
local function numericIntegral(p0, S0, e, minMult, maxMult, a, b, steps)
    steps = steps or 200000
    local h = (b - a) / steps
    local sum = 0
    for i = 0, steps - 1 do
        local x = a + (i + 0.5) * h
        local p = M.rawUnitPrice(p0, S0, x, e)
        sum = sum + M.clamp(p, p0 * minMult, p0 * maxMult) * h
    end
    return sum
end

group('decayStock (§4.3)')
near(M.decayStock(200, 100, 360, 360), 150, 1e-9, '半減期ちょうどで差が半分')
near(M.decayStock(200, 100, 720, 360), 125, 1e-9, '半減期2つ分で差が1/4')
near(M.decayStock(200, 100, 0, 360), 200, 1e-9, '経過0なら変化なし')
near(M.decayStock(50, 100, 360, 360), 75, 1e-9, '下から上へも同じ式で戻る')
ok(M.decayStock(200, 100, 60, 0) == 200, '半減期0は無効値として素通し')

group('rawUnitPrice (§4.1)')
near(M.rawUnitPrice(10, 100, 100, 0.7), 10, 1e-9, '均衡在庫では基準価格ちょうど')
ok(M.rawUnitPrice(10, 100, 200, 0.7) < 10, '供給過多で値下がり')
ok(M.rawUnitPrice(10, 100,  50, 0.7) > 10, '品薄で値上がり')
near(M.rawUnitPrice(10, 100, 100, 0), 10, 1e-9, '弾力性0は常に基準価格')

group('stockAtMult / クランプ分割点')
for _, e in ipairs({0.3, 0.5, 0.7, 1.0, 1.5}) do
    local x = M.stockAtMult(100, e, 0.2)
    near(M.rawUnitPrice(10, 100, x, e), 10 * 0.2, 1e-9, ('分割点で下限倍率ちょうど (e=%s)'):format(e))
    local y = M.stockAtMult(100, e, 3.0)
    near(M.rawUnitPrice(10, 100, y, e), 10 * 3.0, 1e-8, ('分割点で上限倍率ちょうど (e=%s)'):format(e))
end

group('integrateClamped が数値積分と一致するか')
local cases = {
    -- p0, S0,  e,   min, max,  a,     b
    {  10, 100, 0.7, 0.2, 3.0,  100,   200 },   -- 曲線区間のみ
    {  10, 100, 0.7, 0.2, 3.0,  100,  5000 },   -- 下限に張り付く区間をまたぐ
    {  10, 100, 0.7, 0.2, 3.0,    1,   100 },   -- 上限に張り付く区間をまたぐ
    {  10, 100, 0.7, 0.2, 3.0,    1,  5000 },   -- 3区間すべてをまたぐ
    {   4, 250, 1.0, 0.3, 2.0,  200,   900 },   -- e = 1 の対数分岐
    {   4, 250, 1.0, 0.3, 2.0,   10,  4000 },   -- e = 1 で両方の張り付きをまたぐ
    { 2.5,  80, 0.35, 0.5, 1.8,  60,   400 },
    {  10, 100, 1.4, 0.2, 3.0,   40,   600 },   -- e > 1
}
for i, c in ipairs(cases) do
    local exact = M.integrateClamped(c[1], c[2], c[3], c[4], c[5], c[6], c[7])
    local approx = numericIntegral(c[1], c[2], c[3], c[4], c[5], c[6], c[7])
    ok(math.abs(exact - approx) / approx < 1e-4, ('case %d: 閉形式と数値積分が一致'):format(i),
       ('exact %.6f vs numeric %.6f'):format(exact, approx))
end

group('まとめ売りは単価が下がる (§4.2 — 単一作物集中への対策の核)')
local p0, S0, e, mn, mx = 10, 100, 0.7, 0.2, 3.0
local prev = math.huge
for _, q in ipairs({1, 10, 50, 100, 300, 1000}) do
    local unit = M.totalSell(p0, S0, e, mn, mx, S0, q) / q
    ok(unit < prev, ('数量 %d の平均単価は前段より安い'):format(q), ('unit=%.4f prev=%.4f'):format(unit, prev))
    prev = unit
end
near(M.totalSell(p0, S0, e, mn, mx, S0, 1e-6) / 1e-6, p0, 1e-3, '極小数量の単価は基準価格に収束')

group('分散して売るほうが総額で有利か（多品目栽培への誘導）')
local lump = M.totalSell(p0, S0, e, mn, mx, S0, 300)
local split = 0
for _ = 1, 6 do split = split + M.totalSell(p0, S0, e, mn, mx, S0, 50) end
ok(split > lump, '同じ在庫状態から50個ずつ6品目のほうが300個一括より高い',
   ('split=%.2f lump=%.2f'):format(split, lump))

group('totalBuy')
ok(M.totalBuy(p0, S0, e, mn, mx, S0, 10) > M.totalSell(p0, S0, e, mn, mx, S0, 10),
   '同数量なら購入side（在庫が減る）のほうが高い')
local huge = M.totalBuy(p0, S0, e, mn, mx, 5, 1e6)
ok(huge < math.huge and huge > 0, '在庫を超える購入でも有限に収まる（上限クランプが効く）')
near(M.totalBuy(p0, S0, e, mn, mx, 5, 1e6) / 1e6, p0 * mx, 1e-3,
     '巨大数量の平均単価は上限倍率に収束')
ok(M.totalSell(p0, S0, e, mn, mx, S0, 0) == 0, '数量0は0円')

group('taxFromSpread (§9.1)')
for _, spread in ipairs({0.1, 0.2, 0.3, 0.5}) do
    local t = M.taxFromSpread(spread)
    near((1 + t) / (1 - t), 1 / (1 - spread), 1e-9,
         ('spread %.2f で 販売/買取 比が 1/(1-spread) に一致'):format(spread))
end
ok(M.taxFromSpread(0) == 0, 'スプレッド0なら無税')

group('effectiveMinMult (§5.3 レシピ原価による下限)')
near(M.effectiveMinMult(10, 0.2, 3.0, 8, 1.1), 0.88, 1e-9, '原価8×1.1 → 下限倍率0.88')
near(M.effectiveMinMult(10, 0.2, 3.0, 1, 1.1), 0.2, 1e-9, '原価が安ければ min_mult のまま')
near(M.effectiveMinMult(10, 0.2, 3.0, 100, 1.1), 3.0, 1e-9, '原価が高すぎても上限は超えない')
near(M.effectiveMinMult(10, 0.2, 3.0, nil, 1.1), 0.2, 1e-9, '原価不明なら min_mult')
do
    local cost, margin = 8, 1.1
    local em = M.effectiveMinMult(10, 0.2, 3.0, cost, margin)
    local unit = M.totalSell(10, 100, 0.7, em, 3.0, 100000, 10) / 10
    near(unit, cost * margin, 1e-6, '在庫が溢れても買取単価は原価×マージンを下回らない')
end

group('recipes: 原価の再帰計算 (§5.2)')
local recipes = {
    bread  = { outputQty = 2, inputs = { { item = 'flour', qty = 3 }, { item = 'water', qty = 1 } } },
    flour  = { outputQty = 1, inputs = { { item = 'wheat', qty = 4 } } },
    loopA  = { outputQty = 1, inputs = { { item = 'loopB', qty = 1 } } },
    loopB  = { outputQty = 1, inputs = { { item = 'loopA', qty = 1 } } },
    deep1  = { outputQty = 1, inputs = { { item = 'deep2', qty = 1 } } },
    deep2  = { outputQty = 1, inputs = { { item = 'deep3', qty = 1 } } },
    deep3  = { outputQty = 1, inputs = { { item = 'deep4', qty = 1 } } },
    deep4  = { outputQty = 1, inputs = { { item = 'deep5', qty = 1 } } },
    deep5  = { outputQty = 1, inputs = { { item = 'deep6', qty = 1 } } },
    deep6  = { outputQty = 1, inputs = { { item = 'deep7', qty = 1 } } },
    deep7  = { outputQty = 1, inputs = { { item = 'wheat', qty = 1 } } },
}
local base = { wheat = 1.0, water = 0.1 }
local ctx = { recipes = recipes, priceOf = function(i) return base[i] end }

near(R.computeCost('flour', ctx), 4.0, 1e-9, 'flour = wheat 4 個')
near(R.computeCost('bread', ctx), (4.0 * 3 + 0.1 * 1) / 2, 1e-9, 'bread は出力2個で割る')
ok(R.computeCost('wheat', ctx) == nil, 'レシピを持たない素材は原価なし')
ok(R.computeCost('loopA', ctx) == nil, '循環参照は打ち切って nil')
ok(R.computeCost('deep1', ctx) == nil, '最大深さ超過は nil')
near(R.computeCost('deep7', ctx), 1.0, 1e-9, '深さ制限内なら計算できる')
do
    local unknown = { recipes = { x = { outputQty = 1, inputs = { { item = 'ghost', qty = 2 } } } },
                      priceOf = function() return nil end,
                      fallbackPrice = function() return 5 end }
    near(R.computeCost('x', unknown), 10, 1e-9, '価格未定義の素材はフォールバック価格を使う')
end
do
    local calls = 0
    local counting = { recipes = recipes, priceOf = function(i) calls = calls + 1; return base[i] end }
    R.computeCostAll({ 'bread', 'flour' }, counting)
    ok(calls <= 6, '同一素材の価格参照はメモ化されて再計算されない', ('calls=%d'):format(calls))
end

print()
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
