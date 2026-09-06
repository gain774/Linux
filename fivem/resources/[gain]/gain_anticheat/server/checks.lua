-- 定期チェック。サーバーが直接見られる値（体力・装甲・座標）だけを使う。

local tracked = {}

--- 猶予の付与回数。短い間隔で何度も入るのは、正常な死に方ではない。
local graceCount = {}

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
    graceCount[source] = nil
end)

-- 死亡・リスポーン直後は座標が飛ぶので猶予を入れ直す。
--
-- 以前はここで baseevents:onPlayerDied / onPlayerKilled を生の
-- RegisterNetEvent で受けていた。イベント名は公知なので、クライアントが
-- 猶予時間より短い間隔で撃ち続けるだけで、テレポート検知と速度検知を
-- 恒久的に無効化できた。クライアントからの入力を information source に
-- しない形へ変えてある。
--
--   ・gain_spawn がサーバー側で確定させた死亡（gain_spawn:playerDied）
--   ・巡回スレッドが見ている体力（0 になったら死亡とみなす）
--
-- 前者が使えない構成でも後者で拾えるようにしてある。
AddEventHandler('gain_spawn:playerDied', function(src)
    if src and src > 0 then reset(src) end
end)

local function grantGrace(src, why)
    local now = GetGameTimer()
    local g = graceCount[src]
    if not g or now - g.since > 60000 then
        g = { since = now, n = 0 }
        graceCount[src] = g
    end

    g.n = g.n + 1
    if g.n > (ACConfig.Movement.maxGracePerMinute or 3) then
        AC.flag(src, 'spam', '猶予の付与が異常に多い', { count = g.n, why = why })
        return
    end

    reset(src)
end

local function checkHealth(src, ped, state)
    local health = GetEntityHealth(ped)

    -- 死亡はサーバーが見ている体力で判定する。生き返った tick で猶予を張り直す。
    -- 座標が飛ぶのは復帰の瞬間なので、ここで入れれば足りる
    if state then
        local dead = health <= 0
        if dead ~= (state.wasDead or false) then
            state.wasDead = dead
            if not dead then grantGrace(src, 'revive') end
        end
        if dead then return end
    end

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

    if elapsed <= 0 or now < state.graceUntil or state.wasDead then return end

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

                checkHealth(src, ped, state)
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
