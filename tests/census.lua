--[[
  資産センサスの統計（dyn_economy/shared/census_math.lua）のテスト。
  外れ値の扱いを間違えると、大富豪 1 人でサーバー全体の物価が動く。
    lua5.4 tests/census.lua
]]
local root = (arg[0]:match('^(.*)/tests/census%.lua$') or '.')
local M = dofile(root .. '/resources/dyn_economy/shared/census_math.lua')

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

group('中央値')
near(M.median({5}), 5, '1 件')
near(M.median({1, 3}), 2, '偶数件は中間')
near(M.median({3, 1, 2}), 2, '未ソートでも正しい')
near(M.median({1, 2, 3, 4}), 2.5, '4 件')
ok(M.median({}) == nil, '空は nil')
near(M.median({1, 1, 1, 1, 1000000}), 1, '外れ値があっても中央値は動かない')

group('MAD')
near(M.mad({1, 2, 3, 4, 5}), 1, '等間隔なら 1')
near(M.mad({5, 5, 5}), 0, '全部同じなら 0')
near(M.mad({1, 1, 1, 1, 1000000}), 0, '過半数が同額なら 0')
ok(M.mad({}) == nil, '空は nil')

group('分位数')
near(M.percentile({1, 2, 3, 4, 5}, 0.5), 3, 'p50 は中央値')
near(M.percentile({1, 2, 3, 4, 5}, 0), 1, 'p0 は最小')
near(M.percentile({1, 2, 3, 4, 5}, 1), 5, 'p100 は最大')
near(M.percentile({1, 2, 3, 4}, 0.5), 2.5, '補間する')
near(M.percentile({7}, 0.9), 7, '1 件ならその値')
ok(M.percentile({}, 0.5) == nil, '空は nil')

group('集計: 外れ値の扱い')
do
    -- 普通のプレイヤー 10 人 + 大富豪 1 人
    local samples = {}
    for i = 1, 10 do samples[i] = { id = 'p' .. i, amount = 100 + i * 10, active = true } end
    samples[11] = { id = 'rich', amount = 5000000, active = true }

    local r = M.summarize(samples, { outlierMAD = 5.0 })
    near(r.total, 5001550, '総額には外れ値も算入する（存在する金は存在する）')
    ok(r.n == 11, '人数は全員')
    ok(#r.outliers == 1 and r.outliers[1].id == 'rich', '大富豪を外れ値として検出する')
    ok(r.activeN == 10, '統計の対象は外れ値を除いた 10 人')
    near(r.median, 155, '中央値は普通のプレイヤーのもの（大富豪に引きずられない）')
    ok(r.outliers[1].madScore > 5, 'MAD 何個ぶん離れているかが分かる')

    -- 平均だとこうなる、という比較
    local mean = r.total / r.n
    ok(mean > 400000 and r.median < 200, '平均なら 40 万超だが中央値は 200 未満',
       ('mean=%.0f median=%.0f'):format(mean, r.median))
end

group('集計: 端の条件')
do
    local r = M.summarize({}, {})
    ok(r.total == 0 and r.n == 0 and r.activeN == 0, '空でも落ちない')
    ok(r.median == nil and #r.outliers == 0, '統計は nil、外れ値は空')
end
do
    -- 全員が同額。MAD が 0 になるので閾値を作らない
    local samples = {}
    for i = 1, 5 do samples[i] = { id = 'p' .. i, amount = 100, active = true } end
    samples[6] = { id = 'q', amount = 101, active = true }
    local r = M.summarize(samples, {})
    ok(#r.outliers == 0, 'MAD が 0 のときは外れ値なしとして扱う（全員を外れ値にしない）')
    ok(r.activeN == 6, '全員が統計の対象')
end
do
    local r = M.summarize({
        { id = 'a', amount = 100, active = true },
        { id = 'b', amount = 200, active = false },   -- 放置キャラ
    }, {})
    near(r.total, 300, '総額には非アクティブも算入する')
    ok(r.activeN == 1, '統計はアクティブのみ')
    near(r.median, 100, '中央値はアクティブのみから出す')
end
do
    local r = M.summarize({ { id = 'a', amount = 'x', active = true } }, {})
    near(r.total, 0, '数値でない金額は 0 として扱い落ちない')
end

group('外れ値の並び順')
do
    local samples = { { id = 'p', amount = 10, active = true }, { id = 'q', amount = 11, active = true },
                      { id = 'r', amount = 12, active = true }, { id = 's', amount = 13, active = true } }
    samples[5] = { id = 'big',    amount = 100000, active = true }
    samples[6] = { id = 'bigger', amount = 900000, active = true }
    local r = M.summarize(samples, {})
    ok(#r.outliers == 2, '外れ値を 2 件とも拾う')
    ok(r.outliers[1].id == 'bigger', '金額の大きい順に並ぶ（運営が上から見る）')
end

group('総額の drift 判定')
near(M.drift(1000, 1000), 0, '一致なら 0')
near(M.drift(1250, 1000), 0.25, '25% 増なら 0.25')
near(M.drift(750, 1000), 0.25, '25% 減も 0.25（絶対値）')
near(M.drift(100, 0), 100, '予測 0 でもゼロ除算しない')
ok(M.isDrifting(1300, 1000, 0.25) == true, '許容を超えたら異常')
ok(M.isDrifting(1200, 1000, 0.25) == false, '許容内なら正常')
ok(M.isDrifting(1000, 1000, nil) == false, '許容の既定値は 0.25')
do
    -- 複製バグの想定: 総額が予測の 2.8 倍
    ok(M.isDrifting(3498000, 1240000, 0.25) == true,
       '複製バグ相当のズレを検出する（そのまま較正すると全品を値上げしてしまう）')
end

print()
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
