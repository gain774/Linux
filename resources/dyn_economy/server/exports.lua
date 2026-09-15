--[[
  外部リソース向け API（§10）

  既存の NPC 店舗リソースは、この 4 つを呼ぶだけで動的価格に乗る。
  Quote と Commit を分けているのは、メニュー表示と決済の間に価格が動いても
  表示額で確定させないため。同時売却の抜け穴を塞ぐ。Commit の戻り値が正。
]]

local function ok(res, err)
    if not res then return { ok = false, error = err } end
    return {
        ok        = true,
        total     = res.total,
        unitAvg   = res.unitAvg,
        priceNow  = res.priceNow,
        tax       = res.tax,
        qty       = res.qty,
        item      = res.item,
        stock     = res.stock,
        -- 取り消しに必要な情報。Commit の戻り値をそのまま VoidCommit に渡せる
        direction = res.direction,
        txId      = res.txId,
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
    local ref  = DynPlayerRef.get(item)
    return {
        item        = item,
        label       = it.label or item,
        desc        = it.desc,
        category    = it.category,
        stock       = it.stock,
        targetStock = it.targetStock,
        matCost     = it.matCost,
        npcBuy      = sell and sell.priceNow or nil,   -- NPC がプレイヤーから買う単価
        npcSell     = buy and buy.priceNow or nil,     -- NPC がプレイヤーへ売る単価
        sellable    = it.npcSellable,
        buyable     = it.npcBuyable,
        fixed       = it.fixed,
        playerVwap  = ref.vwap,      -- 直近ウィンドウの個人間取引 VWAP（§8.2）。無ければ nil
        playerQty   = ref.qty,
    }
end)

--[[
  個人間取引（dyn_trade 等）の約定 1 件を参考価格として記録する（§8.2）。
  仮想在庫・基準価格は一切動かさない。Config.PlayerRef.enabled=false なら何もしない。
]]
exports('RecordPlayerTrade', function(item, qty, unitPrice)
    return DynPlayerRef.record(item, qty, unitPrice)
end)

--- item の直近ウィンドウの VWAP・出来高・サンプル数。記録が無ければ vwap=nil
exports('GetPlayerVwap', function(item)
    return DynPlayerRef.get(item)
end)

--[[
  確定済みの取引を取り消す。CommitSell / CommitBuy の戻り値をそのまま渡す。

  決済の途中で失敗した店舗側が、仮想在庫だけ動いた状態を残さないために呼ぶ。
  通常の売買では使わない。
]]
exports('VoidCommit', function(committed)
    if type(committed) ~= 'table' then return { ok = false, error = 'bad_argument' } end
    local done = DynPricing.void({
        item      = committed.item,
        qty       = committed.qty,
        direction = committed.direction,
        txId      = committed.txId,
    })
    return { ok = done }
end)

--- 扱っている品目名の一覧。起動時の突き合わせに使う
exports('ListItems', function()
    local list = {}
    for name in pairs(DynState.all()) do list[#list + 1] = name end
    table.sort(list)
    return list
end)

--- 品目の有効／無効を切り替える。
--- インベントリ側に存在しない品を無効化するなど、環境に合わせた除外に使う
exports('SetItemEnabled', function(item, enabled)
    return DynState.setEnabled(item, enabled)
end)

--- 品目を固定価格／変動価格に切り替える（DB へ永続化）。
--- 銃・弾薬・道具のように「売り込まれても値崩れしてほしくない」品目を
--- 個別に固定価格へ倒すための管理用途
exports('SetItemFixed', function(item, fixed)
    return DynState.setFixed(item, fixed)
end)

exports('IsReady', function() return DynState.count() > 0 end)
