--[[ 管理・確認用コマンド。Phase 2 の完了条件は /dyn_quote が価格を返すこと ]]

local ACE = 'dyn_economy.admin'

local function allowed(src)
    if src == 0 then return true end                       -- コンソール
    return IsPlayerAceAllowed(tostring(src), ACE)
end

local function reply(src, msg)
    if src == 0 then
        print(msg)
    else
        TriggerClientEvent('chat:addMessage', src, { args = { 'dyn_economy', msg } })
    end
end

local function money(v)
    return ('%s%.2f'):format(Config.Currency.label, v)
end

RegisterCommand('dyn_quote', function(src, args)
    if not allowed(src) then return reply(src, '権限がありません') end
    local item = args[1]
    local qty  = tonumber(args[2]) or 1
    local dir  = (args[3] == 'buy') and 'buy' or 'sell'
    if not item then return reply(src, '使い方: /dyn_quote <item> [数量] [sell|buy]') end

    local q, err = DynPricing.quote(item, qty, dir)
    if not q then return reply(src, ('見積り不可: %s (%s)'):format(item, err)) end

    reply(src, ('%s x%d [%s] 合計 %s / 平均単価 %s / 現在単価 %s / 税 %s')
        :format(item, qty, dir, money(q.total), money(q.unitAvg), money(q.priceNow), money(q.tax)))
    reply(src, ('  在庫 %.2f / 均衡 %.2f / 基準価格 %s%s')
        :format(q.stock, DynState.get(item).targetStock, money(q.basePrice),
                q.breakdown.floor and (' / 原価下限 x%.3f'):format(q.breakdown.floor) or ''))
end, false)

RegisterCommand('dyn_price', function(src, args)
    if not allowed(src) then return reply(src, '権限がありません') end
    local filter = args[1]
    local list = {}
    for name, it in pairs(DynState.all()) do
        if not filter or name:find(filter, 1, true) then
            list[#list + 1] = { name = name, it = it }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    reply(src, ('品目 %d 件（買取 / 販売 / 在庫比）'):format(#list))
    for _, e in ipairs(list) do
        local s = DynPricing.quote(e.name, 1, 'sell')
        local b = DynPricing.quote(e.name, 1, 'buy')
        reply(src, ('  %-14s %8s %8s  %.0f%%')
            :format(e.name,
                    s and money(s.priceNow) or '-',
                    b and money(b.priceNow) or '-',
                    (e.it.stock / e.it.targetStock) * 100))
    end
end, false)

RegisterCommand('dyn_cost', function(src, args)
    if not allowed(src) then return reply(src, '権限がありません') end
    local item = args[1]
    if not item then return reply(src, '使い方: /dyn_cost <item>') end
    local cost = DynRecipes.costOf(item)
    if not cost then return reply(src, ('%s: レシピ原価なし（素材か、原価を計算できない品目）'):format(item)) end
    reply(src, ('%s: 原価 %s / 下限 %s (マージン x%.2f)')
        :format(item, money(cost), money(cost * Config.Recipes.craftMargin), Config.Recipes.craftMargin))
end, false)

RegisterCommand('dyn_setstock', function(src, args)
    if not allowed(src) then return reply(src, '権限がありません') end
    local item, value = args[1], tonumber(args[2])
    if not item or not value then return reply(src, '使い方: /dyn_setstock <item> <在庫>') end
    if not DynState.setStock(item, value) then return reply(src, '不明なアイテム: ' .. item) end
    reply(src, ('%s の仮想在庫を %.2f にしました'):format(item, value))
end, false)

RegisterCommand('dyn_econ', function(src, args)
    if not allowed(src) then return reply(src, '権限がありません') end
    local key, value = args[1], tonumber(args[2])
    if key and value then
        DynState.setEcon(key, value)
        return reply(src, ('%s = %.6f に設定しました'):format(key, value))
    end
    reply(src, ('currency_scale=%.4f  cpi_mult=%.4f  income_mult=%.4f  品目数=%d  DB=%s')
        :format(DynState.econ('currency_scale'), DynState.econ('cpi_mult'),
                DynState.econ('income_mult'), DynState.count(),
                DynDb.isReady() and 'ok' or 'なし'))
end, false)

RegisterCommand('dyn_import_recipes', function(src, args)
    if not allowed(src) then return reply(src, '権限がありません') end

    local apply = false
    local resource
    for _, a in ipairs(args) do
        if a == '--apply' then apply = true
        elseif a ~= '--dry-run' then resource = a end
    end

    local r, err = DynRecipes.import({ apply = apply, resource = resource })
    if not r then return reply(src, '取り込めません: ' .. tostring(err)) end

    reply(src, ('取り込み %d 件 / 除外 %d 件%s')
        :format(r.imported, r.skipped, apply and '（適用済み）' or '（ドライラン）'))
    for reason, n in pairs(r.reasons) do
        reply(src, ('  除外 %-18s %d 件'):format(reason, n))
    end
    for i = 1, math.min(10, #r.recipes) do
        local rec = r.recipes[i]
        local parts = {}
        for _, inp in ipairs(rec.inputs) do
            parts[#parts + 1] = ('%s x%g'):format(inp.item, inp.qty)
        end
        reply(src, ('  %s x%d <- %s'):format(rec.outputItem, rec.outputQty, table.concat(parts, ', ')))
    end
    if #r.recipes > 10 then reply(src, ('  ... 他 %d 件'):format(#r.recipes - 10)) end

    if apply then
        reply(src, ('レシピ %d 件を読み込み、原価 %d 件を算出しました')
            :format(r.loaded or 0, r.costed or 0))
    else
        reply(src, '適用するには /dyn_import_recipes --apply')
    end
end, false)

RegisterCommand('dyn_reload', function(src)
    if not allowed(src) then return reply(src, '権限がありません') end
    DynState.persist()
    DynState.load()
    local r = DynRecipes.load()
    local c = DynRecipes.refresh()
    reply(src, ('再読み込み完了: 品目 %d / レシピ %d / 原価算出 %d')
        :format(DynState.count(), r, c))
end, false)
