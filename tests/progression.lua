--[[
  目標成長曲線ターゲティング（dyn_economy/shared/progression_math.lua, §7）の単体テスト。
    lua5.4 tests/progression.lua
]]
local root = (arg[0]:match('^(.*)/tests/progression%.lua$') or '.')
local res  = root .. '/resources/dyn_economy'

dofile(res .. '/shared/census_math.lua')
dofile(res .. '/shared/progression_math.lua')

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

local CURVE = {
    { day = 1,  value = 50 },
    { day = 3,  value = 180 },
    { day = 7,  value = 500 },
    { day = 14, value = 1200 },
    { day = 30, value = 3000 },
    { day = 90, value = 12000 },
}

group('ProgressionMath.curveValue（log-log補間）')
near(ProgressionMath.curveValue(CURVE, 1), 50, '曲線の点そのもの(day=1)')
near(ProgressionMath.curveValue(CURVE, 7), 500, '曲線の点そのもの(day=7)')
near(ProgressionMath.curveValue(CURVE, 90), 12000, '曲線の点そのもの(day=90)')
ok(ProgressionMath.curveValue(CURVE, 0.5) == 50, '下端より前は下端の値（外挿しない）')
ok(ProgressionMath.curveValue(CURVE, 200) == 12000, '上端より後ろは上端の値（外挿しない）')
do
    -- day=1(50) と day=3(180) の中間。log-log補間なので幾何平均寄りになる
    -- 直線補間なら (50+180)/2=115 になるはずだが、log-log はそれより小さい値になる
    local v = ProgressionMath.curveValue(CURVE, 2)
    ok(v > 50 and v < 180, '中間点は両端の間に収まる')
    ok(v < 115, 'log-log補間は直線補間より小さい値になる（成長の逓減を表す）')
end
ok(ProgressionMath.curveValue({}, 5) == nil, '曲線が空ならnil')
ok(ProgressionMath.curveValue(nil, 5) == nil, 'nilを渡しても落ちない')
ok(ProgressionMath.curveValue(CURVE, nil) == nil, 'dayがnilならnil')
ok(ProgressionMath.curveValue(CURVE, 0) == nil, 'day<=0はnil')
do
    -- 順不同でもソートされる
    local shuffled = { CURVE[3], CURVE[1], CURVE[6], CURVE[2], CURVE[5], CURVE[4] }
    near(ProgressionMath.curveValue(shuffled, 1), 50, '順不同の曲線でも正しくソートされる')
end

group('ProgressionMath.curveStart（§6.3 curveモードの起点）')
near(ProgressionMath.curveStart(CURVE), 50, '一番小さいdayの点の値を返す')
ok(ProgressionMath.curveStart({}) == nil, '空ならnil')
ok(ProgressionMath.curveStart(nil) == nil, 'nilなら落ちない')

group('ProgressionMath.dayOf')
near(ProgressionMath.dayOf('playtime', 2.0, 10, nil), 5, 'playtime基準: プレイ時間/1日あたり時間')
near(ProgressionMath.dayOf('calendar', 2.0, 10, 20), 20, 'calendar基準: 経過日数をそのまま使う')
ok(ProgressionMath.dayOf('playtime', 0, 10, nil) == nil, 'hoursPerDay<=0はnil')
near(ProgressionMath.dayOf('playtime', nil, nil, nil), 0, 'hoursPerDay省略時は既定2.0, プレイ時間0なら0日')

group('ProgressionMath.bucketOf')
ok(ProgressionMath.bucketOf(0) == 'early', '0日はearly')
ok(ProgressionMath.bucketOf(7) == 'early', '境界7日はearly')
ok(ProgressionMath.bucketOf(7.1) == 'mid', '7日超はmid')
ok(ProgressionMath.bucketOf(30) == 'mid', '境界30日はmid')
ok(ProgressionMath.bucketOf(30.1) == 'late', '30日超はlate')
ok(ProgressionMath.bucketOf(nil) == nil, 'nilはnil')

group('ProgressionMath.filterMinSamples')
do
    local buckets = { early = { values = {1,2,3,4,5} }, mid = { values = {1,2} } }
    local out = ProgressionMath.filterMinSamples(buckets, 5)
    ok(out.early ~= nil, '5件あるearlyは残る')
    ok(out.mid == nil, '2件しかないmidは除外される')
end

group('ProgressionMath.evaluate（重み付き対数平均誤差）')
do
    -- early: 中央値がちょうど目標(avgDay=3の目標値180)と一致 → 誤差0
    local buckets = { early = { values = { 180, 180, 180 }, avgDay = 3 } }
    local r = ProgressionMath.evaluate(buckets, CURVE, { early = 2.0 })
    near(r.E, 0, '目標どおりならE=0')
end
do
    -- 目標の2倍稼いでいる → E > 0
    local buckets = { early = { values = { 1000 }, avgDay = 3 } }
    local r = ProgressionMath.evaluate(buckets, CURVE, { early = 2.0 })
    ok(r.E > 0, '目標より稼いでいればEは正')
    near(r.E, math.log(1000/180), 'E = ln(比)（1バケットのみなら重みは相殺される）')
end
do
    -- 半分しか稼げていない → E < 0、絶対値は「2倍稼いだ」ケースと対称
    local over  = ProgressionMath.evaluate({ early = { values = { 360 }, avgDay = 3 } }, CURVE, { early = 1 })
    local under = ProgressionMath.evaluate({ early = { values = { 90 },  avgDay = 3 } }, CURVE, { early = 1 })
    near(over.E, -under.E, '2倍稼ぎすぎと半分しか稼げていないは対数で対称')
end
ok(ProgressionMath.evaluate({}, CURVE, {}) == nil, 'バケットが空ならnil')
ok(ProgressionMath.evaluate({ early = { values = {} } }, CURVE, {}) == nil, '値が空でも落ちない')

group('ProgressionMath.isInBand')
ok(ProgressionMath.isInBand(0, 0.15) == true, '誤差0は不感帯の中')
ok(ProgressionMath.isInBand(math.log(1.10), 0.15) == true, '+10%は不感帯の中（許容±15%）')
ok(ProgressionMath.isInBand(math.log(1.20), 0.15) == false, '+20%は不感帯を超える')
ok(ProgressionMath.isInBand(nil, 0.15) == true, 'Eが無ければ不感帯扱い（補正しない）')

group('ProgressionMath.updateIncomeMult')
near(ProgressionMath.updateIncomeMult(1.0, 0, 0.5, 0.03), 1.0, '誤差0なら倍率は変化しない')
do
    -- 誤差が大きくても1日の変化は±3%まで
    local m = ProgressionMath.updateIncomeMult(1.0, 5.0, 0.5, 0.03)
    near(m, 0.97, '大きな正の誤差でも1日-3%までしか下がらない（稼ぎすぎ→買取を下げる）')
end
do
    local m = ProgressionMath.updateIncomeMult(1.0, -5.0, 0.5, 0.03)
    near(m, 1.03, '大きな負の誤差でも1日+3%までしか上がらない')
end
do
    -- 絶対域 [0.50, 2.00] を超えない（極端な前日値からの検証）
    local m = ProgressionMath.updateIncomeMult(0.51, -5.0, 0.5, 0.03)
    ok(m <= 0.51 * 1.03 + 1e-9, '日次クランプが優先される')
    local m2 = ProgressionMath.updateIncomeMult(1.99, 5.0, 0.5, 5.0)
    ok(m2 <= 2.00 + 1e-9, '絶対上限2.00を超えない')
end

group('ProgressionMath.coverage')
near(ProgressionMath.coverage(50, 100), 0.5, 'Mod経由/総収入増加分')
ok(ProgressionMath.coverage(150, 100) == 1.0, '100%を超えたら1.0にクランプ')
ok(ProgressionMath.coverage(-10, 100) == 0, '負値は0にクランプ')
ok(ProgressionMath.coverage(50, 0) == nil, '総収入増加分が0ならnil（0除算しない）')
ok(ProgressionMath.coverage(50, nil) == nil, 'nilなら算出しない')

print()
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
