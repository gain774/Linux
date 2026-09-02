-- クライアント側の中枢。スポーン制御・データ同期・通知。

GainPlayerData = nil
local isLoaded = false

--- 自分のキャラクターデータ（サーバーから同期された公開データ）。
exports('GetPlayerData', function()
    return GainPlayerData
end)

exports('IsLoaded', function()
    return isLoaded
end)

RegisterNetEvent('gain_core:setPlayerData', function(data)
    GainPlayerData = data
    isLoaded = true
    TriggerEvent('gain_core:playerDataUpdated', data)
end)

RegisterNetEvent('gain_core:notify', function(message, kind)
    SendNUIMessage({
        action = 'notify',
        message = message,
        kind = kind or 'info',
    })
end)

RegisterNetEvent('gain_core:spawn', function(pos)
    local ped = PlayerPedId()

    DoScreenFadeOut(0)
    FreezeEntityPosition(ped, true)
    SetEntityCoordsNoOffset(ped, pos.x + 0.0, pos.y + 0.0, pos.z + 0.0, false, false, false)
    SetEntityHeading(ped, pos.heading + 0.0)

    RequestCollisionAtCoord(pos.x + 0.0, pos.y + 0.0, pos.z + 0.0)
    local timeout = GetGameTimer() + 10000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do
        Wait(50)
    end

    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetPlayerInvincible(PlayerId(), false)
    ClearPedTasksImmediately(ped)

    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    DoScreenFadeIn(1000)
end)

-- セッション確立後にサーバーへ読み込みを要求する。
CreateThread(function()
    while not NetworkIsSessionStarted() do
        Wait(100)
    end

    -- 既定のランダムスポーンを止め、gain_core の位置復元に任せる
    pcall(function()
        exports.spawnmanager:setAutoSpawn(false)
    end)

    Wait(500)
    TriggerServerEvent('gain_core:requestLoad')
end)

-- 位置を定期送信（切断時の復帰位置に使う）
CreateThread(function()
    while true do
        Wait(10000)

        if isLoaded then
            local coords = GetEntityCoords(PlayerPedId())
            TriggerServerEvent('gain_core:updatePosition', {
                x = coords.x,
                y = coords.y,
                z = coords.z,
                heading = GetEntityHeading(PlayerPedId()),
            })
        end
    end
end)
