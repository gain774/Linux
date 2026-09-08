--[[
  外部リソース向け API（§10）

  既存の NPC 店舗リソースは、この 4 つを呼ぶだけで動的価格に乗る。
  Quote と Commit を分けているのは、メニュー表示と決済の間に価格が動いても
  表示額で確定させないため。同時売却の抜け穴を塞ぐ。Commit の戻り値が正。
]]

local function ok(res, err)
    if not res then return { ok = false, error = err } end
    return {
        ok       = true,
        total    = res.total,
        unitAvg  = res.unitAvg,
        priceNow = res.priceNow,
        tax      = res.tax,
        qty      = res.qty,
        item     = res.item,
        stock    = res.stock,
    }
end

exports('QuoteSell', function(item, qty, identifier)
    return ok(DynPricing.quoteSell(item, qty, identifier))
end)

exports('QuoteBuy', function(item, qty, identifier)
    return ok(DynPricing.quoteBuy(item, qty, identifier))
end)

exports('CommitSell', function(identifier, item, qty, shopId)
    return ok(DynPricing.commitSell(identifier, item, qty, shopId))
end)

exports('CommitBuy', function(identifier, item, qty, shopId)
    return ok(DynPricing.commitBuy(identifier, item, qty, shopId))
end)

--- 店舗の一覧表示用。設定と現在の状態をまとめて返す
exports('GetItemInfo', function(item)
    local it = DynState.get(item)
    if not it then return nil end
    local sell = DynPricing.quote(item, 1, 'sell')
    local buy  = DynPricing.quote(item, 1, 'buy')
    return {
        item        = item,
        category    = it.category,
        stock       = it.stock,
        targetStock = it.targetStock,
        matCost     = it.matCost,
        npcBuy      = sell and sell.priceNow or nil,   -- NPC がプレイヤーから買う単価
        npcSell     = buy and buy.priceNow or nil,     -- NPC がプレイヤーへ売る単価
        sellable    = it.npcSellable,
        buyable     = it.npcBuyable,
    }
end)

exports('IsReady', function() return DynState.count() > 0 end)
