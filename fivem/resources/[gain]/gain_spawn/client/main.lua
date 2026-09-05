-- スポーンの実処理。座標・向き・可視化・コリジョン待ち・ロード画面の畳み方を
-- ここに集約する。位置の決定はサーバー側が行い、ここは指示された場所に置くだけ。

-- 標準の自動スポーンを止める。位置を決めるのはこのリソースだけにする。
-- basic-gamemode を外していれば誰も setAutoSpawn(true) を呼ばないが、
-- 別のリソースが後から入っても効くように毎回明示的に切っておく。
CreateThread(function()
    while not NetworkIsSessionStarted() do
        Wait(100)
    end
    pcall(function()
        exports.spawnmanager:setAutoSpawn(false)
    end)
end)

local spawned = false      -- 一度でもスポーンが完了したか
local dead = false         -- 死亡中か
local deadUntil = 0        -- 復帰可能になる GetGameTimer 時刻

--- 既定の ped モデルを適用する。
--- 既にそのモデルなら何もしない（復帰のたびに外見が飛ばないように）。
local function ensureModel()
    local want = GetHashKey(SpawnConfig.PedModel)
    if GetEntityModel(PlayerPedId()) == want then return end

    RequestModel(want)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(want) and GetGameTimer() < timeout do
        Wait(50)
    end

    if not HasModelLoaded(want) then return end

    SetPlayerModel(PlayerId(), want)
    SetModelAsNoLongerNeeded(want)
end

--- 指定座標へ置く。周囲のコリジョンが載るまで固定しておく。
local function placeAt(pos)
    local ped = PlayerPedId()

    FreezeEntityPosition(ped, true)
    SetEntityCoordsNoOffset(ped, pos.x + 0.0, pos.y + 0.0, pos.z + 0.0, false, false, false)
    SetEntityHeading(ped, (pos.heading or 0.0) + 0.0)

    RequestCollisionAtCoord(pos.x + 0.0, pos.y + 0.0, pos.z + 0.0)
    local timeout = GetGameTimer() + SpawnConfig.CollisionTimeoutMs
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do
        Wait(50)
    end

    FreezeEntityPosition(ped, false)
end

--- スポーンさせる。
---@param pos table 座標
---@param revive boolean 死亡状態からの復帰か
local function doSpawn(pos, revive)
    pos = pos or SpawnConfig.Default

    DoScreenFadeOut(revive and 500 or 0)
    local fadeWait = GetGameTimer() + 1500
    while not IsScreenFadedOut() and GetGameTimer() < fadeWait do
        Wait(0)
    end

    ensureModel()

    local ped = PlayerPedId()
    if revive or IsEntityDead(ped) then
        -- 蘇生してから移動させる。順序を逆にすると死体のまま移動して見える
        NetworkResurrectLocalPlayer(pos.x + 0.0, pos.y + 0.0, pos.z + 0.0, (pos.heading or 0.0) + 0.0, true, false)
        ped = PlayerPedId()
    end

    placeAt(pos)

    SetEntityVisible(ped, true, false)
    SetPlayerInvincible(PlayerId(), false)
    ClearPedTasksImmediately(ped)
    ClearPedBloodDamage(ped)

    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    DoScreenFadeIn(1000)

    spawned = true
    dead = false
end

-- gain_core がキャラクターを読み込み終えると、保存されていた位置つきで飛んでくる。
-- gain_core 側はこのイベントを投げるところまでが責務で、実処理はここが持つ。
RegisterNetEvent('gain_core:spawn', function(pos)
    doSpawn(pos, false)
end)

-- 死亡からの復帰。座標はサーバーが決める。
RegisterNetEvent('gain_spawn:doSpawn', function(pos)
    doSpawn(pos, true)
end)

-- 死亡した瞬間にサーバーへ伝える。サーバー側で裏を取ってから死亡として扱う。
CreateThread(function()
    while true do
        Wait(SpawnConfig.DeathPollMs)

        if spawned and not dead and IsEntityDead(PlayerPedId()) then
            dead = true
            deadUntil = GetGameTimer() + SpawnConfig.RespawnSeconds * 1000
            TriggerServerEvent('gain_spawn:reportDeath')
        end
    end
end)

-- 死亡中の表示。復帰までの残り秒数を出す。
CreateThread(function()
    while true do
        if dead then
            Wait(0)

            local left = math.max(0, math.ceil((deadUntil - GetGameTimer()) / 1000))
            local text = left > 0
                and ('死亡しました。%d 秒後に病院で復帰します。'):format(left)
                or '復帰しています…'

            SetTextFont(4)
            SetTextScale(0.5, 0.5)
            SetTextColour(255, 255, 255, 220)
            SetTextCentre(true)
            SetTextOutline()
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(text)
            EndTextCommandDisplayText(0.5, 0.8)

            -- 死んでいる間は操作させない
            DisableAllControlActions(0)
            EnableControlAction(0, 249, true) -- プッシュトゥトークだけは通す
        else
            Wait(250)
        end
    end
end)

-- 保険。サーバーからの指示が届かないままロード画面で詰むのを防ぐ。
CreateThread(function()
    local deadline = GetGameTimer() + SpawnConfig.LoadTimeoutMs

    while not spawned and GetGameTimer() < deadline do
        Wait(500)
    end

    if not spawned then
        print('[gain_spawn] スポーン指示が届かなかったため既定地点に出します')
        doSpawn(SpawnConfig.Default, false)
    end
end)
