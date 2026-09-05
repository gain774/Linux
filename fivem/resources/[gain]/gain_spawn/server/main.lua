-- スポーンの権威。復帰地点はここが決め、クライアントには結果だけを渡す。
-- クライアントから座標を受け取ることは一切しない。

local core = exports['gain_core']

--- 死亡中のプレイヤー。src -> { at = 死亡時刻, timer = 復帰予定 }
local dying = {}

--- 復帰地点を返す。今は病院固定だが、将来ここを分岐させる
--- （所属する組織、最寄りの病院、BAN 明けの扱いなど）。
local function respawnPoint(_src)
    return SpawnConfig.Hospital
end

--- サーバー側から見た体力。
--- ビルドによっては player ped がサーバー側で解決できないことがあるため、
--- 取得できたかどうかも一緒に返す。
local function serverHealth(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityHealth(ped)
end

--- 復帰させる。
local function respawn(src)
    if not dying[src] then return end
    dying[src] = nil

    if not GetPlayerName(src) then return end   -- 死亡中に切断した

    TriggerClientEvent('gain_spawn:doSpawn', src, respawnPoint(src))
end

exports('Respawn', function(src)
    dying[src] = dying[src] or { at = os.time() }
    respawn(src)
    return true
end)

exports('IsDead', function(src)
    return dying[src] ~= nil
end)

-- クライアントは「死んだ」という事実だけを伝える。座標は送らせない。
-- サーバー側でも体力を確認し、食い違ったら記録に残す。
RegisterSafeEvent('gain_spawn:reportDeath', { rate = { max = 2, per = 5000 } }, function(src)
    if dying[src] then return end

    local player = core:GetPlayer(src)
    if not player then return end

    local health = serverHealth(src)

    -- サーバー側で「明らかに生きている」と分かる場合だけ拒否する。
    -- health が取得できない（nil）場合は判定材料が無いので受け入れる。
    -- 復帰させるだけの操作なので、偽装されても得るものが無い。
    if health and health > 100 then
        core:Log('cheat', '死亡していないのに死亡報告', {
            player = player.name,
            citizenid = player.citizenid,
            health = health,
        })
        return
    end

    dying[src] = { at = os.time() }

    -- GetEntityHealth がサーバー側で何を返すかを実測するための記録。
    -- 十分な件数が溜まったら、この値でクライアント報告なしの死亡検知に切り替えられる。
    core:Log('info', 'プレイヤーが死亡', {
        player = player.name,
        citizenid = player.citizenid,
        serverHealth = health == nil and 'nil' or health,
    })

    -- アンチチート等が信頼できる死亡の情報源として使う。
    -- クライアントの生イベント（baseevents）ではなく、検証を通ったこちらを見る。
    TriggerEvent('gain_spawn:playerDied', src, player.citizenid)

    SetTimeout(SpawnConfig.RespawnSeconds * 1000, function()
        respawn(src)
    end)
end)

AddEventHandler('playerDropped', function()
    dying[source] = nil
end)
