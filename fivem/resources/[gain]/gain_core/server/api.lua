-- 他リソースから使う公開 API。
-- 例: exports['gain_core']:AddMoney(src, 'bank', 500, 'paycheck')

local function dataOf(player)
    if not player then return nil end

    return {
        source = player.source,
        citizenid = player.citizenid,
        name = player.name,
        permission = player.permission,
        money = { cash = player.money.cash, bank = player.money.bank },
        job = { name = player.job.name, grade = player.job.grade, duty = player.job.duty },
        position = player.position,
        metadata = player.metadata,
    }
end

exports('GetPlayer', function(src)
    return dataOf(GetGainPlayer(src))
end)

exports('GetPlayers', function()
    local list = {}
    for src, player in pairs(GetGainPlayers()) do
        list[#list + 1] = dataOf(player)
        list[#list].source = src
    end
    return list
end)

exports('GetPlayerByCitizenId', function(citizenid)
    for _, player in pairs(GetGainPlayers()) do
        if player.citizenid == citizenid then
            return dataOf(player)
        end
    end
    return nil
end)

exports('GetMoney', function(src, account)
    return Money.get(GetGainPlayer(src), account)
end)

exports('AddMoney', function(src, account, amount, reason)
    return Money.add(GetGainPlayer(src), account, amount, reason)
end)

exports('RemoveMoney', function(src, account, amount, reason)
    return Money.remove(GetGainPlayer(src), account, amount, reason)
end)

exports('SetMoney', function(src, account, amount, reason)
    return Money.set(GetGainPlayer(src), account, amount, reason)
end)

exports('GetJob', function(src)
    local player = GetGainPlayer(src)
    if not player then return nil end
    return { name = player.job.name, grade = player.job.grade, duty = player.job.duty }
end)

--- 職業を設定する。職業定義の存在確認は呼び出し側（gain_jobs）の責任。
exports('SetJob', function(src, name, grade, label)
    local player = GetGainPlayer(src)
    if not player or type(name) ~= 'string' then return false end

    player.job.name = name
    player.job.grade = tonumber(grade) or 0
    player.job.duty = false
    player.save()
    player.sync()

    TriggerEvent('gain_core:jobChanged', src, player.job)
    TriggerClientEvent('gain_core:notify', src, _L('job_changed', label or name), 'info')

    GainLog.write('info', '職業を変更', {
        player = player.name,
        citizenid = player.citizenid,
        job = name,
        grade = player.job.grade,
    })

    return true
end)

exports('SetDuty', function(src, duty)
    local player = GetGainPlayer(src)
    if not player then return false end

    player.job.duty = duty and true or false
    player.sync()
    TriggerEvent('gain_core:dutyChanged', src, player.job)
    return true
end)

exports('HasPermission', function(src, level)
    return Permission.has(src, level)
end)

exports('SetPermission', function(src, level)
    return Permission.set(src, level)
end)

exports('GetMetadata', function(src, key)
    local player = GetGainPlayer(src)
    if not player then return nil end
    return key and player.metadata[key] or player.metadata
end)

exports('SetMetadata', function(src, key, value)
    local player = GetGainPlayer(src)
    if not player or type(key) ~= 'string' then return false end

    player.metadata[key] = value
    return true
end)

exports('Notify', function(src, message, kind)
    TriggerClientEvent('gain_core:notify', src, message, kind or 'info')
end)

exports('SavePlayer', function(src)
    local player = GetGainPlayer(src)
    if not player then return false end
    player.save()
    return true
end)
