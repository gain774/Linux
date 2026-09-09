--[[
  レシピ取り込み（dyn_economy/server/recipes_import.lua）のテスト。
  取り込みを間違えると原価が狂い、下限価格が壊れる。
    lua5.4 tests/recipes_import.lua
]]
local root = (arg[0]:match('^(.*)/tests/recipes_import%.lua$') or '.')
local R = dofile(root .. '/resources/dyn_economy/server/recipes_import.lua')

local passed, failed = 0, 0
local function ok(cond, name, extra)
    if cond then passed = passed + 1
    else failed = failed + 1; print(('  FAIL  %s%s'):format(name, extra and ('  -- '..extra) or '')) end
end
local function group(n) print(n) end

local f = assert(io.open(root .. '/tests/fixtures/vorp_crafting_config_sample.lua'))
local src = f:read('a'); f:close()

local recipes, skipped = R.parseVorpCrafting(src)

local byOut = {}
for _, r in ipairs(recipes or {}) do byOut[r.outputItem] = r end
local reasons = {}
for _, s in ipairs(skipped or {}) do reasons[s.reason] = (reasons[s.reason] or 0) + 1 end

group('取り込めるレシピ')
ok(recipes ~= nil, '解析できる', tostring(skipped))
ok(byOut.consumable_breakfast ~= nil, '普通のレシピを取り込む')
ok(#byOut.consumable_breakfast.inputs == 1
   and byOut.consumable_breakfast.inputs[1].item == 'meat'
   and byOut.consumable_breakfast.inputs[1].qty == 2,
   'take = false の素材は道具として原価に入れない')
ok(byOut.cookedsmallgame.outputQty == 2, '出力数量を拾う（原価はこれで割る）')
ok(#byOut.cookedsmallgame.inputs == 2, 'take 未指定は消費される扱い')

group('同じ素材の合算')
do
    local b = byOut.bread
    ok(b ~= nil, 'bread を取り込む')
    ok(#b.inputs == 2, '素材は 2 種類にまとまる')
    local wheat
    for _, i in ipairs(b.inputs) do if i.item == 'wheat' then wheat = i.qty end end
    ok(wheat == 5, '複数行に分かれた同じ素材を足し合わせる（2 + 3 = 5）',
       ('got %s'):format(tostring(wheat)))
end

group('取り込まないもの')
ok(byOut.weapon_revolver_cattleman == nil and reasons.weapon == 1,
   '武器は取り込まない（addItem / subItem が効かない）')
ok(reasons.currency_mode == 1, '金で買うレシピは取り込まない')
ok(byOut.animal_meat == nil and reasons.multiple_rewards == 1,
   '出力が複数のレシピは取り込まない（原価を按分できない）')
ok(byOut.sample == nil and reasons.no_items_taken == 1,
   'TakeItems = false は取り込まない')
ok(byOut.nothing == nil and reasons.no_consumed_inputs == 1,
   '消費される素材が無いレシピは取り込まない')
ok(reasons.duplicate_output == 1, '同じ品を作る 2 本目は取り込まない')
ok(byOut.bread.inputs[1].item == 'wheat', '重複時は最初のレシピを採る')

group('要約')
do
    local sum = R.summarize(recipes, skipped)
    ok(sum.imported == 3, ('取り込み 3 件'):format(), ('got %d'):format(sum.imported))
    ok(sum.skipped == 6, ('除外 6 件'):format(), ('got %d'):format(sum.skipped))
    ok(sum.reasons.weapon == 1, '理由ごとの件数が出る')
end

group('壊れた入力')
ok(select(1, R.parseVorpCrafting(nil)) == nil, 'nil は解析しない')
ok(select(1, R.parseVorpCrafting(123)) == nil, '文字列以外は解析しない')
do
    local _, err = R.parseVorpCrafting('Config = { Crafting = ')
    ok(err and err:find('syntax'), '構文エラーは syntax として報告する')
end
do
    local _, err = R.parseVorpCrafting('Config = {}')
    ok(err == 'no_crafting_table', 'Config.Crafting が無ければそう報告する')
end
do
    local _, err = R.parseVorpCrafting('error("boom")')
    ok(err and err:find('runtime'), '実行時エラーは runtime として報告する')
end
ok(select(1, R.parseVorpCrafting('Config = { Crafting = {} }')) ~= nil, '空のレシピ表は 0 件として成功')

group('サンドボックス')
do
    -- 設定ファイルから io や os に触れないこと
    local _, err = R.parseVorpCrafting('Config = { Crafting = {} } local f = io.open("/etc/passwd")')
    ok(err and err:find('runtime'), 'io は渡していないので失敗する')
end
do
    local _, err = R.parseVorpCrafting('Config = { Crafting = {} } os.exit(1)')
    ok(err and err:find('runtime'), 'os は渡していないので失敗する')
end
ok(select(1, R.parseVorpCrafting('Config = { Crafting = {}, C = vector3(1,2,3) }')) ~= nil,
   'vector3 は使えるようにしてある（座標を書いた設定でも落ちない）')

print()
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
