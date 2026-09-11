--[[
  fxmanifest.lua の取りこぼし検査。

  リソース内の .lua が manifest に載っていないと、その定義は実サーバーでだけ
  nil になる。単体テストは dofile で直接読むので、この種の抜けは素通りする。
  実際に recipes_core.lua が漏れていて、起動して初めて分かった。
    lua5.4 tests/manifest.lua
]]

local root = (arg[0]:match('^(.*)/tests/manifest%.lua$') or '.')

local passed, failed = 0, 0
local function ok(cond, name, extra)
    if cond then passed = passed + 1
    else failed = failed + 1; print(('  FAIL  %s%s'):format(name, extra and ('  -- '..extra) or '')) end
end

local function run(cmd)
    local f = io.popen(cmd)
    local out = f:read('a'); f:close()
    return out
end

--- manifest 内の .lua 参照を集める。'client/*.lua' のような glob も拾う
local function referencedPatterns(manifestPath)
    local f = assert(io.open(manifestPath))
    local src = f:read('a'); f:close()
    local pats = {}
    for quoted in src:gmatch("['\"]([^'\"]-%.lua)['\"]") do
        -- '@other_resource/...' は他リソースのファイルなので対象外
        if not quoted:match('^@') then pats[#pats + 1] = quoted end
    end
    return pats
end

local function matches(pats, rel)
    for _, p in ipairs(pats) do
        if p == rel then return true end
        -- glob: * を「/ を含まない任意」に、** を「任意」に
        local lua = p:gsub('([%.%-%+%[%]%(%)%$%^%%%?])', '%%%1')
                     :gsub('%*%*', '\1'):gsub('%*', '[^/]*'):gsub('\1', '.*')
        if rel:match('^' .. lua .. '$') then return true end
    end
    return false
end

local resources = {}
for line in run('ls ' .. root .. '/resources'):gmatch('[^\n]+') do
    resources[#resources + 1] = line
end
ok(#resources > 0, 'リソースが見つかる')

for _, res in ipairs(resources) do
    local dir = root .. '/resources/' .. res
    local manifest = dir .. '/fxmanifest.lua'
    local mf = io.open(manifest)
    if not mf then
        ok(false, ('%s に fxmanifest.lua がある'):format(res))
    else
        mf:close()
        local pats = referencedPatterns(manifest)
        local missing = {}
        for path in run(('find %q -name "*.lua" -not -name fxmanifest.lua'):format(dir)):gmatch('[^\n]+') do
            local rel = path:sub(#dir + 2)
            if not matches(pats, rel) then missing[#missing + 1] = rel end
        end
        table.sort(missing)
        ok(#missing == 0,
           ('%s: すべての .lua が manifest に載っている'):format(res),
           #missing > 0 and ('未登録: ' .. table.concat(missing, ', ')) or nil)
    end
end

print()
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
