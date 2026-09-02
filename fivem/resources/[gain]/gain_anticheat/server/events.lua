-- ゲームのネットワークイベントに対する保護。
-- クライアントが直接発火できるため、サーバー側で握りつぶせるものは握りつぶす。

local explosions = {}

local function blocked(list, value)
    for _, entry in ipairs(list) do
        if entry == value then return true end
    end
    return false
end

AddEventHandler('explosionEvent', function(sender, ev)
    local src = tonumber(sender)
    if not src or src <= 0 then return end

    if blocked(ACConfig.NetEvents.blockedExplosions, ev.explosionType) then
        CancelEvent()
        AC.flag(src, 'explosion', '禁止された爆発タイプ', { explosionType = ev.explosionType })
        return
    end

    local now = GetGameTimer()
    local bucket = explosions[src]

    if not bucket or now - bucket.since >= 10000 then
        explosions[src] = { since = now, count = 1 }
        return
    end

    bucket.count = bucket.count + 1
    if bucket.count > ACConfig.NetEvents.explosionPer10s then
        if ACConfig.Mode == 'enforce' then CancelEvent() end
        AC.flag(src, 'explosion', '短時間に大量の爆発', {
            count = bucket.count,
            explosionType = ev.explosionType,
        })
    end
end)

AddEventHandler('giveWeaponEvent', function(sender)
    if not ACConfig.NetEvents.blockGiveWeapon then return end

    local src = tonumber(sender)
    if not src or src <= 0 then return end

    CancelEvent()
    AC.flag(src, 'giveWeapon', '他人への武器付与イベントを遮断')
end)

AddEventHandler('clearPedTasksEvent', function(sender)
    if not ACConfig.NetEvents.blockClearPedTasks then return end

    local src = tonumber(sender)
    if not src or src <= 0 then return end

    CancelEvent()
    AC.flag(src, 'clearTasks', '他人の行動キャンセルイベントを遮断')
end)

AddEventHandler('playerDropped', function()
    explosions[source] = nil
end)
