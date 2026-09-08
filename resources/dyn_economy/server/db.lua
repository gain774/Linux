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

function DynDb.single(sql, params)
    return guard(function() return MySQL.single.await(sql, params) end)
end

function DynDb.scalar(sql, params)
    return guard(function() return MySQL.scalar.await(sql, params) end)
end

function DynDb.execute(sql, params)
    return guard(function() return MySQL.update.await(sql, params) end)
end

function DynDb.insert(sql, params)
    return guard(function() return MySQL.insert.await(sql, params) end)
end

--- sql/schema.sql を流す。CREATE TABLE IF NOT EXISTS なので何度実行しても安全
function DynDb.migrate()
    local raw = LoadResourceFile(GetCurrentResourceName(), 'sql/schema.sql')
    if not raw then
        print('^1[dyn_economy] sql/schema.sql を読めませんでした^0')
        return false
    end
    local count = 0
    for statement in raw:gmatch('[^;]+') do
        local trimmed = statement:gsub('^%s+', ''):gsub('%s+$', '')
        -- コメント行だけの塊は飛ばす
        local meaningful = trimmed:gsub('%-%-[^\n]*', ''):gsub('%s+', '')
        if #meaningful > 0 then
            DynDb.execute(trimmed)
            count = count + 1
        end
    end
    print(('[dyn_economy] マイグレーション完了（%d 文）'):format(count))
    return true
end
