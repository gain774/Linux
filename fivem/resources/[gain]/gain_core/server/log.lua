-- 全リソース共通のログ出力。
-- 呼び出し: exports['gain_core']:Log('admin', 'kick', { by = ..., target = ... })

GainLog = {}

local COLORS = {
    info    = 3447003,
    admin   = 15844367,
    money   = 3066993,
    cheat   = 15158332,
    error   = 10038562,
}

local function toDiscord(category, message, meta)
    local url = Config.Log.discordWebhook
    if not url or url == '' then return end

    local fields = {}
    if type(meta) == 'table' then
        for k, v in pairs(meta) do
            fields[#fields + 1] = {
                name = tostring(k),
                value = ('```%s```'):format(tostring(v)),
                inline = true,
            }
        end
    end

    local payload = {
        username = 'gain_core',
        embeds = { {
            title = ('[%s]'):format(category),
            description = message,
            color = COLORS[category] or COLORS.info,
            fields = fields,
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }

    PerformHttpRequest(url, function() end, 'POST', json.encode(payload), {
        ['Content-Type'] = 'application/json',
    })
end

local function toDatabase(category, message, meta)
    if not Config.Log.database then return end

    MySQL.insert('INSERT INTO gain_logs (category, message, meta) VALUES (?, ?, ?)', {
        category,
        message,
        json.encode(meta or {}),
    })
end

--- ログを1件記録する。
---@param category string 'info' | 'admin' | 'money' | 'cheat' | 'error'
---@param message string
---@param meta table|nil 付随情報（プレイヤー名、金額など）
function GainLog.write(category, message, meta)
    category = category or 'info'

    if Config.Log.console then
        local extra = ''
        if type(meta) == 'table' then
            local parts = {}
            for k, v in pairs(meta) do
                parts[#parts + 1] = ('%s=%s'):format(k, tostring(v))
            end
            if #parts > 0 then
                extra = ' | ' .. table.concat(parts, ' ')
            end
        end
        print(('[gain][%s] %s%s'):format(category, message, extra))
    end

    toDiscord(category, message, meta)
    toDatabase(category, message, meta)
end

exports('Log', function(category, message, meta)
    GainLog.write(category, message, meta)
end)
