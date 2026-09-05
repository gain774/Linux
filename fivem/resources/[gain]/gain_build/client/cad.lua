-- CAD の開閉と、描いた図面を現地に立ち上げる部分。
--
-- GTA は実行時にメッシュを作れないので、図面から直接モデルは生まれない。
-- まず「地縄張り」として地面に線を出す。工程1そのものなので、
-- 部品が揃う前でもこれ自体が作業として成立する。

local open = false
local site = nil          -- 立ち上げ中の図面 { plan, x, y, z, heading }

local function setOpen(v)
    open = v
    SetNuiFocus(v, v)
    SendNUIMessage({ action = v and 'open' or 'close' })
end

RegisterCommand('cad', function()
    if open then return end
    setOpen(true)
end, false)

RegisterNUICallback('close', function(_, cb)
    setOpen(false)
    cb({})
end)

RegisterNUICallback('save', function(data, cb)
    TriggerServerEvent('gain_build:save', data)
    cb({})
end)

RegisterNUICallback('list', function(_, cb)
    TriggerServerEvent('gain_build:list')
    cb({})
end)

RegisterNUICallback('load', function(data, cb)
    TriggerServerEvent('gain_build:load', data.id)
    cb({})
end)

RegisterNUICallback('delete', function(data, cb)
    TriggerServerEvent('gain_build:delete', data.id)
    cb({})
end)

RegisterNetEvent('gain_build:blueprints', function(rows)
    SendNUIMessage({ action = 'blueprints', rows = rows })
end)

RegisterNetEvent('gain_build:loaded', function(id, name, system, data)
    SendNUIMessage({ action = 'loaded', id = id, name = name, system = system, data = data })
    lastPlan = { id = id, name = name, data = data }
end)

RegisterNetEvent('gain_build:saved', function(id, name)
    SendNUIMessage({ action = 'saved', id = id })
    lastPlan = lastPlan or {}
    lastPlan.id, lastPlan.name = id, name
end)

RegisterNetEvent('gain_build:deleted', function()
    TriggerServerEvent('gain_build:list')
end)

-- ------------------------------------------------------------------ 地縄張り

--- 図面座標を現地のワールド座標へ。site の位置と向きで回す。
local function toWorld(x, y)
    local rad = math.rad(site.heading)
    local c, s = math.cos(rad), math.sin(rad)
    return site.x + (x * c - y * s), site.y + (x * s + y * c)
end

--- 地面の高さを拾う。拾えなければ設置時の高さのまま。
local function groundAt(x, y)
    local ok, z = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, site.z + 5.0, false)
    return ok and z or site.z
end

RegisterCommand('stake', function()
    if not lastPlan or not lastPlan.data then
        print('[gain_build] 先に図面を読み込んでください（/cad → 図面一覧）')
        return
    end

    local plan = json.decode(lastPlan.data)
    if not plan or not plan.walls then
        print('[gain_build] 図面を読めませんでした')
        return
    end

    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    site = { plan = plan, x = c.x, y = c.y, z = c.z, heading = GetEntityHeading(ped) }

    print(('[gain_build] 「%s」を地縄張りしました。壁 %d 本')
        :format(lastPlan.name or '無題', #plan.walls))
    print('[gain_build] 向きを変えるなら別の場所で撃ち直す。消すには /unstake')
end, false)

RegisterCommand('unstake', function()
    site = nil
    print('[gain_build] 地縄を消しました')
end, false)

-- 描画。地縄は常時ループが要るが、site が無い間は回さない
CreateThread(function()
    while true do
        if not site then
            Wait(500)
        else
            Wait(0)
            local col = BuildConfig.StakeColor
            local plan = site.plan

            for _, w in ipairs(plan.walls) do
                local x1, y1 = toWorld(w[1], w[2])
                local x2, y2 = toWorld(w[3], w[4])
                local z1, z2 = groundAt(x1, y1) + 0.05, groundAt(x2, y2) + 0.05

                -- 芯線
                DrawLine(x1, y1, z1, x2, y2, z2, col[1], col[2], col[3], col[4])
                -- 壁の高さを示す立ち上がり（要所だけ）
                DrawLine(x1, y1, z1, x1, y1, z1 + BuildConfig.WallHeight,
                         col[1], col[2], col[3], 90)
            end

            -- 開口は色を変えて示す
            for _, o in ipairs(plan.openings or {}) do
                local w = plan.walls[o.wall]
                if w then
                    local dx, dy = w[3] - w[1], w[4] - w[2]
                    local len = math.sqrt(dx * dx + dy * dy)
                    if len > 0 then
                        local ux, uy = dx / len, dy / len
                        local h = o.width / 2
                        local ax, ay = toWorld(w[1] + ux * (o.at - h), w[2] + uy * (o.at - h))
                        local bx, by = toWorld(w[1] + ux * (o.at + h), w[2] + uy * (o.at + h))
                        local az, bz = groundAt(ax, ay) + 0.07, groundAt(bx, by) + 0.07
                        if o.kind == 'door' then
                            DrawLine(ax, ay, az, bx, by, bz, 92, 192, 138, 255)
                        else
                            DrawLine(ax, ay, az, bx, by, bz, 111, 168, 216, 255)
                        end
                    end
                end
            end

            -- 室名
            for _, r in ipairs(plan.rooms or {}) do
                local sx, sy, n = 0, 0, #r.poly
                for _, p in ipairs(r.poly) do sx = sx + p[1]; sy = sy + p[2] end
                local wx, wy = toWorld(sx / n, sy / n)
                local wz = groundAt(wx, wy) + 1.0
                SetDrawOrigin(wx, wy, wz, 0)
                SetTextScale(0.32, 0.32)
                SetTextFont(4)
                SetTextColour(255, 255, 255, 200)
                SetTextCentre(true)
                BeginTextCommandDisplayText('STRING')
                AddTextComponentSubstringPlayerName(r.name)
                EndTextCommandDisplayText(0.0, 0.0)
                ClearDrawOrigin()
            end
        end
    end
end)
