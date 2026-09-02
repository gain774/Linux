-- 管理メニューのクライアント側。判定はサーバーが行うので、
-- ここは表示と、サーバーから指示された演出（テレポート・回復など）の実行に徹する。

local menuOpen = false
local spectating = false
local spectateReturn = nil

local function openMenu()
    if menuOpen then return end
    TriggerServerEvent('gain_admin:requestPlayers')
end

local function closeMenu()
    menuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeAdmin' })
end

RegisterNetEvent('gain_admin:setPlayers', function(players, meta)
    menuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openAdmin',
        players = players,
        meta = meta,
    })
end)

RegisterCommand('admin', openMenu, false)
RegisterKeyMapping('admin', '管理メニューを開く', 'keyboard', AdminConfig.MenuKey)

----------------------------------------------------------------------
-- NUI からの入力
----------------------------------------------------------------------

RegisterNUICallback('close', function(_, cb)
    closeMenu()
    cb('ok')
end)

RegisterNUICallback('refresh', function(_, cb)
    TriggerServerEvent('gain_admin:requestPlayers')
    cb('ok')
end)

RegisterNUICallback('action', function(data, cb)
    TriggerServerEvent('gain_admin:action', data.name, data.target, data.payload or {})

    -- 画面を占有し続けると操作の結果が見えないので、演出系は閉じる
    if data.name == 'tpto' or data.name == 'bring' or data.name == 'spectate' then
        closeMenu()
    end

    cb('ok')
end)

RegisterNUICallback('spawnVehicle', function(data, cb)
    TriggerServerEvent('gain_admin:spawnVehicle', data.model)
    closeMenu()
    cb('ok')
end)

----------------------------------------------------------------------
-- サーバーからの指示
----------------------------------------------------------------------

RegisterNetEvent('gain_admin:heal', function(revive)
    local ped = PlayerPedId()

    if revive and IsEntityDead(ped) then
        local coords = GetEntityCoords(ped)
        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)
    end

    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    SetPedArmour(ped, 100)
    ClearPedBloodDamage(ped)
end)

RegisterNetEvent('gain_admin:teleport', function(pos)
    local ped = PlayerPedId()

    DoScreenFadeOut(300)
    Wait(350)

    local vehicle = GetVehiclePedIsIn(ped, false)
    local entity = (vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped) and vehicle or ped

    RequestCollisionAtCoord(pos.x + 0.0, pos.y + 0.0, pos.z + 0.0)
    SetEntityCoords(entity, pos.x + 0.0, pos.y + 0.0, pos.z + 1.0, false, false, false, false)

    local timeout = GetGameTimer() + 8000
    while not HasCollisionLoadedAroundEntity(entity) and GetGameTimer() < timeout do
        Wait(50)
    end

    DoScreenFadeIn(400)
end)

RegisterNetEvent('gain_admin:spawnVehicle', function(model)
    local hash = GetHashKey(model)

    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        TriggerEvent('gain_core:notify', ('車両モデル %s は存在しません。'):format(model), 'error')
        return
    end

    RequestModel(hash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Wait(50)
    end

    if not HasModelLoaded(hash) then
        TriggerEvent('gain_core:notify', '車両の読み込みに失敗しました。', 'error')
        return
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local vehicle = CreateVehicle(hash, coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)

    SetVehicleOnGroundProperly(vehicle)
    SetPedIntoVehicle(ped, vehicle, -1)
    SetModelAsNoLongerNeeded(hash)

    TriggerEvent('gain_core:notify', ('%s をスポーンしました。'):format(model), 'success')
end)

RegisterNetEvent('gain_admin:spectate', function(targetServerId)
    local ped = PlayerPedId()

    if spectating then
        NetworkSetInSpectatorMode(false, nil)
        SetEntityVisible(ped, true, false)
        SetEntityCollision(ped, true, true)
        FreezeEntityPosition(ped, false)
        SetEntityInvincible(ped, false)

        if spectateReturn then
            SetEntityCoords(ped, spectateReturn.x, spectateReturn.y, spectateReturn.z, false, false, false, false)
            spectateReturn = nil
        end

        spectating = false
        TriggerEvent('gain_core:notify', 'スペクテイトを解除しました。', 'info')
        return
    end

    local targetPlayer = GetPlayerFromServerId(targetServerId)
    if targetPlayer == -1 then
        TriggerEvent('gain_core:notify', '対象が近くにいないため観戦できません。', 'error')
        return
    end

    local targetPed = GetPlayerPed(targetPlayer)
    local targetCoords = GetEntityCoords(targetPed)
    local myCoords = GetEntityCoords(ped)

    spectateReturn = { x = myCoords.x, y = myCoords.y, z = myCoords.z }
    spectating = true

    RequestCollisionAtCoord(targetCoords.x, targetCoords.y, targetCoords.z)
    SetEntityCoords(ped, targetCoords.x, targetCoords.y, targetCoords.z + 2.0, false, false, false, false)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    NetworkSetInSpectatorMode(true, targetPed)

    TriggerEvent('gain_core:notify', '観戦中。もう一度実行すると解除します。', 'info')
end)

-- リソース停止時に観戦状態が残らないようにする
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    if spectating then
        NetworkSetInSpectatorMode(false, nil)
        local ped = PlayerPedId()
        SetEntityVisible(ped, true, false)
        SetEntityCollision(ped, true, true)
        FreezeEntityPosition(ped, false)
        SetEntityInvincible(ped, false)
    end

    SetNuiFocus(false, false)
end)
