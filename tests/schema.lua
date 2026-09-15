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

-- 新しいテーブルは CREATE TABLE IF NOT EXISTS、既存テーブルへの列追加は
-- ALTER TABLE ... ADD COLUMN IF NOT EXISTS のどちらか。両方とも何度実行しても安全な文だけを許す
local allSafe, empties, withSemicolon = true, 0, 0
for _, s in ipairs(stmts) do
    local isCreate = s:match('^CREATE TABLE IF NOT EXISTS')
    local isAlter  = s:match('^ALTER TABLE %S+ ADD COLUMN IF NOT EXISTS')
    if not (isCreate or isAlter) then allSafe = false end
    if #s == 0 then empties = empties + 1 end
    if s:find(';') then withSemicolon = withSemicolon + 1 end
end
ok(allSafe, 'すべて CREATE TABLE IF NOT EXISTS か ALTER TABLE ADD COLUMN IF NOT EXISTS で始まる（先頭のコメントが混ざっていない）')
ok(empties == 0, '空の文が混ざらない')
ok(withSemicolon == 0, '文の中に ; が残らない')

local expected = {
    'dyn_items', 'dyn_item_state', 'dyn_npc_tx', 'dyn_recipes',
    'dyn_recipe_inputs', 'dyn_price_history', 'dyn_econ_config',
    'dyn_econ_snapshot', 'dyn_wealth_outlier',
    'dyn_player_playtime', 'dyn_item_yield',
    'dyn_player_progress', 'dyn_progress_curve', 'dyn_progress_eval',
}
for _, t in ipairs(expected) do
    local found = false
    for _, s in ipairs(stmts) do
        if s:match('^CREATE TABLE IF NOT EXISTS') and s:find(t, 1, true) then found = true break end
    end
    ok(found, ('%s の CREATE 文がある'):format(t))
end

local createCount, alterCount = 0, 0
for _, s in ipairs(stmts) do
    if s:match('^CREATE TABLE IF NOT EXISTS') then createCount = createCount + 1
    elseif s:match('^ALTER TABLE') then alterCount = alterCount + 1 end
end
ok(createCount == #expected, ('CREATE 文の数がテーブル数と一致する（%d）'):format(#expected),
   ('got %d'):format(createCount))
ok(alterCount >= 0 and createCount + alterCount == #stmts, '文の内訳が CREATE と ALTER だけで説明できる')

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
