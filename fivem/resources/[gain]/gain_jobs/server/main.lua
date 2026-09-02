-- ジョブのサーバー側。就職・勤務・給料・ミッションの判定を行う。
-- 報酬額は必ず config から計算し、クライアントから受け取った数値は使わない。

local core = exports['gain_core']
local missions = {}

local function jobOf(name)
    return JobConfig.Jobs[name]
end

local function distanceTo(src, point)
    local coords = GetEntityCoords(GetPlayerPed(src))
    return #(coords - vector3(point.x, point.y, point.z))
end

local function recordSalary(citizenid, amount)
    MySQL.insert('INSERT INTO gain_transactions (citizenid, kind, amount, counterparty, reason) VALUES (?, ?, ?, ?, ?)', {
        citizenid, 'salary', amount, '', '給料',
    })
end

----------------------------------------------------------------------
-- 就職 / 退職
----------------------------------------------------------------------

RegisterSafeEvent('gain_jobs:requestList', { rate = { max = 5, per = 3000 } }, function(src)
    if distanceTo(src, JobConfig.JobCenter) > JobConfig.Radius + 4.0 then return end

    local player = core:GetPlayer(src)
    if not player then return end

    local list = {}
    for _, name in ipairs(JobConfig.Hireable) do
        local job = jobOf(name)
        if job then
            list[#list + 1] = {
                name = name,
                label = job.label,
                salary = job.grades[0] and job.grades[0].salary or 0,
                duty = job.duty and job.duty.label or '-',
                current = player.job.name == name,
            }
        end
    end

    TriggerClientEvent('gain_jobs:setList', src, list, player.job)
end)

RegisterSafeEvent('gain_jobs:apply', { rate = { max = 5, per = 5000 } }, function(src, name)
    if type(name) ~= 'string' then return end
    if distanceTo(src, JobConfig.JobCenter) > JobConfig.Radius + 4.0 then
        core:Notify(src, 'ハローワークで手続きしてください。', 'error')
        return
    end

    local job = jobOf(name)
    if not job or (name ~= 'unemployed' and not job.grades[0]) then
        core:Notify(src, _L('job_unknown'), 'error')
        return
    end

    -- 就職できるのは Hireable と退職（unemployed）のみ
    local allowed = (name == 'unemployed')
    for _, hireable in ipairs(JobConfig.Hireable) do
        if hireable == name then allowed = true end
    end

    if not allowed then
        core:Notify(src, _L('job_unknown'), 'error')
        return
    end

    missions[src] = nil
    core:SetJob(src, name, 0, job.label)
end)

----------------------------------------------------------------------
-- 勤務
----------------------------------------------------------------------

RegisterSafeEvent('gain_jobs:toggleDuty', { rate = { max = 5, per = 5000 } }, function(src)
    local player = core:GetPlayer(src)
    if not player then return end

    local job = jobOf(player.job.name)
    if not job or not job.duty then
        core:Notify(src, '勤務を切り替えられる職業ではありません。', 'error')
        return
    end

    if distanceTo(src, job.duty) > JobConfig.Radius + 4.0 then
        core:Notify(src, ('%s で手続きしてください。'):format(job.duty.label), 'error')
        return
    end

    local duty = not player.job.duty
    core:SetDuty(src, duty)

    if not duty then
        missions[src] = nil
    end

    core:Notify(src, duty and '勤務を開始しました。' or '勤務を終了しました。', 'success')
end)

----------------------------------------------------------------------
-- ミッション
----------------------------------------------------------------------

local function pickPoints(pool, count)
    local indices = {}
    for i = 1, #pool do indices[i] = i end

    for i = #indices, 2, -1 do
        local j = math.random(i)
        indices[i], indices[j] = indices[j], indices[i]
    end

    local picked = {}
    for i = 1, math.min(count, #indices) do
        local point = pool[indices[i]]
        picked[i] = { x = point.x, y = point.y, z = point.z, done = false }
    end

    return picked
end

RegisterSafeEvent('gain_jobs:startMission', { rate = { max = 3, per = 10000 } }, function(src)
    local player = core:GetPlayer(src)
    if not player then return end

    local job = jobOf(player.job.name)
    if not job or not job.mission then
        core:Notify(src, 'この職業に業務はありません。', 'error')
        return
    end

    if not player.job.duty then
        core:Notify(src, '先に勤務を開始してください。', 'error')
        return
    end

    if missions[src] then
        core:Notify(src, 'すでに業務中です。', 'warn')
        return
    end

    if distanceTo(src, job.duty) > JobConfig.Radius + 10.0 then
        core:Notify(src, ('%s から開始してください。'):format(job.duty.label), 'error')
        return
    end

    missions[src] = {
        job = player.job.name,
        points = pickPoints(job.mission.points, job.mission.stops),
        startedAt = os.time(),
    }

    TriggerClientEvent('gain_jobs:setMission', src, {
        label = job.mission.label,
        vehicle = job.mission.vehicle,
        points = missions[src].points,
        returnPoint = job.mission.returnPoint,
    })

    core:Notify(src, ('%s を開始しました。'):format(job.mission.label), 'success')
end)

RegisterSafeEvent('gain_jobs:claimStop', { rate = { max = 10, per = 5000 } }, function(src, index)
    local mission = missions[src]
    if not mission then return end

    index = tonumber(index)
    local point = index and mission.points[index]
    if not point or point.done then return end

    if distanceTo(src, point) > JobConfig.ClaimRadius then
        core:Notify(src, 'その地点から離れすぎています。', 'error')
        return
    end

    point.done = true

    local remaining = 0
    for _, p in ipairs(mission.points) do
        if not p.done then remaining = remaining + 1 end
    end

    TriggerClientEvent('gain_jobs:stopDone', src, index, remaining)

    if remaining == 0 then
        local job = jobOf(mission.job)
        core:Notify(src, ('全て完了しました。%s へ戻ってください。'):format(job.duty.label), 'success')
    end
end)

RegisterSafeEvent('gain_jobs:finishMission', { rate = { max = 3, per = 10000 } }, function(src)
    local mission = missions[src]
    if not mission then return end

    local job = jobOf(mission.job)
    if not job or not job.mission then
        missions[src] = nil
        return
    end

    local done = 0
    for _, p in ipairs(mission.points) do
        if p.done then done = done + 1 end
    end

    if done < #mission.points then
        core:Notify(src, ('残り %d 箇所あります。'):format(#mission.points - done), 'warn')
        return
    end

    if distanceTo(src, job.mission.returnPoint) > JobConfig.ClaimRadius then
        core:Notify(src, ('%s へ戻ってください。'):format(job.duty.label), 'error')
        return
    end

    -- 報酬はサーバー側の config からのみ計算する
    local pay = done * job.mission.payPerStop + job.mission.bonus
    missions[src] = nil

    core:AddMoney(src, 'cash', pay, ('mission:%s'):format(job.label))
    TriggerClientEvent('gain_jobs:setMission', src, nil)
    core:Notify(src, ('業務完了。報酬 $%d を受け取りました。'):format(pay), 'success')
end)

----------------------------------------------------------------------
-- 給料
----------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(JobConfig.PaycheckMinutes * 60000)

        for _, player in ipairs(core:GetPlayers()) do
            local job = jobOf(player.job.name)
            local grade = job and job.grades[player.job.grade]

            if grade and grade.salary > 0 then
                if not JobConfig.PayOnDutyOnly or player.job.duty then
                    if core:AddMoney(player.source, 'bank', grade.salary, 'salary') then
                        recordSalary(player.citizenid, grade.salary)
                        core:Notify(player.source,
                            ('給料 $%d が振り込まれました。'):format(grade.salary), 'success')
                    end
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    missions[source] = nil
end)

AddEventHandler('gain_core:jobChanged', function(src)
    missions[src] = nil
end)
