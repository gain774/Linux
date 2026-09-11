--[[
  価格スタック全体（config → state → pricing）の結合テスト。
  FiveM を起動せず、必要な最小限のグローバルだけスタブして走らせる。
    lua5.4 tests/integration.lua
]]

local root = (arg[0]:match('^(.*)/tests/integration%.lua$') or '.')
local res  = root .. '/resources/dyn_economy'

-- FiveM 側のグローバルのうち、このテストが触る範囲だけ用意する
json = { encode = function() return '{}' end }

-- 価格エンジンは確定・取り消しのたびにイベントを出す（§9.5.5）。
-- FiveM の外なので捕まえて中身を見る。
EmittedEvents = {}
TriggerEvent = function(name, payload)
    EmittedEvents[#EmittedEvents + 1] = { name = name, payload = payload }
end

dofile(res .. '/shared/pricing_math.lua')
dofile(res .. '/server/recipes_core.lua')
dofile(res .. '/config/config.lua')
dofile(res .. '/config/categories.lua')
dofile(res .. '/config/items.lua')

-- DB なしモード。state.lua / ledger.lua はこれを見て永続化を飛ばす
DynDb = {
    isReady = function() return false end,
    query = function() return {} end,
    execute = function() end,
    insert = function() end,
}

dofile(res .. '/server/state.lua')
dofile(res .. '/server/pricing.lua')
dofile(res .. '/server/ledger.lua')
dofile(res .. '/server/recipes.lua')

local passed, failed = 0, 0
local function ok(cond, name, extra)
    if cond then passed = passed + 1
    else
        failed = failed + 1
        print(('  FAIL  %s%s'):format(name, extra and ('  -- ' .. extra) or ''))
    end
end
local function near(a, b, tol, name)
    tol = tol or 1e-6
    ok(a and math.abs(a - b) <= tol, name,
       ('expected %.6f got %s'):format(b, a and ('%.6f'):format(a) or 'nil'))
end
local function group(n) print(n) end

local function reset()
    DynState.load()
    DynState.setEcon('currency_scale', 1.0)
    DynState.setEcon('cpi_mult', 1.0)
    DynState.setEcon('income_mult', 1.0)
    Config.Dynamic.enabled = true
    Config.Recipes.enabled = true
    Config.PriceLevel.enabled = true
    Config.Tax.enabled = true
    Config.Tax.sellShare = 0.5
    -- 精度を見るテストでは丸めを切る。丸めそのものは専用のグループで検証する
    Config.Currency.step = 0
end

reset()

group('起動と読み込み')
ok(DynState.count() > 0, 'items.lua から品目が読み込まれる')
ok(DynState.get('corn') ~= nil, 'corn が存在する')
ok(DynState.get('nonexistent') == nil, '未定義アイテムは nil')
near(DynState.get('corn').elasticity, Categories.crop.elasticity, 1e-9,
     'カテゴリ既定値が継承される')

group('均衡在庫での基準価格')
local q = DynPricing.quoteSell('corn', 1)
local t = DynMath.taxFromSpread(Categories.crop.spread)
near(q.priceNow, Items.corn.priceIndex * (1 - t), 1e-9,
     '限界単価 = 相対価値 × (1 - 税率)')
-- 合計は「1 個ぶんの区間を積分した値」なので、限界単価をわずかに下回るのが正しい。
-- ここがズレていると §4.2 の積分が効いていないことになる。
ok(q.total < q.priceNow and q.total > q.priceNow * 0.99,
   '数量 1 の合計は限界単価をわずかに下回る（積分の定義どおり）',
   ('total=%.6f priceNow=%.6f'):format(q.total, q.priceNow))
ok(q.breakdown.index == Items.corn.priceIndex, 'breakdown に相対価値が入る')
near(q.breakdown.scale, 1.0, 1e-9, 'breakdown に通貨スケールが入る')

group('スプレッド: 販売と買取の比 (§4.4)')
local s1 = DynPricing.quoteSell('corn', 1)
local b1 = DynPricing.quoteBuy('corn', 1)
ok(b1.total > s1.total, 'NPC 販売価格 > NPC 買取価格')
near(b1.priceNow / s1.priceNow, 1 / (1 - Categories.crop.spread), 1e-9,
     '限界単価の比がちょうど 1/(1-spread) になる')

group('通貨スケールが全品目に一律で効く (§6.1)')
DynState.setEcon('currency_scale', 3.0)
local scaled = DynPricing.quoteSell('corn', 1)
near(scaled.total, s1.total * 3.0, 1e-6, 'スケール 3 倍で価格も 3 倍')
DynState.setEcon('currency_scale', 1.0)

group('物価水準は需給と独立に効く (§4.5)')
DynState.setEcon('cpi_mult', 1.25)
local cpi = DynPricing.quoteSell('corn', 1)
near(cpi.total, s1.total * 1.25, 1e-6, 'cpi_mult が価格に乗る')
near(cpi.breakdown.cpi, 1.25, 1e-9, 'breakdown に物価水準が分離して残る')
near(cpi.breakdown.supply or 1.0, 1.0, 1e-9, '需給側は動いていない')
DynState.setEcon('cpi_mult', 1.0)

group('成長曲線補正は買取側にだけ掛かる (§7.3)')
DynState.setEcon('income_mult', 0.8)
local sIncome = DynPricing.quoteSell('corn', 1)
local bIncome = DynPricing.quoteBuy('corn', 1)
near(sIncome.total, s1.total * 0.8, 1e-6, '買取（金のソース）は 0.8 倍になる')
near(bIncome.total, b1.total, 1e-6, '販売価格は変わらない')
DynState.setEcon('income_mult', 1.0)

group('売却で在庫が増え、価格が下がる (§4.1〜4.2)')
reset()
local before = DynPricing.quoteSell('corn', 1).total
local commit = DynPricing.commitSell('player1', 'corn', 200, 'shop_valentine')
ok(commit ~= nil, 'commitSell が成立する')
near(commit.stockAfter - commit.stockBefore, 200, 1e-6, '在庫が売却数量ぶん増える')
local after = DynPricing.quoteSell('corn', 1).total
ok(after < before, '大量売却の直後は買取単価が下がっている',
   ('before=%.4f after=%.4f'):format(before, after))

group('時間経過で価格が戻る (§4.3)')
local it = DynState.get('corn')
it.updatedAt = it.updatedAt - (Categories.crop.halfLifeMin * 60) * 4   -- 半減期 4 つ分さかのぼる
local recovered = DynPricing.quoteSell('corn', 1).total
ok(recovered > after, '時間が経つと買取単価が回復する',
   ('after=%.4f recovered=%.4f'):format(after, recovered))
ok(recovered <= before + 1e-9, '基準価格を超えて回復はしない')

group('まとめ売りの平均単価（単一作物集中への対策）')
reset()
local unit1   = DynPricing.quoteSell('corn', 1).unitAvg
local unit500 = DynPricing.quoteSell('corn', 500).unitAvg
ok(unit500 < unit1, '500 個まとめ売りの平均単価は 1 個売りより安い',
   ('1=%.4f 500=%.4f'):format(unit1, unit500))
local lump  = DynPricing.quoteSell('corn', 300).total
local split = DynPricing.quoteSell('corn', 100).total
             + DynPricing.quoteSell('wheat', 100).total
             + DynPricing.quoteSell('chewingtobacco', 100).total
ok(split > lump, '3 品目に分けたほうが総額で有利',
   ('lump=%.2f split=%.2f'):format(lump, split))

group('レシピ原価による下限 (§5.3)')
reset()
DynState.setStock('flour', DynState.get('flour').targetStock * 50)   -- 供給過多にする
local floored = DynPricing.quoteSell('flour', 1)
local glut = floored.total
DynState.setMatCost('flour', 6.0)
local withCost = DynPricing.quoteSell('flour', 1)
ok(withCost.total > glut, '原価を与えると買取価格が持ち上がる',
   ('glut=%.4f withCost=%.4f'):format(glut, withCost.total))
ok(withCost.breakdown.floor ~= nil, 'breakdown に原価下限が記録される')
near(withCost.total, 6.0 * Config.Recipes.craftMargin * (1 - DynMath.taxFromSpread(Categories.crafted.spread)),
     1e-4, '下限は 原価 × マージン（税引き後）')
Config.Recipes.enabled = false
ok(DynPricing.quoteSell('flour', 1).total < withCost.total - 1e-9,
   'Config.Recipes.enabled = false で下限が外れる')
Config.Recipes.enabled = true

group('需給を止めると固定価格になる (§7.7 トグル)')
reset()
Config.Dynamic.enabled = false
local fixedA = DynPricing.quoteSell('corn', 1).total
DynState.setStock('corn', DynState.get('corn').targetStock * 100)
local fixedB = DynPricing.quoteSell('corn', 1).total
near(fixedB, fixedA, 1e-9, '在庫を 100 倍にしても価格が動かない')
Config.Dynamic.enabled = true

group('エラー処理')
reset()
local r, err = DynPricing.quoteSell('nonexistent', 1)
ok(r == nil and err == 'unknown_item', '未定義アイテムは unknown_item')
r, err = DynPricing.quoteSell('corn', 0)
ok(r == nil and err == 'qty_invalid', '数量 0 は qty_invalid')
r, err = DynPricing.quoteSell('corn', -5)
ok(r == nil and err == 'qty_invalid', '負の数量は qty_invalid')
r, err = DynPricing.quoteSell('water', 1)
ok(r == nil and err == 'not_sellable', 'npcSellable = false は not_sellable')
ok(DynPricing.quoteBuy('water', 1) ~= nil, 'water は購入はできる')

group('税額の計算')
reset()
local tq = DynPricing.quoteSell('corn', 100)
local fair = tq.total / (1 - DynMath.taxFromSpread(Categories.crop.spread))
near(tq.tax, fair - tq.total, 1e-6, '買取時の税額 = 公正価格 - 受取額')
Config.Tax.enabled = false
local noTax = DynPricing.quoteSell('corn', 100)
ok(noTax.tax == 0 and noTax.total > tq.total, 'Config.Tax.enabled = false で無税になる')
Config.Tax.enabled = true

group('通貨の丸め')
reset()
Config.Currency.step = 0.01
local rounded = DynPricing.quoteSell('corn', 7)
near(rounded.total, DynMath.round(rounded.total, 0.01), 1e-12, '合計が丸め単位の倍数になる')
Config.Currency.step = 0.25
local coarse = DynPricing.quoteSell('corn', 7)
near(coarse.total % 0.25, 0, 1e-9, '丸め単位を変えると追従する')
Config.Currency.step = 0

group('取引の通知 (§9.5.5)')
reset()
do
    EmittedEvents = {}
    local c = DynPricing.commitSell('char9', 'corn', 10, 'shop_x')
    local ev = EmittedEvents[#EmittedEvents]
    ok(ev and ev.name == 'dyn_economy:committed', '確定で committed が出る')
    ok(ev.payload.item == 'corn' and ev.payload.qty == 10, '品目と数量が入る')
    ok(ev.payload.direction == 'sell', '方向が入る')
    near(ev.payload.total, c.total, 1e-9, '金額が入る')
    near(ev.payload.tax, c.tax, 1e-9, '税額が入る（国庫はこれを記帳する）')
    ok(ev.payload.identifier == 'char9' and ev.payload.shop == 'shop_x', '誰がどの店で取引したか')

    EmittedEvents = {}
    DynPricing.void(c)
    local v = EmittedEvents[#EmittedEvents]
    ok(v and v.name == 'dyn_economy:voided', '取り消しで voided が出る')
    near(v.payload.tax, c.tax, 1e-9, '取り消しにも税額が入る（同額を戻せる）')

    EmittedEvents = {}
    DynPricing.void(c)
    ok(#EmittedEvents == 0, '二重の取り消しでは通知しない')
end

group('commit は在庫だけを動かす（金と現物は呼び出し側の責務）')
reset()
local c = DynPricing.commitBuy('player2', 'corn', 50, 'shop_a')
near(c.stockBefore - c.stockAfter, 50, 1e-6, '購入で在庫が減る')
ok(c.total > 0, '購入額が返る')

print()
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
