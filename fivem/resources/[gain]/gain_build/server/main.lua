-- 図面の保存と読み出し。
--
-- クライアントから来る図面データは信用しない。壁の本数・座標の範囲・
-- 開口の位置をすべてサーバー側で検証してから保存する。

local core = exports['gain_core']

local MAX_WALLS = 400
local MAX_OPENINGS = 200
local MAX_ROOMS = 60

--- 数値として妥当か。NaN と範囲外を弾く。
local function num(v, limit)
    if type(v) ~= 'number' then return nil end
    if v ~= v then return nil end                     -- NaN
    if v < -limit or v > limit then return nil end
    return v
end

--- 図面データを検証して、通ったものだけを返す。
local function sanitize(plan)
    if type(plan) ~= 'table' then return nil, '形式が不正' end

    local E = BuildConfig.MaxExtent
    local out = { walls = {}, openings = {}, rooms = {} }

    if type(plan.walls) ~= 'table' or #plan.walls == 0 then
        return nil, '壁がありません'
    end
    if #plan.walls > MAX_WALLS then return nil, '壁が多すぎます' end

    for _, w in ipairs(plan.walls) do
        local x1, y1 = num(w[1], E), num(w[2], E)
        local x2, y2 = num(w[3], E), num(w[4], E)
        if not (x1 and y1 and x2 and y2) then return nil, '壁の座標が不正' end
        if x1 == x2 and y1 == y2 then return nil, '長さ 0 の壁があります' end
        out.walls[#out.walls + 1] = { x1, y1, x2, y2 }
    end

    if type(plan.openings) == 'table' then
        if #plan.openings > MAX_OPENINGS then return nil, '開口が多すぎます' end
        for _, o in ipairs(plan.openings) do
            local wall = num(o.wall, MAX_WALLS)
            local at = num(o.at, E * 2)
            local width = num(o.width, 6.0)
            if not (wall and at and width) then return nil, '開口が不正' end
            wall = math.floor(wall)
            if wall < 1 or wall > #out.walls then return nil, '開口の壁番号が不正' end
            if width <= 0 or at < 0 then return nil, '開口の寸法が不正' end

            local w = out.walls[wall]
            local len = math.sqrt((w[3] - w[1]) ^ 2 + (w[4] - w[2]) ^ 2)
            if at - width / 2 < -0.01 or at + width / 2 > len + 0.01 then
                return nil, '開口が壁からはみ出しています'
            end

            out.openings[#out.openings + 1] = {
                wall = wall, at = at, width = width,
                kind = (o.kind == 'window') and 'window' or 'door',
            }
        end
    end

    if type(plan.rooms) == 'table' then
        if #plan.rooms > MAX_ROOMS then return nil, '部屋が多すぎます' end
        for _, r in ipairs(plan.rooms) do
            local name = type(r.name) == 'string' and r.name:sub(1, 24) or '室'
            local poly = {}
            if type(r.poly) ~= 'table' or #r.poly < 3 then return nil, '部屋の形が不正' end
            for _, p in ipairs(r.poly) do
                local x, y = num(p[1], E), num(p[2], E)
                if not (x and y) then return nil, '部屋の座標が不正' end
                poly[#poly + 1] = { x, y }
            end
            out.rooms[#out.rooms + 1] = { name = name, poly = poly }
        end
    end

    return out
end

--- 面積（多角形の符号付き面積の絶対値）。
local function areaOf(rooms)
    local total = 0.0
    for _, r in ipairs(rooms) do
        local s, n = 0.0, #r.poly
        for i = 1, n do
            local a, b = r.poly[i], r.poly[i % n + 1]
            s = s + (a[1] * b[2] - b[1] * a[2])
        end
        total = total + math.abs(s) / 2
    end
    return total
end

--- 壁の長さを部品に分解したときの個数。
local function propCount(plan)
    local n = 2                                  -- 床・屋根
    for _, w in ipairs(plan.walls) do
        local len = math.sqrt((w[3] - w[1]) ^ 2 + (w[4] - w[2]) ^ 2)
        for _, size in ipairs(BuildConfig.WallLengths) do
            while len >= size - 0.001 do
                len = len - size
                n = n + 1
            end
        end
    end
    return n
end

RegisterSafeEvent('gain_build:save', { rate = { max = 4, per = 10000 } }, function(src, payload)
    local player = core:GetPlayer(src)
    if not player then return end

    if type(payload) ~= 'table' then return end

    local plan, err = sanitize(payload.plan)
    if not plan then
        core:Notify(src, ('図面を保存できません: %s'):format(err or '不明'), 'error')
        return
    end

    local props = propCount(plan)
    if props > BuildConfig.MaxProps then
        core:Notify(src, ('部品が %d 個で上限 %d を超えています'):format(props, BuildConfig.MaxProps), 'error')
        return
    end

    local name = type(payload.name) == 'string' and payload.name:sub(1, 64) or '無題'
    local system = type(payload.system) == 'string' and payload.system:sub(1, 16) or '木造軸組'
    local area = areaOf(plan.rooms)
    local data = json.encode(plan)

    local id = tonumber(payload.id)
    if id then
        local owned = MySQL.scalar.await(
            'SELECT id FROM gain_blueprints WHERE id = ? AND citizenid = ?', { id, player.citizenid })
        if not owned then
            core:Notify(src, '他人の図面は更新できません', 'error')
            return
        end
        MySQL.update.await([[
            UPDATE gain_blueprints SET name = ?, system = ?, data = ?, area = ?, props = ?
            WHERE id = ? AND citizenid = ?
        ]], { name, system, data, area, props, id, player.citizenid })
    else
        local n = MySQL.scalar.await(
            'SELECT COUNT(*) FROM gain_blueprints WHERE citizenid = ?', { player.citizenid }) or 0
        if n >= BuildConfig.MaxBlueprints then
            core:Notify(src, ('図面は %d 枚までです'):format(BuildConfig.MaxBlueprints), 'error')
            return
        end
        id = MySQL.insert.await([[
            INSERT INTO gain_blueprints (citizenid, name, system, data, area, props)
            VALUES (?, ?, ?, ?, ?, ?)
        ]], { player.citizenid, name, system, data, area, props })
    end

    core:Log('build', '図面を保存', {
        player = player.name, citizenid = player.citizenid,
        name = name, area = ('%.1f'):format(area), props = props,
    })
    core:Notify(src, ('「%s」を保存しました（%.1f m² / 部品 %d 個）'):format(name, area, props), 'success')
    TriggerClientEvent('gain_build:saved', src, id, name)
end)

RegisterSafeEvent('gain_build:list', { rate = { max = 6, per = 10000 } }, function(src)
    local player = core:GetPlayer(src)
    if not player then return end

    local rows = MySQL.query.await([[
        SELECT id, name, system, area, props, updated_at
        FROM gain_blueprints WHERE citizenid = ? ORDER BY id DESC
    ]], { player.citizenid }) or {}

    TriggerClientEvent('gain_build:blueprints', src, rows)
end)

RegisterSafeEvent('gain_build:load', { rate = { max = 6, per = 10000 } }, function(src, id)
    local player = core:GetPlayer(src)
    if not player then return end
    id = tonumber(id)
    if not id then return end

    local row = MySQL.single.await([[
        SELECT id, name, system, data FROM gain_blueprints WHERE id = ? AND citizenid = ?
    ]], { id, player.citizenid })
    if not row then
        core:Notify(src, '図面が見つかりません', 'error')
        return
    end

    TriggerClientEvent('gain_build:loaded', src, row.id, row.name, row.system, row.data)
end)

RegisterSafeEvent('gain_build:delete', { rate = { max = 4, per = 10000 } }, function(src, id)
    local player = core:GetPlayer(src)
    if not player then return end
    id = tonumber(id)
    if not id then return end

    MySQL.update.await('DELETE FROM gain_blueprints WHERE id = ? AND citizenid = ?',
        { id, player.citizenid })
    TriggerClientEvent('gain_build:deleted', src, id)
end)
