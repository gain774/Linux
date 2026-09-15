--[[
  dyn_admin/server/dashboard.lua のテスト。

  FiveM の exports は模擬する。見たいのは「他リソースが無い／落ちていても
  ダッシュボード全体は必ず空データで返ってくる」こと（NUI 側を壊さないため）。
    lua5.4 tests/admin.lua
]]
local root = (arg[0]:match('^(.*)/tests/admin%.lua$') or '.')

local passed, failed = 0, 0
local function ok(cond, name, extra)
    if cond then passed = passed + 1
    else failed = failed + 1; print(('  FAIL  %s%s'):format(name, extra and ('  -- '..extra) or '')) end
end
local function group(n) print(n) end

-- ---------------------------------------------------------------- 何もリソースが無い場合
do
    _G.resourceStates = {}
    GetResourceState = function(name) return _G.resourceStates[name] or 'missing' end
    exports = setmetatable({}, { __index = function() error('exports should not be called when resource is not started') end })

    dofile(root .. '/resources/dyn_admin/server/dashboard.lua')
    local d = BuildDashboard()

    group('リソースが何も無いとき')
    ok(type(d) == 'table', 'テーブルを返す（落ちない）')
    ok(type(d.items) == 'table' and #d.items == 0, 'items は空配列')
    ok(d.treasury == nil, 'treasury は nil')
    ok(type(d.guilds) == 'table' and #d.guilds.pending == 0 and #d.guilds.approved == 0, 'guilds は空')
    ok(d.guilds.enabled == false, 'guilds.enabled は false')
    ok(d.econReady == false, 'econReady は false')
end

-- ---------------------------------------------------------------- 全部揃っている場合
do
    _G.resourceStates = { dyn_economy = 'started', dyn_treasury = 'started', dyn_guild = 'started' }
    GetResourceState = function(name) return _G.resourceStates[name] or 'missing' end

    local fakeItems = { 'corn', 'wheat' }
    local fakeInfo = {
        corn  = { item = 'corn', label = 'コーン', npcBuy = 1.0 },
        wheat = { item = 'wheat', label = '小麦', npcBuy = 2.0 },
    }
    exports = {
        dyn_economy = {
            ListItems = function(self) return fakeItems end,
            GetItemInfo = function(self, item) return fakeInfo[item] end,
        },
        dyn_treasury = {
            GetSpendable = function(self) return { balance = 100, spendable = 40, reserve = 60 } end,
            CurrentWeekLabel = function(self) return '2026-W10' end,
            GetStateBreakdown = function(self) return { { state = 'new_hanover', total = 50, count = 3 } } end,
        },
        dyn_guild = {
            ListPendingGuilds = function(self) return { { id = 1, name = '農協' } } end,
            ListApprovedGuilds = function(self) return {} end,
        },
    }

    dofile(root .. '/resources/dyn_admin/server/dashboard.lua')
    local d = BuildDashboard()

    group('全リソースが揃っているとき')
    ok(#d.items == 2, '品目が2件返る')
    ok(d.items[1].item == 'corn' and d.items[2].item == 'wheat', 'item 名でソートされる')
    ok(d.treasury ~= nil and d.treasury.balance == 100, 'treasury が入る')
    ok(d.treasury.period == '2026-W10', '週ラベルが入る')
    ok(#d.treasury.states == 1 and d.treasury.states[1].state == 'new_hanover', '州別内訳が入る')
    ok(#d.guilds.pending == 1 and d.guilds.pending[1].name == '農協', '承認待ちが入る')
    ok(d.guilds.enabled == true, 'guilds.enabled は true')
end

-- ---------------------------------------------------------------- export が例外を投げても落ちない
do
    _G.resourceStates = { dyn_economy = 'started' }
    GetResourceState = function(name) return _G.resourceStates[name] or 'missing' end
    exports = {
        dyn_economy = {
            ListItems = function(self) error('boom') end,
        },
    }
    dofile(root .. '/resources/dyn_admin/server/dashboard.lua')
    local okCall, d = pcall(BuildDashboard)
    group('export が例外を投げるとき')
    ok(okCall == true, 'BuildDashboard 自体は例外を外に漏らさない')
    ok(d and #d.items == 0, '失敗した部分は空データにフォールバックする')
end

print()
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
