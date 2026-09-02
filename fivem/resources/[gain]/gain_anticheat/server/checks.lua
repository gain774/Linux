-- 定期チェック。サーバーが直接見られる値（体力・装甲・座標）だけを使う。

local tracked = {}

local function reset(src)
    tracked[src] = {
        coords = nil,
        time = GetGameTimer(),
        graceUntil = GetGameTimer() + ACConfig.Movement.graceSeconds * 1000,
    }
end

AddEventHandler('gain_core:playerLoaded', function(src)
    reset(src)
end)

AddEventHandler('playerDropped', function()
    tracked[source] = nil
end)

-- 死亡・リスポーン直後は座標が飛ぶので猶予を入れ直す
RegisterNetEvent('baseevents:onPlayerDied', function()
    reset(source)
end)

RegisterNetEvent('baseevents:onPlayerKilled', function()
    reset(source)
end)

local function checkHealth(src, ped)
    local health = GetEntityHealth(ped)
    if health > ACConfig.Health.max then
        AC.flag(src, 'health', '体力が上限を超えている', { health = health })
    end

    local armour = GetPedArmour(ped)
    if armour > ACConfig.Health.maxArmour then
        AC.flag(src, 'armour', '装甲が上限を超えている', { armour = armour })
    end
end

local function checkMovement(src, ped, state)
    local coords = GetEntityCoords(ped)
    local now = GetGameTimer()

    if not state.coords then
        state.coords = coords
        state.time = now
        return
    end

    local elapsed = (now - state.time) / 1000
    state.time = now

    local previous = state.coords
    state.coords = coords

    if elapsed <= 0 or now < state.graceUntil then return end

    local distance = #(coords - previous)
    local speed = distance / elapsed
    local inVehicle = GetVehiclePedIsIn(ped, false) ~= 0

    if distance > ACConfig.Movement.maxJump then
        AC.flag(src, 'teleport', '瞬間移動を検知', {
            distance = ('%.1fm'):format(distance),
            seconds = ('%.1f'):format(elapsed),
        })
        return
    end

    local limit = inVehicle and ACConfig.Movement.maxAny or ACConfig.Movement.maxOnFoot
    if speed > limit then
        AC.flag(src, 'speed', '移動速度が異常', {
            speed = ('%.1fm/s'):format(speed),
            limit = limit,
            vehicle = inVehicle,
        })
    end
end

CreateThread(function()
    while true do
        Wait(ACConfig.Interval)

        for _, src in ipairs(GetPlayers()) do
            src = tonumber(src)
            local ped = GetPlayerPed(src)

            if ped and ped ~= 0 then
                local state = tracked[src]
                if not state then
                    reset(src)
                    state = tracked[src]
                end

                checkHealth(src, ped)
                checkMovement(src, ped, state)
            end
        end
    end
end)

-- クライアントからの武器所持レポート。
-- クライアント側の申告なので改ざんできるが、既製のチートメニューは
-- これを黙らせないため、素通しよりは確実に引っかかる。
RegisterSafeEvent('gain_anticheat:reportWeapon', { rate = { max = 5, per = 10000 } }, function(src, weapon)
    if type(weapon) ~= 'string' or #weapon > 48 then return end

    for _, name in ipairs(ACConfig.BlacklistedWeapons) do
        if name == weapon then
            AC.flag(src, 'weapon', '禁止武器の所持を検知', { weapon = weapon })
            return
        end
    end
end)
