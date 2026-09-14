--[[ oxmysql の薄いラッパ。DB が無い環境でもリソースが落ちないようにする（dyn_economy/server/db.lua と同じ設計） ]]
TradeDb = {}

local ready = false

function TradeDb.isReady() return ready end

function TradeDb.setReady(v) ready = v end

local function guard(fn, ...)
    if not MySQL then
        print('^1[dyn_trade] oxmysql が見つかりません。DB 機能は無効です^0')
        return nil
    end
    local ok, res = pcall(fn, ...)
    if not ok then
        print(('^1[dyn_trade] DB エラー: %s^0'):format(tostring(res)))
        return nil
    end
    return res
end

function TradeDb.query(sql, params)
    return guard(function() return MySQL.query.await(sql, params) end)
end

function TradeDb.execute(sql, params)
    return guard(function() return MySQL.update.await(sql, params) end)
end

function TradeDb.insert(sql, params)
    return guard(function() return MySQL.insert.await(sql, params) end)
end

--- sql/schema.sql を流す。CREATE TABLE IF NOT EXISTS / INSERT ... ON DUPLICATE KEY UPDATE
--- なので何度実行しても安全
function TradeDb.migrate()
    local raw = LoadResourceFile(GetCurrentResourceName(), 'sql/schema.sql')
    if not raw then
        print('^1[dyn_trade] sql/schema.sql を読めませんでした^0')
        return false
    end
    local stripped = raw:gsub('%-%-[^\n]*', '')
    local n = 0
    for statement in stripped:gmatch('[^;]+') do
        local trimmed = statement:gsub('^%s+', ''):gsub('%s+$', '')
        if trimmed:gsub('%s+', '') ~= '' then
            TradeDb.execute(trimmed)
            n = n + 1
        end
    end
    print(('[dyn_trade] マイグレーション完了（%d 文）'):format(n))
    return true
end
