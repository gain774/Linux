--[[ oxmysql の薄いラッパ。他の dyn_* リソースと同じ形（リソースを跨いで
     Lua は共有できないので、ここにも同じものを置く）。DB が無くても落ちない。 ]]
GuildDb = {}

local ready = false

function GuildDb.isReady() return ready end
function GuildDb.setReady(v) ready = v end

local function guard(fn, ...)
    if not MySQL then return nil end
    local ok, res = pcall(fn, ...)
    if not ok then
        print(('^1[dyn_guild] DB エラー: %s^0'):format(tostring(res)))
        return nil
    end
    return res
end

function GuildDb.query(sql, params)
    return guard(function() return MySQL.query.await(sql, params) end)
end

function GuildDb.execute(sql, params)
    return guard(function() return MySQL.update.await(sql, params) end)
end

function GuildDb.insert(sql, params)
    return guard(function() return MySQL.insert.await(sql, params) end)
end

--- コメントを落としてからセミコロンで分割する（他の dyn_* と同じ順序。
--- 逆順だとコメント内のセミコロンで文が割れる）。
function GuildDb.splitStatements(raw)
    local out = {}
    if not raw then return out end
    local stripped = raw:gsub('%-%-[^\n]*', '')
    for statement in stripped:gmatch('[^;]+') do
        local trimmed = statement:gsub('^%s+', ''):gsub('%s+$', '')
        if trimmed:gsub('%s+', '') ~= '' then out[#out + 1] = trimmed end
    end
    return out
end

function GuildDb.migrate()
    local raw = LoadResourceFile(GetCurrentResourceName(), 'sql/schema.sql')
    if not raw then
        print('^1[dyn_guild] sql/schema.sql を読めませんでした^0')
        return false
    end
    local statements = GuildDb.splitStatements(raw)
    for _, s in ipairs(statements) do GuildDb.execute(s) end
    print(('[dyn_guild] マイグレーション完了（%d 文）'):format(#statements))
    return true
end
