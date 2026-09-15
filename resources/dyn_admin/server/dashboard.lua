--[[
  他リソースの export を叩いて、ダッシュボード表示用の1つのテーブルに
  まとめるだけの薄い層。純粋関数ではない（exports 呼び出しは FiveM 依存）ので
  lua5.4 の単体テストからは検証できない。各 export 呼び出しは pcall で守り、
  そのリソースが無い／落ちていてもダッシュボード全体は必ず返す。
]]

local function safeCall(resource, exportName, ...)
    if GetResourceState(resource) ~= 'started' then return nil end
    local ok, result = pcall(function(...) return exports[resource][exportName](exports[resource], ...) end, ...)
    if not ok then
        print(('^1[dyn_admin] %s:%s の呼び出しに失敗: %s^0'):format(resource, exportName, tostring(result)))
        return nil
    end
    return result
end

local function buildItems()
    local list = safeCall('dyn_economy', 'ListItems')
    if not list then return {} end
    local out = {}
    for _, item in ipairs(list) do
        local info = safeCall('dyn_economy', 'GetItemInfo', item)
        if info then out[#out + 1] = info end
    end
    table.sort(out, function(a, b) return (a.item or '') < (b.item or '') end)
    return out
end

local function buildTreasury()
    local spend = safeCall('dyn_treasury', 'GetSpendable')
    if not spend then return nil end
    return {
        balance   = spend.balance,
        spendable = spend.spendable,
        reserve   = spend.reserve,
        period    = safeCall('dyn_treasury', 'CurrentWeekLabel'),
        states    = safeCall('dyn_treasury', 'GetStateBreakdown') or {},
    }
end

local function buildGuilds()
    return {
        pending  = safeCall('dyn_guild', 'ListPendingGuilds') or {},
        approved = safeCall('dyn_guild', 'ListApprovedGuilds') or {},
        enabled  = GetResourceState('dyn_guild') == 'started',
    }
end

function BuildDashboard()
    return {
        items    = buildItems(),
        treasury = buildTreasury(),
        guilds   = buildGuilds(),
        econReady = GetResourceState('dyn_economy') == 'started',
    }
end
