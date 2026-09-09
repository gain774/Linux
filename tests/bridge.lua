--[[
  決済フロー（dyn_economy_bridge/server/txflow.lua）のテスト。

  価格エンジンは本物を使い、所持金と現物だけスタブに差し替える。
  順序を間違えると金か現物が増えるので、失敗経路を重点的に見る。
    lua5.4 tests/bridge.lua
]]

local root = (arg[0]:match('^(.*)/tests/bridge%.lua$') or '.')
local res  = root .. '/resources/dyn_economy'

json = { encode = function() return '{}' end }

dofile(res .. '/shared/pricing_math.lua')
dofile(res .. '/server/recipes_core.lua')
dofile(res .. '/config/config.lua')
dofile(res .. '/config/categories.lua')
dofile(res .. '/config/items.lua')

DynDb = {
    isReady = function() return false end,
    query = function() return {} end, execute = function() end, insert = function() end,
}

dofile(res .. '/server/state.lua')
dofile(res .. '/server/pricing.lua')
dofile(res .. '/server/ledger.lua')
dofile(root .. '/resources/dyn_economy_bridge/server/txflow.lua')

local passed, failed = 0, 0
local function ok(cond, name, extra)
    if cond then passed = passed + 1
    else
        failed = failed + 1
        print(('  FAIL  %s%s'):format(name, extra and ('  -- ' .. extra) or ''))
    end
end
local function near(a, b, name, tol)
    tol = tol or 1e-6
    ok(a and math.abs(a - b) <= tol, name,
       ('expected %.4f got %s'):format(b, a and ('%.4f'):format(a) or 'nil'))
end
local function group(n) print(n) end

-- 本物の価格エンジンをそのまま使う
local Economy = {
    quoteSell  = function(item, qty, id)
        local q, e = DynPricing.quoteSell(item, qty, id)
        return q and { ok = true, total = q.total } or { ok = false, error = e }
    end,
    quoteBuy   = function(item, qty, id)
        local q, e = DynPricing.quoteBuy(item, qty, id)
        return q and { ok = true, total = q.total } or { ok = false, error = e }
    end,
    commitSell = function(id, item, qty, shop)
        local q, e = DynPricing.commitSell(id, item, qty, shop)
        return q and { ok = true, total = q.total, item = q.item, qty = q.qty,
                       direction = q.direction, txId = q.txId } or { ok = false, error = e }
    end,
    commitBuy  = function(id, item, qty, shop)
        local q, e = DynPricing.commitBuy(id, item, qty, shop)
        return q and { ok = true, total = q.total, item = q.item, qty = q.qty,
                       direction = q.direction, txId = q.txId } or { ok = false, error = e }
    end,
    void       = function(c) return { ok = DynPricing.void(c) } end,
}

--- 所持金と現物のスタブ。失敗させたい箇所を fail テーブルで指定する
local function newAdapter(opts)
    opts = opts or {}
    local a = {
        money = opts.money or 1000,
        items = opts.items or {},
        calls = {},
        fail  = opts.fail or {},
    }
    local function log(what) a.calls[#a.calls + 1] = what end
    a.getIdentifier = function() return opts.identifier ~= false and 'char1' or nil end
    a.getMoney      = function() return a.money end
    a.addMoney      = function(_, amt) log('addMoney'); a.money = a.money + amt; return true end
    a.removeMoney   = function(_, amt) log('removeMoney'); a.money = a.money - amt; return true end
    a.getItemCount  = function(_, item) return a.items[item] or 0 end
    a.addItem       = function(_, item, qty)
        log('addItem')
        if a.fail.addItem then return false end
        a.items[item] = (a.items[item] or 0) + qty; return true
    end
    a.removeItem    = function(_, item, qty)
        log('removeItem')
        if a.fail.removeItem then return false end
        a.items[item] = (a.items[item] or 0) - qty; return true
    end
    a.canCarry      = function() return not a.fail.canCarry end
    a.notify        = function() end
    return a
end

local function reset()
    DynState.load()
    DynState.setEcon('currency_scale', 1.0)
    DynState.setEcon('cpi_mult', 1.0)
    DynState.setEcon('income_mult', 1.0)
    Config.Currency.step = 0
end

local function stockOf(item) return DynState.get(item).stock end

reset()

group('売却: 正常系')
do
    local a = newAdapter({ money = 100, items = { corn = 50 } })
    local before = stockOf('corn')
    local r, err = DynTxFlow.sellToNpc({ adapter = a, economy = Economy }, 1, 'corn', 20, 'shop_a')
    ok(r ~= nil, '成立する', tostring(err))
    ok(a.items.corn == 30, '現物が 20 個減る')
    near(a.money, 100 + r.total, '受取額ぶん所持金が増える')
    near(stockOf('corn'), before + 20, '仮想在庫が 20 増える')
    ok(a.calls[1] == 'removeItem' and a.calls[2] == 'addMoney',
       '現物を引いてから入金する（逆だと引けなかったときに金だけ増える）')
end

group('売却: 現物が足りない')
do
    local a = newAdapter({ money = 100, items = { corn = 5 } })
    local before = stockOf('corn')
    local r, err = DynTxFlow.sellToNpc({ adapter = a, economy = Economy }, 1, 'corn', 20)
    ok(r == nil and err == 'not_enough_items', 'not_enough_items で止まる')
    ok(#a.calls == 0, '現物にも所持金にも触っていない')
    near(stockOf('corn'), before, '仮想在庫が動いていない')
    near(a.money, 100, '所持金が動いていない')
end

group('売却: 現物を引けなかった')
do
    local a = newAdapter({ money = 100, items = { corn = 50 }, fail = { removeItem = true } })
    local before = stockOf('corn')
    local r, err = DynTxFlow.sellToNpc({ adapter = a, economy = Economy }, 1, 'corn', 20)
    ok(r == nil and err == 'remove_item_failed', 'remove_item_failed で止まる')
    near(a.money, 100, '入金していない')
    near(stockOf('corn'), before, '仮想在庫を動かしていない（確定前に落ちている）')
end

group('売却: 確定に失敗したら現物を返す')
do
    local a = newAdapter({ money = 100, items = { corn = 50 } })
    local broken = setmetatable({ commitSell = function() return { ok = false, error = 'boom' } end },
                                { __index = Economy })
    local r, err = DynTxFlow.sellToNpc({ adapter = a, economy = broken }, 1, 'corn', 20)
    ok(r == nil and err == 'boom', '確定失敗のエラーがそのまま返る')
    ok(a.items.corn == 50, '引いた現物が戻っている')
    near(a.money, 100, '入金していない')
end

group('売却: 扱えない品目')
do
    local a = newAdapter({ items = { water = 10 } })
    local r, err = DynTxFlow.sellToNpc({ adapter = a, economy = Economy }, 1, 'water', 5)
    ok(r == nil and err == 'not_sellable', 'npcSellable = false は not_sellable')
    ok(#a.calls == 0, '現物に触れていない')

    local r2, err2 = DynTxFlow.sellToNpc({ adapter = a, economy = Economy }, 1, 'nonexistent', 5)
    ok(r2 == nil and err2 == 'unknown_item', '未定義アイテムは unknown_item')
end

group('購入: 正常系')
reset()
do
    local a = newAdapter({ money = 1000, items = {} })
    local before = stockOf('corn')
    local r, err = DynTxFlow.buyFromNpc({ adapter = a, economy = Economy }, 1, 'corn', 20, 'shop_a')
    ok(r ~= nil, '成立する', tostring(err))
    ok(a.items.corn == 20, '現物を 20 個受け取る')
    near(a.money, 1000 - r.total, '支払額ぶん所持金が減る')
    near(stockOf('corn'), before - 20, '仮想在庫が 20 減る')
    ok(a.calls[1] == 'removeMoney' and a.calls[2] == 'addItem',
       '支払ってから現物を渡す')
end

group('購入: 所持金が足りない')
reset()
do
    local a = newAdapter({ money = 1, items = {} })
    local before = stockOf('corn')
    local r, err = DynTxFlow.buyFromNpc({ adapter = a, economy = Economy }, 1, 'corn', 100)
    ok(r == nil and err == 'not_enough_money', 'not_enough_money で止まる')
    near(a.money, 1, '所持金が動いていない')
    ok(a.items.corn == nil, '現物を渡していない')
    near(stockOf('corn'), before, '取り消しで仮想在庫が元に戻っている')
end

group('購入: 持ちきれない')
reset()
do
    local a = newAdapter({ money = 1000, fail = { canCarry = true } })
    local before = stockOf('corn')
    local r, err = DynTxFlow.buyFromNpc({ adapter = a, economy = Economy }, 1, 'corn', 20)
    ok(r == nil and err == 'cannot_carry', 'cannot_carry で止まる')
    ok(#a.calls == 0, '所持金にも現物にも触れていない')
    near(stockOf('corn'), before, '仮想在庫を動かす前に落ちている')
end

group('購入: 現物を渡せなかったら返金して取り消す')
reset()
do
    local a = newAdapter({ money = 1000, fail = { addItem = true } })
    local before = stockOf('corn')
    local r, err = DynTxFlow.buyFromNpc({ adapter = a, economy = Economy }, 1, 'corn', 20)
    ok(r == nil and err == 'add_item_failed', 'add_item_failed で止まる')
    near(a.money, 1000, '全額返金されている')
    near(stockOf('corn'), before, '仮想在庫が元に戻っている')
end

group('取り消しは二重に効かない')
reset()
do
    local before = stockOf('corn')
    local c = DynPricing.commitSell('char1', 'corn', 10)
    ok(DynPricing.void(c) == true, '1 回目の取り消しは成功')
    ok(DynPricing.void(c) == false, '2 回目は何もしない')
    near(stockOf('corn'), before, '在庫が二重に戻らない')
end

group('引数の検証')
do
    local a = newAdapter({ items = { corn = 50 }, money = 1000 })
    local d = { adapter = a, economy = Economy }
    for _, bad in ipairs({ 0, -5, 1.5 }) do
        local r, err = DynTxFlow.sellToNpc(d, 1, 'corn', bad)
        ok(r == nil and err == 'qty_invalid', ('数量 %s は qty_invalid'):format(tostring(bad)))
    end
    local r, err = DynTxFlow.sellToNpc(d, 1, 'corn', '20')
    ok(r == nil and err == 'qty_invalid', '文字列の数量は qty_invalid')

    local noChar = newAdapter({ identifier = false })
    local r2, err2 = DynTxFlow.buyFromNpc({ adapter = noChar, economy = Economy }, 1, 'corn', 1)
    ok(r2 == nil and err2 == 'no_character', 'キャラクター未取得は no_character')
    ok(#a.calls == 0, '検証で落ちた分は何も触っていない')
end

print()
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
