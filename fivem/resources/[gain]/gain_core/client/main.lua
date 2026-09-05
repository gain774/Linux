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

-- スポーンの実処理は gain_spawn が持つ。
-- コアの責務は「キャラクターを読み込んで位置を渡す」ところまでで、
-- gain_core:spawn はリソース間のイベント契約としてサーバー側に残っている。

-- セッション確立後にサーバーへ読み込みを要求する。
CreateThread(function()
    while not NetworkIsSessionStarted() do
        Wait(100)
    end

    -- データが届くまで要求を繰り返す。固定の待ち時間に依存しない。
    -- サーバー側は 10 秒あたり 3 回までに制限しているので、間隔をそれに合わせる。
    local attempts = 0
    while not isLoaded and attempts < 5 do
        TriggerServerEvent('gain_core:requestLoad')
        attempts = attempts + 1

        local deadline = GetGameTimer() + 4000
        while not isLoaded and GetGameTimer() < deadline do
            Wait(100)
        end
    end

    if not isLoaded then
        print('[gain_core] キャラクターの読み込みに失敗しました。サーバーのログを確認してください。')
    end
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
