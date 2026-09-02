-- 違反点数の管理。検知は全てここを通し、モードに応じて処分する。
--
-- 前提として、クライアント側のチートを完全に防ぐことはできない。
-- ここでやるのは「サーバーが持つ値との矛盾を見つけて記録し、
-- 悪質なものを追い出す」ところまで。

AC = {}

local core = exports['gain_core']
local strikes = {}

local function isExempt(src)
    return core:HasPermission(src, ACConfig.ExemptPermission)
end

--- 検知を1件記録する。必要なら処分まで行う。
---@param src number
---@param kind string ACConfig.Weight のキー
---@param detail string 人間が読む説明
---@param meta table|nil 付随情報
function AC.flag(src, kind, detail, meta)
    if not src or src <= 0 then return end
    if GetPlayerName(src) == nil then return end
    if isExempt(src) then return end

    local weight = ACConfig.Weight[kind] or 1
    strikes[src] = (strikes[src] or 0) + weight

    meta = meta or {}
    meta.player = GetPlayerName(src)
    meta.id = src
    meta.kind = kind
    meta.points = strikes[src]
    meta.mode = ACConfig.Mode

    core:Log('cheat', detail, meta)

    if ACConfig.Mode ~= 'enforce' then return end

    if strikes[src] >= ACConfig.Escalation.ban then
        AC.punish(src, 'ban', detail)
    elseif strikes[src] >= ACConfig.Escalation.kick then
        AC.punish(src, 'kick', detail)
    end
end

local function licenseOf(src)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == 'license:' then return id end
    end
    return nil
end

--- 処分を実行する。
---@param src number
---@param action string 'kick' | 'ban'
---@param reason string
function AC.punish(src, action, reason)
    local name = GetPlayerName(src)
    if not name then return end

    strikes[src] = nil

    if action == 'ban' then
        local license = licenseOf(src)

        if license then
            local minutes = ACConfig.Escalation.banMinutes
            local expires = nil
            if minutes and minutes > 0 then
                expires = os.date('!%Y-%m-%d %H:%M:%S', os.time() + minutes * 60)
            end

            MySQL.insert.await([[
                INSERT INTO gain_bans (license, name, reason, banned_by, expires_at)
                VALUES (?, ?, ?, ?, ?)
            ]], { license, name, ('anticheat: %s'):format(reason), 'anticheat', expires })
        end

        core:Log('cheat', 'アンチチートが BAN を実行', { player = name, reason = reason })
        DropPlayer(src, ('不正行為を検知したため接続を停止しました。理由: %s'):format(reason))
        return
    end

    core:Log('cheat', 'アンチチートがキックを実行', { player = name, reason = reason })
    DropPlayer(src, ('不正行為を検知しました。理由: %s'):format(reason))
end

--- 現在の違反点数。
function AC.points(src)
    return strikes[src] or 0
end

-- 時間経過で点数を減らす（一度の誤検知が永久に残らないようにする）
CreateThread(function()
    while true do
        Wait(ACConfig.Decay * 1000)

        for src, value in pairs(strikes) do
            if value <= 1 then
                strikes[src] = nil
            else
                strikes[src] = value - 1
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    strikes[source] = nil
end)

RegisterCommand('gacpoints', function(src, args)
    if src > 0 and not exports['gain_core']:HasPermission(src, 'admin') then return end

    local target = tonumber(args[1])
    if target then
        print(('[gain][ac] %s の違反点数: %d'):format(GetPlayerName(target) or '?', AC.points(target)))
        return
    end

    for id, value in pairs(strikes) do
        print(('[gain][ac] [%d] %s: %d'):format(id, GetPlayerName(id) or '?', value))
    end
end, false)
