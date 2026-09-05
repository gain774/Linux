-- 部品の実在確認と、組んだ部屋が実際に歩けるかの検証。
--
-- 図面エディタを作る前に、出力先になる部品が存在するのかを確かめる。
-- プロップ名は推測で並べてあるので、ここで実測して候補表を作り直す。

local spawned = {}   -- 検証で出したオブジェクト。/gbuild clear で消す

--- モデルが実在して読み込めるか。
local function checkModel(model)
    local hash = GetHashKey(model)

    if not IsModelInCdimage(hash) then
        return false, 'ゲームに存在しない'
    end
    if not IsModelValid(hash) then
        return false, 'モデルとして無効'
    end

    RequestModel(hash)
    local timeout = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Wait(10)
    end

    if not HasModelLoaded(hash) then
        return false, '読み込めない'
    end

    -- 部品として使えるかは寸法で決まる。バウンディングボックスを見る
    local min, max = GetModelDimensions(hash)
    SetModelAsNoLongerNeeded(hash)

    return true, ('%.1f x %.1f x %.1f m'):format(max.x - min.x, max.y - min.y, max.z - min.z)
end

--- 候補を全部検証して結果を出す。
local function probeAll()
    print('[gain_build] 部品候補の検証を開始します')

    local ok, ng = 0, 0
    local usable = {}

    for _, part in ipairs(BuildConfig.Candidates) do
        local valid, detail = checkModel(part.model)

        if valid then
            ok = ok + 1
            usable[#usable + 1] = ('  { role = \'%s\', model = \'%s\' },  -- %s'):format(part.role, part.model, detail)
            print(('[gain_build] OK   %-28s %-8s %s'):format(part.model, part.role, detail))
        else
            ng = ng + 1
            print(('[gain_build] NG   %-28s %-8s %s'):format(part.model, part.role, detail))
        end
    end

    print(('[gain_build] 検証終了: 使える %d / 使えない %d'):format(ok, ng))
    print('[gain_build] --- 採用できる候補 ---')
    for _, line in ipairs(usable) do print(line) end
end

--- モデルを1つ読み込んでオブジェクトを出す。
local function place(model, x, y, z, heading)
    local hash = GetHashKey(model)
    RequestModel(hash)
    local timeout = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(10) end
    if not HasModelLoaded(hash) then return nil end

    local obj = CreateObject(hash, x, y, z, false, false, false)
    SetEntityHeading(obj, heading or 0.0)
    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, true, true)
    SetModelAsNoLongerNeeded(hash)

    spawned[#spawned + 1] = obj
    return obj
end

--- 指定モデルで四角い部屋を1つ組む。入り口として1マス空ける。
--- 実際に歩いて入れるか、隙間から抜けられないかを見るための検証。
local function buildTestRoom(wallModel)
    local ped = PlayerPedId()
    local origin = GetEntityCoords(ped)
    local g = BuildConfig.GridSize
    local w, d = BuildConfig.TestRoom.width, BuildConfig.TestRoom.depth

    -- 足元より少し前に建てる（プレイヤーが壁に埋まらないように）
    local ox = origin.x + 4.0
    local oy = origin.y
    local oz = origin.z - 1.0

    local count = 0

    for i = 0, w - 1 do
        for j = 0, d - 1 do
            local edge = (i == 0 or i == w - 1 or j == 0 or j == d - 1)
            if not edge then goto continue end

            -- 手前中央は入り口として空ける
            if j == 0 and i == math.floor(w / 2) then goto continue end

            local heading = (j == 0 or j == d - 1) and 0.0 or 90.0
            if place(wallModel, ox + i * g, oy + j * g, oz, heading) then
                count = count + 1
            end

            ::continue::
        end
    end

    print(('[gain_build] %s で %d 個の壁を配置しました'):format(wallModel, count))
    print('[gain_build] 中に入れるか、隙間から抜けられないかを確認してください')
    print('[gain_build] 消すときは /gbuild clear')
end

local function clearAll()
    for _, obj in ipairs(spawned) do
        if DoesEntityExist(obj) then DeleteObject(obj) end
    end
    spawned = {}
    print('[gain_build] 検証用オブジェクトを消しました')
end

RegisterCommand('gbuild', function(_, args)
    local sub = args[1]

    if sub == 'props' then
        probeAll()
    elseif sub == 'room' then
        local model = args[2]
        if not model then
            print('[gain_build] 使い方: /gbuild room <プロップ名>')
            print('[gain_build] 先に /gbuild props で使える名前を確認してください')
            return
        end
        buildTestRoom(model)
    elseif sub == 'clear' then
        clearAll()
    else
        print('[gain_build] /gbuild props           部品候補を検証する')
        print('[gain_build] /gbuild room <model>    そのプロップで部屋を1つ組む')
        print('[gain_build] /gbuild clear           検証用オブジェクトを消す')
    end
end, false)
