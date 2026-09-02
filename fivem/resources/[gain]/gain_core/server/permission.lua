-- 権限判定。権限は gain_users.permission に文字列で保存し、
-- Config.Permissions の数値順で比較する。

Permission = {}

--- 権限名を数値に変換する。未知の名前は最弱扱い。
---@param name string|nil
---@return number
function Permission.rank(name)
    return Config.Permissions[name or 'user'] or 0
end

--- src のプレイヤーが required 以上の権限を持つか。
--- プレイヤーが未ロードなら常に false。
---@param src number
---@param required string
---@return boolean
function Permission.has(src, required)
    local player = GetGainPlayer(src)
    if not player then return false end

    return Permission.rank(player.permission) >= Permission.rank(required)
end

--- 権限を変更して DB に保存する。
---@param src number
---@param level string
---@return boolean ok
function Permission.set(src, level)
    if Config.Permissions[level] == nil then return false end

    local player = GetGainPlayer(src)
    if not player then return false end

    player.permission = level
    MySQL.update('UPDATE gain_users SET permission = ? WHERE license = ?', { level, player.license })
    player.sync()

    GainLog.write('admin', '権限を変更', {
        target = player.name,
        license = player.license,
        level = level,
    })

    return true
end
