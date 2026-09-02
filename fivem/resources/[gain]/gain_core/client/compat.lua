-- ESX / QBCore 互換レイヤー（クライアント側）。
-- サーバー側と同じく、プレイヤーデータ参照と通知までをカバーする最小限のブリッジ。

if not Config.Compat.esx and not Config.Compat.qbcore then return end

local function notify(message)
    TriggerEvent('gain_core:notify', message, 'info')
end

----------------------------------------------------------------------
-- ESX
----------------------------------------------------------------------

local ESX = { PlayerData = {}, PlayerLoaded = false }

function ESX.GetPlayerData()
    return ESX.PlayerData
end

function ESX.ShowNotification(message)
    notify(message)
end

function ESX.ShowAdvancedNotification(_, _, message)
    notify(message)
end

----------------------------------------------------------------------
-- QBCore
----------------------------------------------------------------------

local QBCore = { Functions = {}, PlayerData = {}, Shared = { Jobs = {} } }

function QBCore.Functions.GetPlayerData(cb)
    if cb then cb(QBCore.PlayerData) end
    return QBCore.PlayerData
end

function QBCore.Functions.Notify(message)
    notify(message)
end

----------------------------------------------------------------------
-- gain_core のデータを両方の形に写す
----------------------------------------------------------------------

AddEventHandler('gain_core:playerDataUpdated', function(data)
    ESX.PlayerLoaded = true
    ESX.PlayerData = {
        identifier = data.citizenid,
        name = data.name,
        money = data.money.cash,
        accounts = {
            { name = 'money', money = data.money.cash },
            { name = 'bank', money = data.money.bank },
        },
        job = {
            name = data.job.name,
            label = data.job.name,
            grade = data.job.grade,
            grade_name = tostring(data.job.grade),
        },
    }

    QBCore.PlayerData = {
        citizenid = data.citizenid,
        name = data.name,
        charinfo = { firstname = data.name, lastname = '' },
        money = { cash = data.money.cash, bank = data.money.bank },
        job = {
            name = data.job.name,
            label = data.job.name,
            grade = { level = data.job.grade, name = tostring(data.job.grade) },
            onduty = data.job.duty,
        },
        metadata = {},
    }

    TriggerEvent('esx:playerLoaded', ESX.PlayerData)
    TriggerEvent('QBCore:Client:OnPlayerLoaded')
    TriggerEvent('QBCore:Player:SetPlayerData', QBCore.PlayerData)
end)

if Config.Compat.esx then
    AddEventHandler('esx:getSharedObject', function(cb)
        if cb then cb(ESX) end
    end)

    exports('getSharedObject', function()
        return ESX
    end)
end

if Config.Compat.qbcore then
    AddEventHandler('QBCore:GetObject', function(cb)
        if cb then cb(QBCore) end
    end)

    exports('GetCoreObject', function()
        return QBCore
    end)
end
