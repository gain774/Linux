--[[
  マイグレーションの文分割（dyn_economy/server/db.lua）を実物の schema.sql で検証する。
  分割を間違えると起動時のマイグレーションが黙って壊れる。
    lua5.4 tests/schema.lua
]]

local root = (arg[0]:match('^(.*)/tests/schema%.lua$') or '.')

-- db.lua は FiveM の関数を参照するが、splitStatements は純粋。
print = print
MySQL = nil
dofile(root .. '/resources/dyn_economy/server/db.lua')

local passed, failed = 0, 0
local function ok(cond, name, extra)
    if cond then passed = passed + 1
    else
        failed = failed + 1
        print(('  FAIL  %s%s'):format(name, extra and ('  -- ' .. extra) or ''))
    end
end

print('文の分割')
local f = assert(io.open(root .. '/resources/dyn_economy/sql/schema.sql'))
local raw = f:read('a'); f:close()
local stmts = DynDb.splitStatements(raw)

ok(#stmts > 0, '文が取り出せる')
local allCreate, empties, withSemicolon = true, 0, 0
for _, s in ipairs(stmts) do
    if not s:match('^CREATE TABLE IF NOT EXISTS') then allCreate = false end
    if #s == 0 then empties = empties + 1 end
    if s:find(';') then withSemicolon = withSemicolon + 1 end
end
ok(allCreate, 'すべて CREATE TABLE IF NOT EXISTS で始まる（先頭のコメントが混ざっていない）')
ok(empties == 0, '空の文が混ざらない')
ok(withSemicolon == 0, '文の中に ; が残らない')

local expected = {
    'dyn_items', 'dyn_item_state', 'dyn_npc_tx', 'dyn_recipes',
    'dyn_recipe_inputs', 'dyn_price_history', 'dyn_econ_config',
    'dyn_econ_snapshot', 'dyn_wealth_outlier',
}
for _, t in ipairs(expected) do
    local found = false
    for _, s in ipairs(stmts) do
        if s:find(t, 1, true) then found = true break end
    end
    ok(found, ('%s の定義がある'):format(t))
end
ok(#stmts == #expected, ('文の数がテーブル数と一致する（%d）'):format(#expected),
   ('got %d'):format(#stmts))

print('端の条件')
ok(#DynDb.splitStatements(nil) == 0, 'nil を渡しても落ちない')
ok(#DynDb.splitStatements('') == 0, '空文字は 0 文')
ok(#DynDb.splitStatements('-- comment only\n-- another;') == 0, 'コメントだけなら 0 文')
ok(#DynDb.splitStatements('CREATE TABLE a (x INT);') == 1, '末尾の ; があっても 1 文')
ok(#DynDb.splitStatements('CREATE TABLE a (x INT)') == 1, '末尾の ; が無くても 1 文')
ok(#DynDb.splitStatements('CREATE TABLE a (x INT);\n\n-- note\nCREATE TABLE b (y INT);') == 2,
   '文の間のコメントは文として数えない')

print()
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
