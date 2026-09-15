--[[
  新規キャラの開始所持金を、サーバーの物価から自動で決める（§6.3）。

  vorp_character は新規キャラを固定額（Config.initMoney）で作る。
  ここでは vorp_NewCharacter（キャラ作成の3秒後に発火）を拾って、
  dyn_economy が算出した目標額との差分だけを addCurrency/removeCurrency で
  調整する。**既存キャラの所持金には一切触らない**（このイベントは新規作成時
  にしか飛ばない）。
]]

AddEventHandler('vorp_NewCharacter', function(source)
    if not BridgeConfig.startingCash or not BridgeConfig.startingCash.enabled then return end
    if GetResourceState('dyn_economy') ~= 'started' then return end

    local ok, target = pcall(function() return exports.dyn_economy:GetStartingCash() end)
    if not ok or not target or target <= 0 then return end

    local adapter = DynAdapters.vorp
    -- vorp_NewCharacter は3秒後発火の設計だが、Core.getUser がまだ準備できて
    -- いない瞬間を拾う可能性への保険として少し待つ
    local waited = 0
    while not adapter.isReady() and waited < 5000 do
        Wait(200)
        waited = waited + 200
    end
    if not adapter.isReady() then return end

    local current = adapter.getMoney(source)
    local delta = target - current
    if delta > 0 then
        adapter.addMoney(source, delta)
    elseif delta < 0 then
        adapter.removeMoney(source, -delta)
    end

    print(('[dyn_economy_bridge] 新規キャラの開始所持金を %.2f に設定しました（既定 %.2f からの差分 %+.2f）')
        :format(target, current, delta))
end)
