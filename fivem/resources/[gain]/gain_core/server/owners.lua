-- オーナーの解決。
--
-- Config.Owners は shared/config.lua にあり、それは shared_scripts に
-- 入っている。つまりそこへ license を書くと、全クライアントへ配信される。
-- git に載る以前に情報漏洩なので、サーバーだけが読む経路に移す。
--
-- 書き場所は secrets.cfg（.gitignore 済み）:
--   set gain_owners "license:aaaa,license:bbbb"

Owners = {}

local cached, cachedRaw = nil, nil

local function list()
    local raw = GetConvar('gain_owners', '')
    if cached and raw == cachedRaw then return cached end

    local out = {}
    for token in raw:gmatch('[^,%s]+') do out[token] = true end

    -- Config.Owners は非推奨。互換のため読むが、使うと全クライアントに配信される
    for _, id in ipairs(Config.Owners or {}) do
        out[id] = true
        GainLog.write('error',
            'Config.Owners に license が書かれている。shared_scripts なので全クライアントへ配信される。'
            .. 'secrets.cfg の set gain_owners へ移すこと', { license = id })
    end

    cached, cachedRaw = out, raw
    return out
end

function Owners.has(license)
    return license ~= nil and list()[license] == true
end

function Owners.count()
    local n = 0
    for _ in pairs(list()) do n = n + 1 end
    return n
end
