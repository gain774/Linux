-- 管理操作のサーバー側。権限判定はすべてここで行い、
-- クライアントから来た値（対象 ID・金額・理由）は必ず検証する。

local core = exports['gain_core']

local function can(src, action)
    local required = AdminConfig.Actions[action]
    if not required then return false end
    return core:HasPermission(src, required)
end

local function deny(src, action)
    core:Notify(src, _L('no_permission'), 'error')
    core:Log('cheat', '権限のない管理操作を試行', {
        player = GetPlayerName(src) or '?',
        id = src,
        action = action,
    })
end

local function licenseOf(src)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == 'license:' then return id end
    end
    return nil
end

--- 対象プレイヤーの source を検証して返す。無効なら nil。
local function resolveTarget(value)
    local target = tonumber(value)
    if not target then return nil end
    if GetPlayerName(target) == nil then return nil end
    return target
end

local function adminName(src)
    local player = core:GetPlayer(src)
    return player and player.name or (GetPlayerName(src) or 'console')
end

----------------------------------------------------------------------
-- プレイヤー一覧
----------------------------------------------------------------------

RegisterSafeEvent('gain_admin:requestPlayers', { rate = { max = 5, per = 2000 } }, function(src)
    if not can(src, 'players') then return deny(src, 'players') end

    local list = {}
    for _, player in ipairs(core:GetPlayers()) do
        list[#list + 1] = {
            id = player.source,
            name = player.name,
            citizenid = player.citizenid,
            permission = player.permission,
            job = player.job.name,
            cash = player.money.cash,
            bank = player.money.bank,
            ping = GetPlayerPing(player.source),
        }
    end

    table.sort(list, function(a, b) return a.id < b.id end)

    TriggerClientEvent('gain_admin:setPlayers', src, list, {
        self = src,
        actions = AdminConfig.Actions,
        durations = AdminConfig.BanDurations,
    })
end)

----------------------------------------------------------------------
-- 各操作
----------------------------------------------------------------------

local actions = {}

function actions.heal(src, target)
    TriggerClientEvent('gain_admin:heal', target, false)
    core:Notify(src, ('%s を回復しました。'):format(GetPlayerName(target)), 'success')
end

function actions.revive(src, target)
    TriggerClientEvent('gain_admin:heal', target, true)
    core:Notify(src, ('%s を蘇生しました。'):format(GetPlayerName(target)), 'success')
end

function actions.tpto(src, target)
    local coords = GetEntityCoords(GetPlayerPed(target))
    TriggerClientEvent('gain_admin:teleport', src, {
        x = coords.x, y = coords.y, z = coords.z,
    })
end

function actions.bring(src, target)
    local coords = GetEntityCoords(GetPlayerPed(src))
    TriggerClientEvent('gain_admin:teleport', target, {
        x = coords.x, y = coords.y, z = coords.z,
    })
    core:Notify(target, '管理者に呼び寄せられました。', 'warn')
end

function actions.spectate(src, target)
    TriggerClientEvent('gain_admin:spectate', src, target)
end

function actions.kick(src, target, payload)
    local reason = type(payload.reason) == 'string' and payload.reason:sub(1, 128) or '理由なし'

    core:Log('admin', 'キック', {
        by = adminName(src),
        target = GetPlayerName(target),
        reason = reason,
    })
    DropPlayer(target, ('キックされました。理由: %s'):format(reason))
    core:Notify(src, ('%s をキックしました。'):format(GetPlayerName(target)), 'success')
end

function actions.ban(src, target, payload)
    local license = licenseOf(target)
    if not license then
        core:Notify(src, '対象の license を取得できませんでした。', 'error')
        return
    end

    local reason = type(payload.reason) == 'string' and payload.reason:sub(1, 200) or '理由なし'
    local minutes = math.max(0, math.floor(tonumber(payload.minutes) or 0))
    local name = GetPlayerName(target)

    local expires = nil
    if minutes > 0 then
        expires = os.date('!%Y-%m-%d %H:%M:%S', os.time() + minutes * 60)
    end

    MySQL.insert.await([[
        INSERT INTO gain_bans (license, name, reason, banned_by, expires_at)
        VALUES (?, ?, ?, ?, ?)
    ]], { license, name, reason, adminName(src), expires })

    core:Log('admin', 'BAN', {
        by = adminName(src),
        target = name,
        license = license,
        reason = reason,
        minutes = minutes > 0 and minutes or '無期限',
    })

    DropPlayer(target, _L('banned', reason))
    core:Notify(src, ('%s を BAN しました。'):format(name), 'success')
end

function actions.givemoney(src, target, payload)
    local account = payload.account == 'bank' and 'bank' or 'cash'
    local amount = math.floor(tonumber(payload.amount) or 0)

    if amount <= 0 or amount > AdminConfig.MaxGiveMoney then
        core:Notify(src, _L('invalid_amount'), 'error')
        return
    end

    if core:AddMoney(target, account, amount, ('admin:%s'):format(adminName(src))) then
        core:Log('admin', '所持金を付与', {
            by = adminName(src),
            target = GetPlayerName(target),
            account = account,
            amount = amount,
        })
        core:Notify(src, ('%s に $%d を付与しました。'):format(GetPlayerName(target), amount), 'success')
        core:Notify(target, _L('money_received', amount), 'success')
    else
        core:Notify(src, _L('invalid_amount'), 'error')
    end
end

function actions.setperm(src, target, payload)
    local level = payload.level

    if Config.Permissions[level] == nil then
        core:Notify(src, 'その権限は存在しません。', 'error')
        return
    end

    -- 自分より上の権限は付与できない
    local me = core:GetPlayer(src)
    if not me or (Config.Permissions[level] > Config.Permissions[me.permission]) then
        return deny(src, 'setperm')
    end

    if core:SetPermission(target, level) then
        core:Notify(src, _L('permission_changed', GetPlayerName(target), level), 'success')
    else
        core:Notify(src, _L('player_not_found'), 'error')
    end
end

RegisterSafeEvent('gain_admin:action', { rate = { max = 10, per = 3000 } }, function(src, name, targetId, payload)
    payload = type(payload) == 'table' and payload or {}

    local handler = actions[name]
    if not handler then return end
    if not can(src, name) then return deny(src, name) end

    local target = resolveTarget(targetId)
    if not target then
        core:Notify(src, _L('player_not_found'), 'error')
        return
    end

    -- 自分と同格以上の相手には強制系の操作を行えない（owner 同士も含む）
    local enforcing = (name == 'kick' or name == 'ban' or name == 'setperm')
    if enforcing and target ~= src then
        local me, them = core:GetPlayer(src), core:GetPlayer(target)
        if me and them and Config.Permissions[them.permission] >= Config.Permissions[me.permission] then
            core:Notify(src, '自分と同じかそれ以上の権限を持つ相手には実行できません。', 'error')
            return
        end
    end

    handler(src, target, payload)
end)

-- 車のスポーンは対象が自分のみ
RegisterSafeEvent('gain_admin:spawnVehicle', { rate = { max = 5, per = 5000 } }, function(src, model)
    if not can(src, 'vehicle') then return deny(src, 'vehicle') end
    if type(model) ~= 'string' or #model == 0 or #model > 32 or model:find('[^%w_]') then
        core:Notify(src, '車両モデル名が正しくありません。', 'error')
        return
    end

    TriggerClientEvent('gain_admin:spawnVehicle', src, model)
    core:Log('admin', '車両をスポーン', { by = adminName(src), model = model })
end)

----------------------------------------------------------------------
-- コンソール / チャットコマンド（メニューと同じ判定を通す）
----------------------------------------------------------------------

local function commandTarget(src, args, index)
    local target = resolveTarget(args[index])
    if not target then
        if src > 0 then core:Notify(src, _L('player_not_found'), 'error') end
        return nil
    end
    return target
end

RegisterCommand('gkick', function(src, args)
    if src > 0 and not can(src, 'kick') then return deny(src, 'kick') end
    local target = commandTarget(src, args, 1)
    if not target then return end
    actions.kick(src, target, { reason = table.concat(args, ' ', 2) })
end, false)

RegisterCommand('gban', function(src, args)
    if src > 0 and not can(src, 'ban') then return deny(src, 'ban') end
    local target = commandTarget(src, args, 1)
    if not target then return end
    actions.ban(src, target, { minutes = args[2], reason = table.concat(args, ' ', 3) })
end, false)

RegisterCommand('gunban', function(src, args)
    if src > 0 and not can(src, 'unban') then return deny(src, 'unban') end

    local license = args[1]
    if type(license) ~= 'string' or license:sub(1, 8) ~= 'license:' then
        print('使い方: gunban license:xxxxxxxx')
        return
    end

    local affected = MySQL.update.await('DELETE FROM gain_bans WHERE license = ?', { license })
    core:Log('admin', 'BAN を解除', { by = adminName(src), license = license, rows = affected or 0 })
    if src > 0 then
        core:Notify(src, ('BAN を %d 件解除しました。'):format(affected or 0), 'success')
    end
end, false)

RegisterCommand('ggivemoney', function(src, args)
    if src > 0 and not can(src, 'givemoney') then return deny(src, 'givemoney') end
    local target = commandTarget(src, args, 1)
    if not target then return end
    actions.givemoney(src, target, { account = args[2], amount = args[3] })
end, false)

RegisterCommand('gsetperm', function(src, args)
    if src > 0 and not can(src, 'setperm') then return deny(src, 'setperm') end
    local target = commandTarget(src, args, 1)
    if not target then return end

    -- コンソール（src = 0）からは権限比較を行えないので直接設定する
    if src == 0 then
        core:SetPermission(target, args[2])
        return
    end
    actions.setperm(src, target, { level = args[2] })
end, false)

-- 自分の license を確認する（Config.Owners に書くため）
RegisterCommand('gwhoami', function(src)
    if src == 0 then return end
    local license = licenseOf(src)
    print(('[gain] %s の license: %s'):format(GetPlayerName(src), license or '取得失敗'))
    core:Notify(src, ('license はサーバーコンソールに出力しました。'), 'info')
end, false)
