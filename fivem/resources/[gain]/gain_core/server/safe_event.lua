-- net イベントの共通ラッパ。
-- クライアントから直接呼べるイベントは必ずこれを通し、
-- 送信元の検証とレート制限を掛けてから本体を実行する。
--
-- 他リソースからは fxmanifest でこのファイルを読み込んで使う:
--   server_scripts { '@gain_core/shared/config.lua', '@gain_core/server/safe_event.lua', ... }

local buckets = {}

-- トークンバケット。固定ウィンドウだと窓の境界を跨いで
-- per ミリ秒の間に最大 2*max 回通ってしまうため、こちらを使う。
local function allowed(src, name, rate)
    local now = GetGameTimer()
    local perPlayer = buckets[src]

    if not perPlayer then
        perPlayer = {}
        buckets[src] = perPlayer
    end

    local bucket = perPlayer[name]
    if not bucket then
        bucket = { tokens = rate.max, at = now }
        perPlayer[name] = bucket
    end

    -- 経過時間ぶんだけ補充する。上限は max
    local refill = (now - bucket.at) * rate.max / rate.per
    bucket.tokens = math.min(rate.max, bucket.tokens + refill)
    bucket.at = now

    if bucket.tokens < 1 then return false end

    bucket.tokens = bucket.tokens - 1
    return true
end

-- ログは export 経由で呼ぶ。
-- このファイルは他リソースへ個別にロードされるため、そこからは
-- gain_core のグローバル（GainLog）が見えない。以前は `if GainLog then`
-- で握り潰していたので、gain_core 以外ではレート制限抵触も権限違反も
-- 一切ログに残っていなかった。
local function logCheat(message, meta)
    pcall(function()
        exports['gain_core']:Log('cheat', message, meta)
    end)
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
            logCheat('イベントのレート制限に抵触', {
                event = name,
                player = GetPlayerName(src) or '?',
                id = src,
            })
            return
        end

        if opts.permission then
            local ok = exports['gain_core']:HasPermission(src, opts.permission)
            if not ok then
                logCheat('権限のないイベント呼び出し', {
                    event = name,
                    required = opts.permission,
                    player = GetPlayerName(src) or '?',
                    id = src,
                })
                -- 黙って落とすと使う側が原因に辿り着けない
                pcall(function()
                    exports['gain_core']:Notify(src, _L('no_permission'), 'error')
                end)
                return
            end
        end

        handler(src, ...)
    end)
end

AddEventHandler('playerDropped', function()
    buckets[source] = nil
end)
