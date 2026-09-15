--[[
  「1日あたりのプレイ時間」を実測する。§6.6（収集効率アンカー）は日別
  （dyn_player_playtime）、§7 の basis='playtime'（目標成長曲線）は累計
  （dyn_player_progress.playtime_hours）を見るので、両方を同じティックで
  積み上げる。

  厳密な接続・切断イベントでの計測は、クラッシュやリスタートで片方だけ
  記録されると狂うので、一定間隔でその時点の接続者に加算していく方式にする
  （多少の誤差は出るが、事故で大きく狂わない）。

  このファイルはフレームワークを選ばない。「今サーバーに何人繋がっているか」
  と「その人の VORP キャラ識別子」だけを見る。識別子の取得は
  dyn_economy_bridge に用意されている解決関数を使う（無ければこのファイルは
  何もしない＝ §6.6 は自然に据え置きになる）。
]]

local function tickMinutes()
    return (Config.Calibration and Config.Calibration.playtimeTickMinutes) or 5
end

--- 接続中プレイヤーの VORP 識別子を集める。取れない環境では空を返す
local function connectedIdentifiers()
    local ids = {}
    if GetResourceState('dyn_economy_bridge') ~= 'started' then return ids end
    local ok, resolver = pcall(function() return exports.dyn_economy_bridge.GetIdentifier end)
    if not ok or not resolver then return ids end

    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local okId, identifier = pcall(function() return exports.dyn_economy_bridge:GetIdentifier(src) end)
        if okId and identifier then ids[#ids + 1] = identifier end
    end
    return ids
end

--- §6.6（収集効率アンカー）と §7 の basis='playtime'（目標成長曲線）の
--- どちらかが要る間だけ計測する。どちらも要らなければ何もしない
local function needed()
    local yieldOn = Config.Calibration and Config.Calibration.enabled and Config.Calibration.yield
    local progressionOn = Config.Progression and Config.Progression.enabled and Config.Progression.basis == 'playtime'
    return yieldOn or progressionOn
end

local function tick()
    if not needed() then return end
    if not DynDb.isReady() then return end

    local hours = tickMinutes() / 60
    local yieldOn = Config.Calibration and Config.Calibration.enabled and Config.Calibration.yield
    local progressionOn = Config.Progression and Config.Progression.enabled and Config.Progression.basis == 'playtime'

    for _, identifier in ipairs(connectedIdentifiers()) do
        if yieldOn then
            DynDb.execute([[
                INSERT INTO dyn_player_playtime (identifier, day, hours)
                VALUES (?, CURDATE(), ?)
                ON DUPLICATE KEY UPDATE hours = hours + VALUES(hours)
            ]], { identifier, hours })
        end
        if progressionOn then
            -- dyn_player_progress の行はまだ無いかもしれない（NPC取引がまだ無い新規プレイヤー）ので
            -- INSERT ... ON DUPLICATE KEY UPDATE で無ければ作る
            DynDb.execute([[
                INSERT INTO dyn_player_progress (identifier, first_seen, last_seen, playtime_hours, updated_at)
                VALUES (?, NOW(), NOW(), ?, NOW())
                ON DUPLICATE KEY UPDATE
                    last_seen      = NOW(),
                    playtime_hours = playtime_hours + VALUES(playtime_hours),
                    updated_at     = NOW()
            ]], { identifier, hours })
        end
    end
end

CreateThread(function()
    while true do
        Wait(tickMinutes() * 60 * 1000)
        tick()
    end
end)
