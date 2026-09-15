--[[
  他リソースとの互換レイヤー（dyn_economy_bridge/server/compat.lua）のテスト。
    lua5.4 tests/compat.lua
]]

local root = (arg[0]:match('^(.*)/tests/compat%.lua$') or '.')

-- compat.lua は FiveM の関数を参照するが、ここで使うのは純粋な部分だけ。
-- ロード時に評価されないよう、必要なものだけスタブする。
GetResourceState  = function() return 'stopped' end
LoadResourceFile  = function() return nil end
exports = setmetatable({}, { __index = function() return {} end })

dofile(root .. '/resources/dyn_economy_bridge/server/compat.lua')

local passed, failed = 0, 0
local function ok(cond, name, extra)
    if cond then passed = passed + 1
    else
        failed = failed + 1
        print(('  FAIL  %s%s'):format(name, extra and ('  -- ' .. extra) or ''))
    end
end
local function group(n) print(n) end

group('vorp_stores との設定衝突の検出')
do
    local f = io.open(root .. '/tests/fixtures/vorp_stores_config_sample.lua')
    local raw = f:read('a'); f:close()
    local found = DynCompat.findStoreConflicts(raw)

    ok(found.RandomPrices == 1, 'RandomPrices = true を 1 箇所検出する',
       ('got %s'):format(tostring(found.RandomPrices)))
    ok(found.DynamicStore == 2, 'DynamicStore = true を 2 箇所検出する',
       ('got %s'):format(tostring(found.DynamicStore)))
end
do
    local clean = 'Config = {}\nConfig.Stores = { A = { RandomPrices = false, DynamicStore = false } }'
    ok(next(DynCompat.findStoreConflicts(clean)) == nil, 'すべて false なら検出しない')
    ok(next(DynCompat.findStoreConflicts(nil)) == nil, 'nil を渡しても落ちない')
    ok(next(DynCompat.findStoreConflicts('-- RandomPrices = true')) == nil,
       'コメント行だけなら検出しない')
    ok(DynCompat.findStoreConflicts('DynamicStore = true -- RandomPrices = true').RandomPrices == nil,
       '行末コメントの中は検出しない')
    ok(DynCompat.findStoreConflicts('DynamicStore = true -- RandomPrices = true').DynamicStore == 1,
       '行末コメントがあっても本体は検出する')
    ok(DynCompat.findStoreConflicts('RandomPrices=true').RandomPrices == 1, '空白なしでも検出する')
end

group('品目の突き合わせ')
BridgeConfig = { compat = { allowDegradable = false } }
local function runValidate(itemDb, allowDegradable)
    BridgeConfig.compat.allowDegradable = allowDegradable or false
    local disabled = {}
    local names = {}
    for name in pairs(itemDb) do names[#names + 1] = name end
    table.sort(names)
    local missing, degradable = DynCompat.validateItems({
        listItems  = function() return names end,
        getItemDB  = function(n) return itemDb[n] ~= false and itemDb[n] or nil end,
        setEnabled = function(n, on) disabled[n] = (on == false); return true end,
    })
    return missing, degradable, disabled
end

do
    local missing, degradable, disabled = runValidate({
        corn        = { maxDegradation = 0 },
        wheat       = { maxDegradation = 0 },
        ghost_item  = false,                    -- vorp_inventory に登録が無い
        bread       = { maxDegradation = 120 }, -- 劣化する
    })
    ok(#missing == 1 and missing[1] == 'ghost_item', '未登録の品目を検出する')
    ok(#degradable == 1 and degradable[1] == 'bread', '劣化アイテムを検出する')
    ok(disabled.ghost_item == true and disabled.bread == true, '両方とも無効化される')
    ok(disabled.corn == nil and disabled.wheat == nil, '正常な品目には触れない')
end
do
    local _, degradable, disabled = runValidate({
        bread = { maxDegradation = 120 },
    }, true)
    ok(#degradable == 0 and disabled.bread == nil,
       'allowDegradable = true なら劣化アイテムを無効化しない')
end
do
    local missing, degradable = runValidate({ corn = { maxDegradation = 0 } })
    ok(#missing == 0 and #degradable == 0, '問題がなければ何も無効化しない')
end
do
    -- maxDegradation が nil の品目（劣化しない扱い）
    local _, degradable = runValidate({ corn = {} })
    ok(#degradable == 0, 'maxDegradation が未設定なら劣化なし扱い')
end

print()
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
