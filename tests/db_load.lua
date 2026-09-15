--[[
  DynState.load() の DB 上書き経路（config/items.lua ではなく、実際に oxmysql から
  読み込む側）だけを狙ったテスト。

  背景: oxmysql は環境によって TINYINT(1) 列を Lua の 1/0 ではなく true/false で返す。
  以前の実装は `row.enabled == 1` でしか判定しておらず、boolean で返ってくる環境では
  DB 読み込み後に全品目が enabled=false（取引不可）になっていた。
  tests/integration.lua は DynDb.isReady() = false で走るため、この経路を一切通らず
  この不具合を検出できなかった。ここでは isReady() = true にして、DB 由来の
  boolean / 数値(1,0) / 文字列("1","0") のいずれが来ても正しく解釈できることを確認する。

    lua5.4 tests/db_load.lua
]]

local root = (arg[0]:match('^(.*)/tests/db_load%.lua$') or '.')
local res  = root .. '/resources/dyn_economy'

json = { encode = function() return '{}' end }
TriggerEvent = function() end
print = print

dofile(res .. '/shared/pricing_math.lua')
dofile(res .. '/server/recipes_core.lua')
dofile(res .. '/config/config.lua')
dofile(res .. '/config/categories.lua')
dofile(res .. '/config/items.lua')

-- dyn_items の行を差し替えられるようにしておく
local dynItemsRows = {}

DynDb = {
    isReady = function() return true end,
    execute = function() end,   -- INSERT / UPDATE は結果を気にしない
    insert  = function() end,
    query = function(sql)
        if sql:find('FROM dyn_items', 1, true) then return dynItemsRows end
        return {}   -- dyn_item_state, dyn_econ_config はテストに無関係
    end,
}

dofile(res .. '/server/state.lua')

local passed, failed = 0, 0
local function ok(cond, name, extra)
    if cond then passed = passed + 1
    else
        failed = failed + 1
        print(('  FAIL  %s%s'):format(name, extra and ('  -- ' .. extra) or ''))
    end
end

-- 実物の dyn_items 行の形。数値列はそのまま、フラグ列だけ表現を変えて検証する
local function baseRow(item, flags)
    return {
        item = item, category = 'crop', price_index = 0.75, base_price = 0,
        target_stock = 400, elasticity = 0.70, min_mult = 0.15, max_mult = 2.00,
        half_life_min = 360, npc_spread = 0.35,
        npc_sellable = flags.npc_sellable, npc_buyable = flags.npc_buyable,
        pinned = flags.pinned, enabled = flags.enabled, price_fixed = flags.price_fixed,
    }
end

print('boolean で返る環境（実際の oxmysql の挙動）')
dynItemsRows = {
    baseRow('corn', { npc_sellable = true, npc_buyable = false, pinned = false, enabled = true, price_fixed = false }),
}
DynState.load()
do
    local it = DynState.get('corn')
    ok(it.enabled == true, 'enabled: true(boolean) が真と解釈される')
    ok(it.npcSellable == true, 'npcSellable: true(boolean) が真と解釈される')
    ok(it.npcBuyable == false, 'npcBuyable: false(boolean) が偽と解釈される（なんでも真、ではない）')
    ok(it.fixed == false, 'price_fixed: false(boolean) が偽と解釈される')
end

print()
print('数値 1/0 で返る環境（従来想定していた形）')
dynItemsRows = {
    baseRow('wheat', { npc_sellable = 1, npc_buyable = 0, pinned = 0, enabled = 1, price_fixed = 1 }),
}
DynState.load()
do
    local it = DynState.get('wheat')
    ok(it.enabled == true, 'enabled: 1 が真と解釈される')
    ok(it.npcBuyable == false, 'npcBuyable: 0 が偽と解釈される')
    ok(it.fixed == true, 'price_fixed: 1 で固定価格になる')
    ok(it.elasticity == 0, 'price_fixed=1 のとき elasticity が 0 に落ちる')
end

print()
print('文字列 "1"/"0" で返る環境（ドライバ設定によってはこれもあり得る）')
dynItemsRows = {
    baseRow('potato', { npc_sellable = '1', npc_buyable = '0', pinned = '0', enabled = '1', price_fixed = '0' }),
}
DynState.load()
do
    local it = DynState.get('potato')
    ok(it.enabled == true, 'enabled: "1"(文字列) が真と解釈される')
    ok(it.npcBuyable == false, 'npcBuyable: "0"(文字列) が偽と解釈される')
end

print()
print('fixed 解除で category 由来の elasticity に戻る')
dynItemsRows = {
    baseRow('hop', { npc_sellable = true, npc_buyable = true, pinned = false, enabled = true, price_fixed = true }),
}
DynState.load()
do
    local it = DynState.get('hop')
    ok(it.fixed == true and it.elasticity == 0, '一旦 fixed になる')
    ok(DynState.setFixed('hop', false), 'setFixed(false) が成功する')
    it = DynState.get('hop')
    ok(it.fixed == false, 'fixed が解除される')
    ok(it.elasticity > 0, 'elasticity が category 由来の値に戻る（0 のままにならない）')
end

print()
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
