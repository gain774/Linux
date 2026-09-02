Locales = Locales or {}

--- ロケール文字列を取得する。
--- 第2引数以降を渡すと string.format に通す。
---@param key string
---@return string
function _L(key, ...)
    local dict = Locales[Config.Locale] or Locales['ja']
    local str = dict and dict[key]

    if not str then
        return ('[missing:%s]'):format(key)
    end

    if select('#', ...) > 0 then
        local ok, formatted = pcall(string.format, str, ...)
        if ok then return formatted end
    end

    return str
end
