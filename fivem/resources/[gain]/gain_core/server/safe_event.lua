-- net イベントの共通ラッパ。
-- クライアントから直接呼べるイベントは必ずこれを通し、
-- 送信元の検証とレート制限を掛けてから本体を実行する。
--
-- 他リソースからは fxmanifest でこのファイルを読み込んで使う:
--   server_scripts { '@gain_core/shared/config.lua', '@gain_core/server/safe_event.lua', ... }

local buckets = {}

local function allowed(src, name, rate)
    local now = GetGameTimer()
    local perPlayer = buckets[src]

    if not perPlayer then
        perPlayer = {}
        buckets[src] = perPlayer
    end

    local bucket = perPlayer[name]
    if not bucket or now - bucket.since >= rate.per then
        perPlayer[name] = { since = now, count = 1 }
        return true
    end

    bucket.count = bucket.count + 1
    return bucket.count <= rate.max
end

--- 検証付きで net イベントを登録する。
---@param name string イベント名
---@param opts table|nil { rate = { max = number, per = number }, permission = string|nil }
---@param handler fun(src: number, ...): any 第1引数に送信元 source が入る
function RegisterSafeEvent(name, opts, handler)
    opts = opts or {}
    local rate = opts.rate or Config.EventRateLimit

    RegisterNetEvent(name, function(...)
        local src = source

        -- source が 0 / nil のものはサーバー内部からの発火。クライアント経路では起き得ない
        if not src or src <= 0 then return end

        if not allowed(src, name, rate) then
            if GainLog then
                GainLog.write('cheat', 'イベントのレート制限に抵触', {
                    event = name,
                    player = GetPlayerName(src) or '?',
                    id = src,
                })
            end
            return
        end

        if opts.permission then
            local ok = exports['gain_core']:HasPermission(src, opts.permission)
            if not ok then
                if GainLog then
                    GainLog.write('cheat', '権限のないイベント呼び出し', {
                        event = name,
                        required = opts.permission,
                        player = GetPlayerName(src) or '?',
                        id = src,
                    })
                end
                return
            end
        end

        handler(src, ...)
    end)
end

AddEventHandler('playerDropped', function()
    buckets[source] = nil
end)
