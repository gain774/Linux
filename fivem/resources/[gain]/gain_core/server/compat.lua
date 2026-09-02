-- ESX / QBCore 互換レイヤー（サーバー側）。
-- 既存の無料リソースをそのまま動かすための最小限のブリッジで、
-- 完全互換ではない。カバーしているのは「プレイヤー取得・所持金・職業」まで。
-- 想定外の API を叩くリソースは個別に手当てが必要。

if not Config.Compat.esx and not Config.Compat.qbcore then return end

local function playerOf(src)
    return GetGainPlayer(src)
end

----------------------------------------------------------------------
-- ESX
----------------------------------------------------------------------

local ESX = { Players = {} }

local function makeXPlayer(player)
    if not player then return nil end

    local xPlayer = {
        source = player.source,
        identifier = player.license,
        job = {
            name = player.job.name,
            grade = player.job.grade,
            grade_name = tostring(player.job.grade),
            label = player.job.name,
        },
    }

    function xPlayer.getName() return player.name end
    function xPlayer.getIdentifier() return player.license end

    function xPlayer.getMoney() return Money.get(player, 'cash') end
    function xPlayer.addMoney(amount, reason) return Money.add(player, 'cash', amount, reason or 'esx') end
    function xPlayer.removeMoney(amount, reason) return Money.remove(player, 'cash', amount, reason or 'esx') end

    function xPlayer.getAccount(name)
        local account = (name == 'bank') and 'bank' or 'cash'
        return { name = name, money = Money.get(player, account) }
    end

    function xPlayer.addAccountMoney(name, amount, reason)
        local account = (name == 'bank') and 'bank' or 'cash'
        return Money.add(player, account, amount, reason or 'esx')
    end

    function xPlayer.removeAccountMoney(name, amount, reason)
        local account = (name == 'bank') and 'bank' or 'cash'
        return Money.remove(player, account, amount, reason or 'esx')
    end

    function xPlayer.getJob() return xPlayer.job end

    function xPlayer.setJob(name, grade)
        return exports['gain_core']:SetJob(player.source, name, grade)
    end

    function xPlayer.showNotification(message)
        TriggerClientEvent('gain_core:notify', player.source, message, 'info')
    end

    function xPlayer.triggerEvent(name, ...)
        TriggerClientEvent(name, player.source, ...)
    end

    return xPlayer
end

function ESX.GetPlayerFromId(src)
    return makeXPlayer(playerOf(src))
end

function ESX.GetPlayerFromIdentifier(identifier)
    for _, player in pairs(GetGainPlayers()) do
        if player.license == identifier then
            return makeXPlayer(player)
        end
    end
    return nil
end

function ESX.GetPlayers()
    local list = {}
    for src in pairs(GetGainPlayers()) do
        list[#list + 1] = src
    end
    return list
end

function ESX.GetExtendedPlayers()
    local list = {}
    for _, player in pairs(GetGainPlayers()) do
        list[#list + 1] = makeXPlayer(player)
    end
    return list
end

if Config.Compat.esx then
    AddEventHandler('esx:getSharedObject', function(cb)
        if cb then cb(ESX) end
    end)

    exports('getSharedObject', function()
        return ESX
    end)
end

----------------------------------------------------------------------
-- QBCore
----------------------------------------------------------------------

local QBCore = { Functions = {}, Shared = { Jobs = {} } }

local function makeQBPlayer(player)
    if not player then return nil end

    local qb = {
        PlayerData = {
            source = player.source,
            citizenid = player.citizenid,
            license = player.license,
            name = player.name,
            charinfo = { firstname = player.name, lastname = '' },
            money = { cash = player.money.cash, bank = player.money.bank },
            job = {
                name = player.job.name,
                label = player.job.name,
                grade = { level = player.job.grade, name = tostring(player.job.grade) },
                onduty = player.job.duty,
            },
            metadata = player.metadata,
        },
        Functions = {},
    }

    function qb.Functions.AddMoney(account, amount, reason)
        return Money.add(player, account == 'bank' and 'bank' or 'cash', amount, reason or 'qb')
    end

    function qb.Functions.RemoveMoney(account, amount, reason)
        return Money.remove(player, account == 'bank' and 'bank' or 'cash', amount, reason or 'qb')
    end

    function qb.Functions.GetMoney(account)
        return Money.get(player, account == 'bank' and 'bank' or 'cash')
    end

    function qb.Functions.SetJob(name, grade)
        return exports['gain_core']:SetJob(player.source, name, grade)
    end

    function qb.Functions.SetJobDuty(duty)
        return exports['gain_core']:SetDuty(player.source, duty)
    end

    function qb.Functions.Save()
        player.save()
    end

    return qb
end

function QBCore.Functions.GetPlayer(src)
    return makeQBPlayer(playerOf(src))
end

function QBCore.Functions.GetPlayerByCitizenId(citizenid)
    for _, player in pairs(GetGainPlayers()) do
        if player.citizenid == citizenid then
            return makeQBPlayer(player)
        end
    end
    return nil
end

function QBCore.Functions.GetPlayers()
    local list = {}
    for src in pairs(GetGainPlayers()) do
        list[#list + 1] = src
    end
    return list
end

function QBCore.Functions.GetQBPlayers()
    local list = {}
    for src, player in pairs(GetGainPlayers()) do
        list[src] = makeQBPlayer(player)
    end
    return list
end

function QBCore.Functions.Notify(src, message, kind)
    TriggerClientEvent('gain_core:notify', src, message, kind or 'info')
end

function QBCore.Functions.HasPermission(src, level)
    return Permission.has(src, level)
end

if Config.Compat.qbcore then
    AddEventHandler('QBCore:GetObject', function(cb)
        if cb then cb(QBCore) end
    end)

    exports('GetCoreObject', function()
        return QBCore
    end)
end
