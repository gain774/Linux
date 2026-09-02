-- 銀行窓口と ATM の操作。表示と入力だけを担当し、金額はサーバーが判定する。

local uiOpen = false
local atmHashes = {}

CreateThread(function()
    for _, prop in ipairs(BankConfig.AtmProps) do
        atmHashes[#atmHashes + 1] = GetHashKey(prop)
    end
end)

local function openUi(mode)
    if uiOpen then return end

    uiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openBank', mode = mode })
    TriggerServerEvent('gain_banking:requestState')
end

local function closeUi()
    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeBank' })
end

RegisterNetEvent('gain_banking:setState', function(state)
    SendNUIMessage({ action = 'setState', state = state })
end)

RegisterNUICallback('close', function(_, cb)
    closeUi()
    cb('ok')
end)

RegisterNUICallback('deposit', function(data, cb)
    TriggerServerEvent('gain_banking:deposit', data.amount)
    cb('ok')
end)

RegisterNUICallback('withdraw', function(data, cb)
    TriggerServerEvent('gain_banking:withdraw', data.amount)
    cb('ok')
end)

RegisterNUICallback('transfer', function(data, cb)
    TriggerServerEvent('gain_banking:transfer', data.target, data.amount)
    cb('ok')
end)

-- 地図のブリップ
CreateThread(function()
    if not BankConfig.Blip.enabled then return end

    for _, bank in ipairs(BankConfig.Banks) do
        local blip = AddBlipForCoord(bank.x, bank.y, bank.z)
        SetBlipSprite(blip, BankConfig.Blip.sprite)
        SetBlipColour(blip, BankConfig.Blip.color)
        SetBlipScale(blip, BankConfig.Blip.scale)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(BankConfig.Blip.label)
        EndTextCommandSetBlipName(blip)
    end
end)

local function nearestBank(coords)
    local closest, distance = nil, 999.0

    for _, bank in ipairs(BankConfig.Banks) do
        local d = #(coords - vector3(bank.x, bank.y, bank.z))
        if d < distance then
            closest, distance = bank, d
        end
    end

    return closest, distance
end

local function nearestAtm(coords)
    for _, hash in ipairs(atmHashes) do
        local object = GetClosestObjectOfType(coords.x, coords.y, coords.z, BankConfig.Radius + 0.6, hash, false, false, false)
        if object ~= 0 then
            return GetEntityCoords(object)
        end
    end

    return nil
end

-- 近接判定。毎フレーム走らせないよう、離れている間は間隔を空ける
CreateThread(function()
    while true do
        local wait = 800
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)

        local bank, distance = nearestBank(coords)
        local atmCoords = (distance > 30.0) and nearestAtm(coords) or nil

        local point, mode = nil, nil
        if bank and distance <= 25.0 then
            point, mode = vector3(bank.x, bank.y, bank.z), 'bank'
        elseif atmCoords then
            point, mode = atmCoords, 'atm'
        end

        if point then
            wait = 0
            DrawMarker(2, point.x, point.y, point.z + 1.0, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
                0.25, 0.25, 0.2, 40, 130, 255, 160, false, false, 2, true, nil, nil, false)

            if #(coords - point) <= BankConfig.Radius and not uiOpen then
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName(
                    mode == 'bank' and '~INPUT_CONTEXT~ 銀行を利用する' or '~INPUT_CONTEXT~ ATM を利用する')
                EndTextCommandDisplayHelp(0, false, true, -1)

                if IsControlJustReleased(0, 38) then
                    openUi(mode)
                end
            end
        end

        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        SetNuiFocus(false, false)
    end
end)
