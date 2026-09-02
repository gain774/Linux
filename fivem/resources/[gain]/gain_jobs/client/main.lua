-- ジョブのクライアント側。マーカー表示と操作だけを行い、
-- 到達判定・報酬計算はサーバーが再検証する。

local uiOpen = false
local mission = nil
local missionBlips = {}
local playerJob = { name = 'unemployed', grade = 0, duty = false }

AddEventHandler('gain_core:playerDataUpdated', function(data)
    playerJob = data.job
end)

----------------------------------------------------------------------
-- 就職所 UI
----------------------------------------------------------------------

local function closeUi()
    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeJobs' })
end

RegisterNetEvent('gain_jobs:setList', function(list, job)
    uiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openJobs', jobs = list, current = job })
end)

RegisterNUICallback('close', function(_, cb)
    closeUi()
    cb('ok')
end)

RegisterNUICallback('apply', function(data, cb)
    TriggerServerEvent('gain_jobs:apply', data.name)
    closeUi()
    cb('ok')
end)

----------------------------------------------------------------------
-- ミッション
----------------------------------------------------------------------

local function clearBlips()
    for _, blip in ipairs(missionBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    missionBlips = {}
end

local function addBlip(point, label, sprite, color)
    local blip = AddBlipForCoord(point.x, point.y, point.z)
    SetBlipSprite(blip, sprite)
    SetBlipColour(blip, color)
    SetBlipScale(blip, 0.8)
    SetBlipRoute(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(blip)
    missionBlips[#missionBlips + 1] = blip
    return blip
end

local function refreshBlips()
    clearBlips()
    if not mission then return end

    local remaining = 0
    for i, point in ipairs(mission.points) do
        if not point.done then
            remaining = remaining + 1
            addBlip(point, ('%s %d'):format(mission.label, i), 1, 5)
        end
    end

    if remaining == 0 then
        addBlip(mission.returnPoint, ('%s 完了報告'):format(mission.label), 1, 2)
    end
end

local function spawnMissionVehicle(model)
    if not model then return end

    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return end

    RequestModel(hash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Wait(50)
    end
    if not HasModelLoaded(hash) then return end

    local ped = PlayerPedId()
    local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 5.0, 0.0)
    local vehicle = CreateVehicle(hash, coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)

    SetVehicleOnGroundProperly(vehicle)
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    SetModelAsNoLongerNeeded(hash)
end

RegisterNetEvent('gain_jobs:setMission', function(data)
    mission = data

    if not mission then
        clearBlips()
        return
    end

    spawnMissionVehicle(mission.vehicle)
    refreshBlips()
end)

RegisterNetEvent('gain_jobs:stopDone', function(index, remaining)
    if not mission then return end

    if mission.points[index] then
        mission.points[index].done = true
    end

    refreshBlips()
    TriggerEvent('gain_core:notify', ('残り %d 箇所です。'):format(remaining), 'info')
end)

----------------------------------------------------------------------
-- マーカーと操作
----------------------------------------------------------------------

local function helpText(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

local function marker(point, r, g, b)
    DrawMarker(1, point.x, point.y, point.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        1.6, 1.6, 0.8, r, g, b, 120, false, false, 2, false, nil, nil, false)
end

CreateThread(function()
    if JobConfig.JobCenter.blip then
        local blip = AddBlipForCoord(JobConfig.JobCenter.x, JobConfig.JobCenter.y, JobConfig.JobCenter.z)
        SetBlipSprite(blip, JobConfig.JobCenter.blip.sprite)
        SetBlipColour(blip, JobConfig.JobCenter.blip.color)
        SetBlipScale(blip, JobConfig.JobCenter.blip.scale)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(JobConfig.JobCenter.label)
        EndTextCommandSetBlipName(blip)
    end
end)

CreateThread(function()
    while true do
        local wait = 700
        local coords = GetEntityCoords(PlayerPedId())

        -- 就職所
        local center = JobConfig.JobCenter
        if #(coords - vector3(center.x, center.y, center.z)) < 20.0 then
            wait = 0
            marker(center, 40, 130, 255)

            if #(coords - vector3(center.x, center.y, center.z)) <= JobConfig.Radius and not uiOpen then
                helpText('~INPUT_CONTEXT~ 求人を見る')
                if IsControlJustReleased(0, 38) then
                    TriggerServerEvent('gain_jobs:requestList')
                end
            end
        end

        -- 勤務地点
        local job = JobConfig.Jobs[playerJob.name]
        if job and job.duty then
            local duty = job.duty
            local distance = #(coords - vector3(duty.x, duty.y, duty.z))

            if distance < 20.0 then
                wait = 0
                marker(duty, 60, 200, 120)

                if distance <= JobConfig.Radius then
                    if not playerJob.duty then
                        helpText('~INPUT_CONTEXT~ 勤務を開始する')
                        if IsControlJustReleased(0, 38) then
                            TriggerServerEvent('gain_jobs:toggleDuty')
                        end
                    elseif not mission then
                        helpText('~INPUT_CONTEXT~ 業務を開始する / ~INPUT_DETONATE~ 勤務を終了する')
                        if IsControlJustReleased(0, 38) then
                            TriggerServerEvent('gain_jobs:startMission')
                        elseif IsControlJustReleased(0, 47) then
                            TriggerServerEvent('gain_jobs:toggleDuty')
                        end
                    end
                end
            end
        end

        -- ミッションのポイント
        if mission then
            local remaining = 0

            for index, point in ipairs(mission.points) do
                if not point.done then
                    remaining = remaining + 1
                    local distance = #(coords - vector3(point.x, point.y, point.z))

                    if distance < 30.0 then
                        wait = 0
                        marker(point, 255, 200, 60)

                        if distance <= JobConfig.ClaimRadius - 2.0 then
                            helpText(('~INPUT_CONTEXT~ %s'):format(mission.label))
                            if IsControlJustReleased(0, 38) then
                                TriggerServerEvent('gain_jobs:claimStop', index)
                            end
                        end
                    end
                end
            end

            if remaining == 0 then
                local point = mission.returnPoint
                local distance = #(coords - vector3(point.x, point.y, point.z))

                if distance < 30.0 then
                    wait = 0
                    marker(point, 60, 200, 120)

                    if distance <= JobConfig.ClaimRadius - 2.0 then
                        helpText('~INPUT_CONTEXT~ 完了を報告する')
                        if IsControlJustReleased(0, 38) then
                            TriggerServerEvent('gain_jobs:finishMission')
                        end
                    end
                end
            end
        end

        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearBlips()
    SetNuiFocus(false, false)
end)
