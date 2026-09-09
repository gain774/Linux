--[[
  ブリッジの入口。アダプタと価格エンジンを配線し、店舗向けの exports を出す。

  既存の NPC 店舗リソースは、固定価格の計算と決済を
  SellToNpc / BuyFromNpc の呼び出し 1 行に置き換えるだけで動的価格に乗る。
]]

local Adapter

local Economy = {
    quoteSell  = function(item, qty, id)          return exports.dyn_economy:QuoteSell(item, qty, id) end,
    quoteBuy   = function(item, qty, id)          return exports.dyn_economy:QuoteBuy(item, qty, id) end,
    commitSell = function(id, item, qty, shopId)  return exports.dyn_economy:CommitSell(id, item, qty, shopId) end,
    commitBuy  = function(id, item, qty, shopId)  return exports.dyn_economy:CommitBuy(id, item, qty, shopId) end,
    void       = function(committed)              return exports.dyn_economy:VoidCommit(committed) end,
}

local function deps()
    return { adapter = Adapter, economy = Economy }
end

local ERRORS = {
    qty_invalid        = '数量が正しくありません',
    no_character       = 'キャラクター情報を取得できませんでした',
    unknown_item       = 'この店では扱っていない品です',
    item_disabled      = 'この品は現在取引できません',
    not_sellable       = 'この品は買い取っていません',
    not_buyable        = 'この品は販売していません',
    not_enough_items   = '売る品が足りません',
    not_enough_money   = '所持金が足りません',
    cannot_carry       = 'これ以上持てません',
    remove_item_failed = '品を渡せませんでした',
    add_item_failed    = '品を受け取れませんでした',
    quote_failed       = '価格を計算できませんでした',
    commit_failed      = '取引を確定できませんでした',
}

local function fail(source, err)
    if Adapter and source then
        Adapter.notify(source, ERRORS[err] or ('取引できません (' .. tostring(err) .. ')'))
    end
    return { ok = false, error = err }
end

local function money(v)
    return ('%s%.2f'):format(BridgeConfig.currencyLabel or '$', v)
end

CreateThread(function()
    Adapter = _G.DynAdapters and _G.DynAdapters[BridgeConfig.framework]
    if not Adapter then
        print(('^1[dyn_economy_bridge] framework = "%s" のアダプタがありません^0')
            :format(tostring(BridgeConfig.framework)))
        return
    end

    while not Adapter.isReady() do Wait(500) end
    print(('[dyn_economy_bridge] %s アダプタを使用します'):format(Adapter.name))

    -- dyn_economy と vorp_inventory の品目読み込みが終わるのを待ってから突き合わせる
    while not exports.dyn_economy:IsReady() do Wait(500) end
    Wait(2000)
    DynCompat.run()
end)

--- プレイヤーが NPC に売る
exports('SellToNpc', function(source, item, qty, shopId)
    if not Adapter then return fail(source, 'no_character') end
    local res, err = DynTxFlow.sellToNpc(deps(), source, item, qty, shopId)
    if not res then return fail(source, err) end
    Adapter.notify(source, ('%s x%d を %s で売りました'):format(item, qty, money(res.total)))
    return res
end)

--- プレイヤーが NPC から買う
exports('BuyFromNpc', function(source, item, qty, shopId)
    if not Adapter then return fail(source, 'no_character') end
    local res, err = DynTxFlow.buyFromNpc(deps(), source, item, qty, shopId)
    if not res then return fail(source, err) end
    Adapter.notify(source, ('%s x%d を %s で買いました'):format(item, qty, money(res.total)))
    return res
end)

--- メニュー表示用の見積り。identifier をこちらで解決するので店舗側は source を渡すだけでよい。
--- **表示専用**。実際の金額は SellToNpc / BuyFromNpc の戻り値が正。
exports('Quote', function(source, item, qty, direction)
    if not Adapter then return { ok = false, error = 'no_character' } end
    local id = Adapter.getIdentifier(source)
    if not id then return { ok = false, error = 'no_character' } end
    if direction == 'buy' then
        return Economy.quoteBuy(item, qty or 1, id)
    end
    return Economy.quoteSell(item, qty or 1, id)
end)

--- 店舗の一覧表示用。価格エンジンの GetItemInfo をそのまま通す
exports('GetItemInfo', function(item)
    return exports.dyn_economy:GetItemInfo(item)
end)

--- 店舗リソースが所持金や現物を直接触りたい場合に使う
exports('GetAdapter', function() return Adapter end)

exports('IsReady', function()
    return Adapter ~= nil and Adapter.isReady() and exports.dyn_economy:IsReady()
end)
