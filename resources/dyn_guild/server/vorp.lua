--[[
  この resource 専用の薄い VORP アダプタ（dyn_trade/server/vorp.lua と同じ理由で
  リソースをまたいで共有できないため複製）。組合は識別子・氏名の参照と
  補助金の入金だけできれば足りる。

  確認に使ったバージョン: vorp_core 3.3
]]

local Core

CreateThread(function()
    while not Core do
        local ok, core = pcall(function() return exports.vorp_core:GetCore() end)
        if ok and core then Core = core else Wait(500) end
    end
end)

local function character(source)
    if not Core then return nil end
    local user = Core.getUser(source)
    if not user then return nil end
    return user.getUsedCharacter
end

GuildAdapter = {}

function GuildAdapter.isReady() return Core ~= nil end

function GuildAdapter.getIdentifier(source)
    local c = character(source)
    if not c then return nil end
    return tostring(c.charIdentifier)
end

function GuildAdapter.getName(source)
    local c = character(source)
    if not c then return nil end
    local full = ((c.firstname or '') .. ' ' .. (c.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return full ~= '' and full or nil
end

function GuildAdapter.addMoney(source, amount)
    if not amount or amount <= 0 then return true end
    local c = character(source)
    if not c then return false end
    c.addCurrency(0, amount)
    return true
end

function GuildAdapter.notify(source, text)
    if not Core then return end
    Core.NotifyRightTip(source, text, 5000)
end
