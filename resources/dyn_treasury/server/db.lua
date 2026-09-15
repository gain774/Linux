--[[ oxmysql の薄いラッパ。dyn_economy と同じ形だが、リソースを跨いで
     Lua は共有できないのでここにも置く。DB が無くても落ちないようにする。 ]]
TreasuryDb = {}

local ready = false

function TreasuryDb.isReady() return ready end
function TreasuryDb.setReady(v) ready = v end

local function guard(fn, ...)
    if not MySQL then return nil end
    local ok, res = pcall(fn, ...)
    if not ok then
        print(('^1[dyn_treasury] DB エラー: %s^0'):format(tostring(res)))
        return nil
    end
    return res
end

function TreasuryDb.query(sql, params)
    return guard(function() return MySQL.query.await(sql, params) end)
end

function TreasuryDb.execute(sql, params)
    return guard(function() return MySQL.update.await(sql, params) end)
end

function TreasuryDb.insert(sql, params)
    return guard(function() return MySQL.insert.await(sql, params) end)
end

--- コメントを落としてからセミコロンで分割する。順序が逆だとコメント内の
--- セミコロンで文が割れ、断片が SQL として実行される。
function TreasuryDb.splitStatements(raw)
    local out = {}
    if not raw then return out end
    local stripped = raw:gsub('%-%-[^\n]*', '')
    for statement in stripped:gmatch('[^;]+') do
        local trimmed = statement:gsub('^%s+', ''):gsub('%s+$', '')
        if trimmed:gsub('%s+', '') ~= '' then out[#out + 1] = trimmed end
    end
    return out
end

function TreasuryDb.migrate()
    local raw = LoadResourceFile(GetCurrentResourceName(), 'sql/schema.sql')
    if not raw then
        print('^1[dyn_treasury] sql/schema.sql を読めませんでした^0')
        return false
    end
    local statements = TreasuryDb.splitStatements(raw)
    for _, s in ipairs(statements) do TreasuryDb.execute(s) end
    print(('[dyn_treasury] マイグレーション完了（%d 文）'):format(#statements))
    return true
end
