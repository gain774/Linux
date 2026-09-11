--[[ oxmysql の薄いラッパ。DB が無い環境でもリソースが落ちないようにする ]]
DynDb = {}

local ready = false

function DynDb.isReady() return ready end

function DynDb.setReady(v) ready = v end

local function guard(fn, ...)
    if not MySQL then
        print('^1[dyn_economy] oxmysql が見つかりません。DB 機能は無効です^0')
        return nil
    end
    local ok, res = pcall(fn, ...)
    if not ok then
        print(('^1[dyn_economy] DB エラー: %s^0'):format(tostring(res)))
        return nil
    end
    return res
end

function DynDb.query(sql, params)
    return guard(function() return MySQL.query.await(sql, params) end)
end

function DynDb.execute(sql, params)
    return guard(function() return MySQL.update.await(sql, params) end)
end

function DynDb.insert(sql, params)
    return guard(function() return MySQL.insert.await(sql, params) end)
end

--[[
  SQL ファイルを文単位に切り出す（純粋関数）。

  コメントを先に落としてから ';' で切る。順序が逆だと、コメントの中の ';' で
  文が割れ、コメントの断片が SQL として実行されて構文エラーになる。
  文字列リテラルの中の '--' は考慮しないので、schema.sql には書かないこと。

  切り出しの正しさは tests/schema.lua が実物の schema.sql に対して検証する。
]]
function DynDb.splitStatements(raw)
    local out = {}
    if not raw then return out end
    local stripped = raw:gsub('%-%-[^\n]*', '')
    for statement in stripped:gmatch('[^;]+') do
        local trimmed = statement:gsub('^%s+', ''):gsub('%s+$', '')
        if trimmed:gsub('%s+', '') ~= '' then out[#out + 1] = trimmed end
    end
    return out
end

--- sql/schema.sql を流す。CREATE TABLE IF NOT EXISTS なので何度実行しても安全
function DynDb.migrate()
    local raw = LoadResourceFile(GetCurrentResourceName(), 'sql/schema.sql')
    if not raw then
        print('^1[dyn_economy] sql/schema.sql を読めませんでした^0')
        return false
    end
    local statements = DynDb.splitStatements(raw)
    for _, statement in ipairs(statements) do
        DynDb.execute(statement)
    end
    print(('[dyn_economy] マイグレーション完了（%d 文）'):format(#statements))
    return true
end
