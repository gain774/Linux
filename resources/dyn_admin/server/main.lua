--[[
  管理者ダッシュボード（NUI）のサーバー側。

  価格・在庫・税収(州別)・組合承認・fixed切替を1画面で見られるようにする。
  ここで実装するのは表示の組み立てと操作の受け口だけ。実際の判断ロジックは
  dyn_economy / dyn_treasury / dyn_guild 側の export にすべて委譲する
  （承認条件・上限などをここで再実装しない）。
]]

local ACE = 'dyn_economy.admin'

local function isAdmin(src)
    return src ~= 0 and IsPlayerAceAllowed(tostring(src), ACE)
end

--- 監査用の「誰が操作したか」。他リソースの識別子取得ロジックを
--- 呼ぶのは大げさなので、プレイヤー名で足りるとしている
local function actorLabel(src)
    local name = GetPlayerName(src)
    return name and ('nui:' .. name) or ('nui:src' .. tostring(src))
end

RegisterServerEvent('dyn_admin:requestOpen')
AddEventHandler('dyn_admin:requestOpen', function()
    local src = source
    if not isAdmin(src) then
        return TriggerClientEvent('dyn_admin:denied', src, '権限がありません（ACE: dyn_economy.admin）')
    end
    TriggerClientEvent('dyn_admin:open', src, BuildDashboard())
end)

--[[
  操作の受け口。種類ごとに対応する export を 1 回呼ぶだけで、判断は
  呼び出し先の export に任せる。成否にかかわらず最新のダッシュボードを
  送り返し、NUI 側は常にサーバーの実際の状態を表示する（楽観更新はしない）。
]]
RegisterServerEvent('dyn_admin:action')
AddEventHandler('dyn_admin:action', function(kind, payload)
    local src = source
    if not isAdmin(src) then return end
    payload = payload or {}

    local ok, err = false, 'unknown_action'
    if kind == 'setFixed' and GetResourceState('dyn_economy') == 'started' then
        local success = pcall(function() ok = exports.dyn_economy:SetItemFixed(payload.item, payload.fixed) end)
        if not success then ok, err = false, 'call_failed' end
    elseif kind == 'approveGuild' and GetResourceState('dyn_guild') == 'started' then
        local success = pcall(function() ok, err = exports.dyn_guild:ApproveGuild(payload.id, actorLabel(src)) end)
        if not success then ok, err = false, 'call_failed' end
    elseif kind == 'rejectGuild' and GetResourceState('dyn_guild') == 'started' then
        local success = pcall(function() ok, err = exports.dyn_guild:RejectGuild(payload.id, payload.reason, actorLabel(src)) end)
        if not success then ok, err = false, 'call_failed' end
    elseif kind == 'revokeGuild' and GetResourceState('dyn_guild') == 'started' then
        local success = pcall(function() ok, err = exports.dyn_guild:RevokeGuild(payload.id, payload.reason, actorLabel(src)) end)
        if not success then ok, err = false, 'call_failed' end
    end

    TriggerClientEvent('dyn_admin:actionResult', src, { ok = ok and true or false, kind = kind, error = (ok ~= true) and tostring(err) or nil })
    TriggerClientEvent('dyn_admin:open', src, BuildDashboard())
end)
