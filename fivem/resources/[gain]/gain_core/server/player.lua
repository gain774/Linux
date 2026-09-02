-- プレイヤー（キャラクター）の読み込み・保持・保存。

local players = {}

--- 接続中プレイヤーの内部オブジェクトを取得する。
---@param src number
---@return table|nil
function GetGainPlayer(src)
    return players[tonumber(src)]
end

--- 接続中の全プレイヤー。
---@return table
function GetGainPlayers()
    return players
end

local function getLicense(src)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == 'license:' then
            return id
        end
    end
    return nil
end

local function generateCitizenId()
    local chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    for _ = 1, 20 do
        local id = {}
        for _ = 1, 8 do
            local i = math.random(#chars)
            id[#id + 1] = chars:sub(i, i)
        end
        id = table.concat(id)

        local exists = MySQL.scalar.await('SELECT 1 FROM gain_characters WHERE citizenid = ?', { id })
        if not exists then return id end
    end

    -- 20回引いて衝突し続けることは実質起きないが、念のため時刻で埋める
    return ('C%s'):format(os.time())
end

--- 有効な BAN 情報を返す。無ければ nil。
local function getActiveBan(license)
    return MySQL.single.await([[
        SELECT reason, expires_at FROM gain_bans
        WHERE license = ? AND (expires_at IS NULL OR expires_at > NOW())
        ORDER BY id DESC LIMIT 1
    ]], { license })
end

local function ensureUser(license, name)
    local user = MySQL.single.await('SELECT license, permission FROM gain_users WHERE license = ?', { license })

    if not user then
        local permission = 'user'
        for _, owner in ipairs(Config.Owners) do
            if owner == license then permission = 'owner' end
        end

        MySQL.insert.await('INSERT INTO gain_users (license, name, permission) VALUES (?, ?, ?)', {
            license, name, permission,
        })
        return { license = license, permission = permission }
    end

    -- Config.Owners は毎回反映する（鍵を失った時の復旧手段）
    for _, owner in ipairs(Config.Owners) do
        if owner == license and user.permission ~= 'owner' then
            MySQL.update.await('UPDATE gain_users SET permission = ? WHERE license = ?', { 'owner', license })
            user.permission = 'owner'
        end
    end

    MySQL.update('UPDATE gain_users SET name = ? WHERE license = ?', { name, license })
    return user
end

local function createCharacter(license, name)
    local citizenid = generateCitizenId()

    MySQL.insert.await([[
        INSERT INTO gain_characters (citizenid, license, firstname, lastname, cash, bank, position)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        citizenid, license, name, '', Config.StartingCash, Config.StartingBank,
        json.encode(Config.DefaultSpawn),
    })

    return MySQL.single.await('SELECT * FROM gain_characters WHERE citizenid = ?', { citizenid })
end

--- 内部プレイヤーオブジェクトを組み立てる。
local function buildPlayer(src, license, user, row)
    local position = row.position and json.decode(row.position) or nil
    local metadata = row.metadata and json.decode(row.metadata) or nil

    local self = {
        source = src,
        license = license,
        citizenid = row.citizenid,
        name = (row.lastname ~= '' and (row.firstname .. ' ' .. row.lastname)) or row.firstname,
        permission = user.permission or 'user',
        money = {
            cash = row.cash or 0,
            bank = row.bank or 0,
        },
        job = {
            name = row.job or 'unemployed',
            grade = row.job_grade or 0,
            duty = (row.job_duty or 0) == 1,
        },
        position = position or Config.DefaultSpawn,
        metadata = metadata or {},
    }

    --- クライアントへ渡す公開データ（権限や license は渡さない情報を含めて最小限に）。
    function self.public()
        return {
            citizenid = self.citizenid,
            name = self.name,
            permission = self.permission,
            money = self.money,
            job = self.job,
        }
    end

    function self.sync()
        TriggerClientEvent('gain_core:setPlayerData', self.source, self.public())
    end

    function self.save()
        MySQL.update([[
            UPDATE gain_characters
            SET cash = ?, bank = ?, job = ?, job_grade = ?, job_duty = ?, position = ?, metadata = ?
            WHERE citizenid = ?
        ]], {
            self.money.cash,
            self.money.bank,
            self.job.name,
            self.job.grade,
            self.job.duty and 1 or 0,
            json.encode(self.position),
            json.encode(self.metadata),
            self.citizenid,
        })
    end

    return self
end

-- 接続時: BAN 判定だけを行う。キャラの読み込みはクライアントの準備完了後。
AddEventHandler('playerConnecting', function(name, _, deferrals)
    local src = source
    deferrals.defer()
    Wait(0)

    local license = getLicense(src)
    if not license then
        deferrals.done('license 識別子を取得できませんでした。FiveM を再起動してください。')
        return
    end

    deferrals.update(_L('loading_character'))

    local ban = getActiveBan(license)
    if ban then
        deferrals.done(_L('banned', ban.reason or '-'))
        GainLog.write('admin', 'BAN 中のプレイヤーが接続を試行', { name = name, license = license })
        return
    end

    ensureUser(license, name)
    deferrals.done()
end)

-- クライアントの準備完了後にキャラクターを読み込む。
RegisterSafeEvent('gain_core:requestLoad', { rate = { max = 3, per = 10000 } }, function(src)
    if players[src] then
        players[src].sync()
        return
    end

    local license = getLicense(src)
    if not license then
        DropPlayer(src, 'license 識別子を取得できませんでした。')
        return
    end

    local user = ensureUser(license, GetPlayerName(src))
    local row = MySQL.single.await('SELECT * FROM gain_characters WHERE license = ? LIMIT 1', { license })

    local isNew = false
    if not row then
        row = createCharacter(license, GetPlayerName(src))
        isNew = true
    end

    if not row then
        DropPlayer(src, _L('db_error'))
        return
    end

    local player = buildPlayer(src, license, user, row)
    players[src] = player

    TriggerClientEvent('gain_core:spawn', src, player.position)
    player.sync()

    TriggerEvent('gain_core:playerLoaded', src, player.citizenid)
    TriggerClientEvent('gain_core:notify', src,
        isNew and _L('character_created', player.name) or _L('welcome_back', player.name), 'info')

    GainLog.write('info', isNew and 'キャラクターを新規作成' or 'プレイヤーが参加', {
        player = player.name,
        citizenid = player.citizenid,
        id = src,
    })
end)

-- 位置情報の定期送信（保存用）。値は保存にしか使わないので改ざんされても実害は無いが、
-- 数値であることだけ検証する。
RegisterSafeEvent('gain_core:updatePosition', { rate = { max = 2, per = 5000 } }, function(src, pos)
    local player = players[src]
    if not player or type(pos) ~= 'table' then return end

    local x, y, z, h = tonumber(pos.x), tonumber(pos.y), tonumber(pos.z), tonumber(pos.heading)
    if not x or not y or not z then return end

    player.position = { x = x, y = y, z = z, heading = h or 0.0 }
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    local player = players[src]
    if not player then return end

    player.save()
    players[src] = nil

    TriggerEvent('gain_core:playerUnloaded', src, player.citizenid)
    GainLog.write('info', 'プレイヤーが退出', {
        player = player.name,
        citizenid = player.citizenid,
        reason = reason,
    })
end)

-- 自動保存
CreateThread(function()
    while true do
        Wait(Config.AutosaveInterval)
        for _, player in pairs(players) do
            player.save()
        end
    end
end)

-- リソース停止・サーバー再起動時の保存
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    for _, player in pairs(players) do
        player.save()
    end
    GainLog.write('info', 'gain_core 停止に伴い全プレイヤーを保存')
end)
