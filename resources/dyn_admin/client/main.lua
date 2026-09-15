--[[
  管理者ダッシュボード（NUI）のクライアント側。表示と入力の受け付けだけ。
  権限チェックは全部サーバー側でやる（NUI 側の isAdmin 判定は信用しない）。
]]

local open = false

local function closeUi()
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterCommand('dyn_admin', function()
    if open then return closeUi() end
    TriggerServerEvent('dyn_admin:requestOpen')
end, false)

RegisterNetEvent('dyn_admin:open', function(data)
    open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'init', data = data })
end)

RegisterNetEvent('dyn_admin:denied', function(reason)
    TriggerEvent('vorp:TipRight', ('管理者ダッシュボード: %s'):format(reason or '権限がありません'), 4000)
end)

RegisterNetEvent('dyn_admin:actionResult', function(result)
    SendNUIMessage({ action = 'actionResult', data = result })
end)

RegisterNUICallback('close', function(_, cb)
    closeUi()
    cb('ok')
end)

RegisterNUICallback('refresh', function(_, cb)
    TriggerServerEvent('dyn_admin:requestOpen')
    cb('ok')
end)

RegisterNUICallback('action', function(data, cb)
    TriggerServerEvent('dyn_admin:action', data.kind, data.payload)
    cb('ok')
end)
