--[[
  個人間取引の参考価格集計（§8.2）のテスト。
    lua5.4 tests/vwap.lua
]]

local root = (arg[0]:match('^(.*)/tests/vwap%.lua$') or '.')
local res  = root .. '/resources/dyn_economy'

dofile(res .. '/shared/vwap_math.lua')
dofile(res .. '/config/config.lua')
dofile(res .. '/server/player_ref.lua')

local passed, failed = 0, 0
local function ok(cond, name, extra)
    if cond then passed = passed + 1
    else
        failed = failed + 1
        print(('  FAIL  %s%s'):format(name, extra and ('  -- ' .. extra) or ''))
    end
end
local function near(a, b, eps, name)
    ok(math.abs(a - b) < (eps or 1e-9), name, ('%s vs %s'):format(tostring(a), tostring(b)))
end

print('DynVwapMath.vwap')
do
    ok(DynVwapMath.vwap({}) == nil, 'サンプルが無ければ nil')
    local v, qty, n = DynVwapMath.vwap({
        { t = 0, qty = 10, unitPrice = 1.0 },
        { t = 0, qty = 10, unitPrice = 2.0 },
    })
    near(v, 1.5, 1e-9, '同数量なら単純平均と一致する')
    near(qty, 20, 1e-9, '出来高の合計を返す')
    ok(n == 2, 'サンプル件数を返す')
end
do
    -- 出来高加重: 大口の単価に寄る
    local v = DynVwapMath.vwap({
        { t = 0, qty = 90, unitPrice = 1.0 },
        { t = 0, qty = 10, unitPrice = 10.0 },
    })
    near(v, 1.9, 1e-9, '出来高の大きいほうに寄る (90*1 + 10*10) / 100 = 1.9')
end

print()
print('DynVwapMath.addSample（窓外を刈る）')
do
    local samples = {
        { t = 0,   qty = 1, unitPrice = 1.0 },
        { t = 100, qty = 1, unitPrice = 2.0 },
    }
    local kept = DynVwapMath.addSample(samples, { t = 200, qty = 1, unitPrice = 3.0 }, 200, 150)
    -- windowSec=150 なので t=0 (差200) は外れ、t=100 (差100) と新規 t=200 (差0) が残る
    ok(#kept == 2, '窓の外のサンプルは刈られる')
    local hasOld = false
    for _, s in ipairs(kept) do if s.unitPrice == 1.0 then hasOld = true end end
    ok(not hasOld, '最も古いサンプルが除外されている')
end
do
    local kept = DynVwapMath.addSample({}, { t = 0, qty = 5, unitPrice = 2.0 }, 0, 3600)
    ok(#kept == 1, '空配列に追加できる')
end

print()
print('DynPlayerRef（dyn_economy 側の記録・参照）')
do
    DynPlayerRef.reset()
    ok(DynPlayerRef.get('corn').vwap == nil, '記録が無ければ vwap は nil')

    DynPlayerRef.record('corn', 10, 1.0)
    DynPlayerRef.record('corn', 10, 2.0)
    local ref = DynPlayerRef.get('corn')
    near(ref.vwap, 1.5, 1e-9, '複数件を出来高加重平均する')
    near(ref.qty, 20, 1e-9, '出来高合計を返す')
    ok(ref.samples == 2, 'サンプル件数を返す')
end
do
    DynPlayerRef.reset()
    ok(DynPlayerRef.record('corn', 0, 1.0) == false, '数量 0 以下は記録しない')
    ok(DynPlayerRef.record('corn', 10, 0) == false, '単価 0 以下は記録しない')
    ok(DynPlayerRef.get('corn').vwap == nil, '無効なサンプルは実際に反映されていない')
end
do
    DynPlayerRef.reset()
    Config.PlayerRef.enabled = false
    ok(DynPlayerRef.record('corn', 10, 1.0) == false, 'Config.PlayerRef.enabled=false なら記録しない')
    Config.PlayerRef.enabled = true
end
do
    -- 品目ごとに独立した集計になっている
    DynPlayerRef.reset()
    DynPlayerRef.record('corn', 10, 1.0)
    DynPlayerRef.record('wheat', 10, 9.0)
    near(DynPlayerRef.get('corn').vwap, 1.0, 1e-9, 'corn は corn だけの平均')
    near(DynPlayerRef.get('wheat').vwap, 9.0, 1e-9, 'wheat は wheat だけの平均')
end

print()
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
