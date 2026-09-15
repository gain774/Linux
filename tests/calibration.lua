--[[
  自動較正（dyn_economy/shared/calibration_math.lua, §6.2〜§6.7）の単体テスト。
    lua5.4 tests/calibration.lua
]]
local root = (arg[0]:match('^(.*)/tests/calibration%.lua$') or '.')
local res  = root .. '/resources/dyn_economy'

dofile(res .. '/shared/census_math.lua')
dofile(res .. '/shared/calibration_math.lua')

local passed, failed = 0, 0
local function ok(cond, name, extra)
    if cond then passed = passed + 1
    else failed = failed + 1; print(('  FAIL  %s%s'):format(name, extra and ('  -- '..extra) or '')) end
end
local function near(a, b, name, tol)
    tol = tol or 1e-6
    ok(a and math.abs(a - b) <= tol, name, ('expected %.6f got %s'):format(b, tostring(a)))
end
local function group(n) print(n) end

group('CalibrationMath.bootstrapFromExisting (§6.2 A)')
do
    -- 全品目がきれいに同じ倍率（比 = 2）なら、外れ値なしで scale=2 が出る
    local existing = { corn = 1.5, wheat = 2.0, coal = 3.2 }
    local index    = { corn = 0.75, wheat = 1.0, coal = 1.6 }
    local r = CalibrationMath.bootstrapFromExisting(existing, index)
    near(r.scale, 2.0, '比が揃っていれば中央値がそのままスケールになる')
    ok(#r.outliers == 0, '揃っていれば外れ値なし')
    ok(r.wide == false, 'IQR が狭ければ wide=false')
end
do
    -- tobacco だけ極端に安い（意図的な設定）→ 外れ値として検出される
    local existing = { corn = 1.5, wheat = 2.0, coal = 3.2, tobacco = 4.0 }
    local index    = { corn = 0.75, wheat = 1.0, coal = 1.6, tobacco = 12.3 }
    local r = CalibrationMath.bootstrapFromExisting(existing, index)
    ok(#r.outliers == 1 and r.outliers[1].item == 'tobacco', '極端にズレた品目を外れ値として検出する')
end
ok(CalibrationMath.bootstrapFromExisting({}, {}) == nil, '対応する品目が無ければ nil')
ok(select(1, CalibrationMath.bootstrapFromExisting(nil, nil)) == nil, 'nil を渡しても落ちない')
do
    local r = CalibrationMath.bootstrapFromExisting({ a = 1 }, { a = nil })
    ok(r == nil, 'price_index に無い品目は対象外（結果として1件も無ければ nil）')
end

group('CalibrationMath.startingCash (§6.3)')
near(CalibrationMath.startingCash('basket', { baskets = 1.5, basketPrice = 20 }), 30, 'basket: 倍率×バスケット価格')
near(CalibrationMath.startingCash('curve', { curveDay0 = 77 }), 77, 'curve: day0の値をそのまま使う')
near(CalibrationMath.startingCash('fixed', { fixed = 100 }), 100, 'fixed: 固定額')
near(CalibrationMath.startingCash('basket', { baskets = 1.5 }), 0, 'basket価格が無ければ0（新規サーバーでバスケットが空のとき等）')
near(CalibrationMath.startingCash('unknown_mode', { baskets = 1, basketPrice = 10 }), 10, '不明なモードは basket 扱いにフォールバック')

group('CalibrationMath.purchasingPowerScale (§6.5)')
do
    -- 購買力が目標の2倍 → スケールを上げる方向。ただし1日±2%でクランプ
    local s = CalibrationMath.purchasingPowerScale(1.0, 200, 20, 5.0, 0.15, 0.02)
    -- pp = 200/20 = 10, target=5 → 比2倍。理論上は 1*(1+0.15*(2-1))=1.15 だが ±2%でクランプされ1.02
    near(s, 1.02, '1日の変化幅が±2%でクランプされる')
end
do
    local s = CalibrationMath.purchasingPowerScale(1.0, 100, 20, 5.0, 0.15, 0.02)
    -- pp = 5.0 = target なのでちょうど一致、変化なし
    near(s, 1.0, '購買力が目標と一致していれば変化しない')
end
near(CalibrationMath.purchasingPowerScale(1.0, nil, 20, 5.0, 0.15, 0.02), 1.0, '中央値が無ければ変化しない')
near(CalibrationMath.purchasingPowerScale(1.0, 100, 0, 5.0, 0.15, 0.02), 1.0, 'バスケット価格0は変化しない（0除算しない）')

group('CalibrationMath.wealthCoupling (§6.5 非対称カップリング)')
near(CalibrationMath.wealthCoupling(1.2, 1.0), 1.2, 'coupling=1.0 は完全連動')
near(CalibrationMath.wealthCoupling(1.2, 0.5), 1.2 ^ 0.5, 'coupling=0.5 は変化量が弱まる')
near(CalibrationMath.wealthCoupling(1.2, 0.0), 1.0, 'coupling=0 は全く連動しない')
near(CalibrationMath.wealthCoupling(nil, 0.5), 1.0, 'wealth_mult が無ければ1.0')
near(CalibrationMath.wealthCoupling(0, 0.5), 1.0, 'wealth_mult が0以下でも落ちずに1.0を返す')

group('CalibrationMath.yieldAdjust / yieldTargetBand (§6.6)')
do
    local lo, hi = CalibrationMath.yieldTargetBand(100, 0.7, 1.3)
    near(lo, 70, '目標バンド下限 = 中央値×0.7')
    near(hi, 130, '目標バンド上限 = 中央値×1.3')
end
do
    -- 時給が上限を超えている → price_index を下げる方向（1日最大-3%）
    local idx = CalibrationMath.yieldAdjust(1.0, 500, 70, 130, 0.03)
    near(idx, 0.97, '時給が高すぎる品目は指数を下げる（上限-3%/日でクランプ）')
end
do
    -- 時給が下限を下回る → price_index を上げる方向
    local idx = CalibrationMath.yieldAdjust(1.0, 10, 70, 130, 0.03)
    near(idx, 1.03, '時給が低すぎる品目は指数を上げる（上限+3%/日でクランプ）')
end
do
    -- バンド内なら変化なし
    local idx = CalibrationMath.yieldAdjust(1.0, 100, 70, 130, 0.03)
    near(idx, 1.0, 'バンド内なら変化しない')
end
near(CalibrationMath.yieldAdjust(1.0, nil, 70, 130, 0.03), 1.0, '実測が無ければ変化しない')

group('CalibrationMath.moneySupplyPI (§6.7)')
do
    -- 成長率が目標どおりなら倍率は1.0のまま
    local buy, sell, i = CalibrationMath.moneySupplyPI(0, 0.0, 0.0, 2.0, 0.5)
    near(buy, 1.0, '目標どおりなら買取倍率は変化しない')
    near(sell, 1.0, '目標どおりなら販売倍率は変化しない')
    near(i, 0, '誤差0なら積分項も動かない')
end
do
    -- インフレ気味(成長率 > 目標) → 買取(ソース)を絞り、販売(シンク)を上げる
    local buy, sell = CalibrationMath.moneySupplyPI(0, 0.05, 0.0, 2.0, 0.5)
    ok(buy < 1.0, 'インフレのとき NPC 買取(ソース)を絞る方向に動く')
    ok(sell > 1.0, 'インフレのとき NPC 販売(シンク)を上げる方向に動く')
end
do
    -- デフレ気味(成長率 < 目標) → 逆方向
    local buy, sell = CalibrationMath.moneySupplyPI(0, -0.05, 0.0, 2.0, 0.5)
    ok(buy > 1.0, 'デフレのとき買取を緩める方向に動く')
    ok(sell < 1.0, 'デフレのとき販売を緩める方向に動く')
end
do
    -- 積分項がワインドアップしない（±0.5でクランプ）
    local i = 0
    for _ = 1, 100 do
        local _, _, ni = CalibrationMath.moneySupplyPI(i, 1.0, 0.0, 2.0, 0.5)
        i = ni
    end
    ok(i <= 0.5, '積分項が上限でクランプされる（ワインドアップ防止）')
end
do
    local buy = CalibrationMath.moneySupplyPI(0, 10.0, 0.0, 2.0, 0.5)
    ok(buy >= 0.70, '倍率の絶対下限0.70を割らない')
    local _, sell = CalibrationMath.moneySupplyPI(0, -10.0, 0.0, 2.0, 0.5)
    ok(sell >= 0.70, '倍率の絶対下限0.70を割らない(sell側)')
end

group('CalibrationMath.dailyGrowth')
near(CalibrationMath.dailyGrowth(110, 100), 0.10, '成長率 = (今-前)/前')
ok(CalibrationMath.dailyGrowth(110, 0) == nil, '前日総額0は算出しない（0除算しない）')
ok(CalibrationMath.dailyGrowth(nil, 100) == nil, 'nilなら算出しない')

print()
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
