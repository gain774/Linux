--[[ 起動処理と定期タスク ]]

local function bootstrapAnchor()
    -- 新規サーバー向け（§6.2 B）。currency_scale が未設定なら、
    -- アンカーアイテムの希望価格から逆算して 1 つだけ決める。
    if DynState.econ('currency_scale') ~= 1.0 then return end
    local a = Config.Anchor
    if not a or not a.item or not a.price then return end
    local cfg = Items[a.item]
    if not cfg or not cfg.priceIndex or cfg.priceIndex <= 0 then
        print(('^3[dyn_economy] アンカー %s が items.lua にありません。currency_scale は 1.0 のままです^0')
            :format(tostring(a.item)))
        return
    end
    local scale = a.price / cfg.priceIndex
    DynState.setEcon('currency_scale', scale)
    print(('[dyn_economy] アンカー %s = %.2f から currency_scale = %.4f を設定しました')
        :format(a.item, a.price, scale))
end

CreateThread(function()
    Wait(1000)   -- oxmysql の起動を待つ

    if MySQL then
        DynDb.setReady(true)
        if Config.Db.autoMigrate then DynDb.migrate() end
    else
        print('^3[dyn_economy] oxmysql が無いためメモリ上だけで動作します（永続化なし）^0')
    end

    DynState.load()
    bootstrapAnchor()

    local nRecipes = DynRecipes.load()
    local nCosts   = DynRecipes.refresh()
    print(('[dyn_economy] 起動完了: 品目 %d / レシピ %d / 原価算出 %d')
        :format(DynState.count(), nRecipes, nCosts))

    -- 仮想在庫の書き戻し
    CreateThread(function()
        while true do
            Wait((Config.Db.persistSec or 60) * 1000)
            DynState.persist()
        end
    end)

    -- レシピ原価の再計算（素材価格が動くと原価も動く）
    CreateThread(function()
        while true do
            Wait((Config.Recipes.refreshMin or 15) * 60000)
            DynRecipes.refresh()
        end
    end)

    -- 1 時間バケットの価格履歴
    CreateThread(function()
        while true do
            DynLedger.snapshotPrices()
            Wait(60 * 60000)
        end
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    local n = DynState.persist()
    print(('[dyn_economy] 停止: 仮想在庫 %d 件を保存しました'):format(n or 0))
end)
