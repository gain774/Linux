--[[ 取引ログと価格履歴（§3.2 / §3.4） ]]
DynLedger = {}

--- 確定した取引を dyn_npc_tx に残す。
--- price_breakdown を必ず入れる。「あのとき何であの値段だったか」を
--- 後から再現できないと、価格クレームに対して何も言えなくなる。
function DynLedger.record(identifier, q, shopId)
    if not DynDb.isReady() then return end
    DynDb.insert([[
        INSERT INTO dyn_npc_tx
          (identifier, item, direction, qty, unit_price, total, tax_amount,
           stock_before, stock_after, shop, price_breakdown, created_at)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,NOW())
    ]], {
        identifier or 'unknown', q.item, q.direction, q.qty,
        q.unitAvg, q.total, q.tax or 0,
        q.stockBefore or 0, q.stockAfter or 0,
        shopId, json.encode(q.breakdown or {}),
    })
end

--- 1 時間バケットの価格履歴を書く（Phase 5 のグラフ用の土台）
function DynLedger.snapshotPrices()
    if not DynDb.isReady() then return end
    for name, it in pairs(DynState.all()) do
        if it.enabled then
            local sell = DynPricing.quote(name, 1, 'sell')
            local buy  = DynPricing.quote(name, 1, 'buy')
            if sell or buy then
                DynDb.execute([[
                    INSERT INTO dyn_price_history (item, bucket_at, npc_buy, npc_sell)
                    VALUES (?, DATE_FORMAT(NOW(), '%Y-%m-%d %H:00:00'), ?, ?)
                    ON DUPLICATE KEY UPDATE npc_buy = VALUES(npc_buy), npc_sell = VALUES(npc_sell)
                ]], { name, sell and sell.priceNow or 0, buy and buy.priceNow or 0 })
            end
        end
    end
end
