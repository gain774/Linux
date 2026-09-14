--[[
  個人間取引（dyn_trade/server/trade_flow.lua, trade_math.lua）のテスト。

  最重要視点: 失敗経路で本当に「全部戻る」か。片方だけ戻って片方が消える／
  増えるバグは、資産を溶かすかコピー機になるかのどちらかなので、ここを厚めに見る。
    lua5.4 tests/dyn_trade.lua
]]

local root = (arg[0]:match('^(.*)/tests/dyn_trade%.lua$') or '.')
local res  = root .. '/resources/dyn_trade'

dofile(res .. '/server/trade_math.lua')
dofile(res .. '/server/trade_flow.lua')

local passed, failed = 0, 0
local function ok(cond, name, extra)
    if cond then passed = passed + 1
    else
        failed = failed + 1
        print(('  FAIL  %s%s'):format(name, extra and ('  -- ' .. extra) or ''))
    end
end
local function near(a, b, eps, name)
    ok(math.abs(a - b) < (eps or 1e-9), name, ('%s vs %s'):format(tostring(a), tostring(b)))
end

-- ============================== TradeMath ==============================
print('TradeMath')
ok(TradeMath.round2(1.005) == 1.0 or TradeMath.round2(1.005) == 1.01, '丸めが数値として返る（浮動小数の境界はどちらでもよい）')
near(TradeMath.round2(9.999), 10.00, 1e-9, '四捨五入される')
do
    local fee, net = TradeMath.feeFor(100, 0.03)
    near(fee, 3.00, 1e-9, '$100 の 3% は $3')
    near(net, 97.00, 1e-9, '残りは $97')
end
do
    local fee, net = TradeMath.feeFor(0, 0.03)
    near(fee, 0, 1e-9, '現金 0 なら手数料も 0（物々交換に課金しない）')
    near(net, 0, 1e-9, '純額も 0')
end

-- ============================== TradeFlow.finalize ==============================
print()
print('TradeFlow.finalize')

local function newPlayers()
    return {
        [1] = { items = { gold_nugget = 5 }, money = 200 },
        [2] = { items = { deerpelt = 3 }, money = 50 },
    }
end

local function makeAdapter(players, opts)
    opts = opts or {}
    return {
        getItemCount = function(src, item) return (players[src].items[item] or 0) end,
        getMoney = function(src) return players[src].money end,
        canCarry = function(src, item, qty)
            if opts.cannotCarry and opts.cannotCarry[src] then return false end
            return true
        end,
        addItem = function(src, item, qty)
            players[src].items[item] = (players[src].items[item] or 0) + qty
            return true
        end,
        removeItem = function(src, item, qty)
            if opts.failRemoveItem and opts.failRemoveItem(src, item) then return false end
            local have = players[src].items[item] or 0
            if have < qty then return false end
            players[src].items[item] = have - qty
            return true
        end,
        addMoney = function(src, amount)
            players[src].money = players[src].money + amount
            return true
        end,
        removeMoney = function(src, amount)
            if opts.failRemoveMoney and opts.failRemoveMoney(src) then return false end
            if players[src].money < amount then return false end
            players[src].money = players[src].money - amount
            return true
        end,
    }
end

local function session(cashA, itemsA, cashB, itemsB)
    return {
        a = { src = 1, offer = { items = itemsA, cash = cashA } },
        b = { src = 2, offer = { items = itemsB, cash = cashB } },
    }
end

print('正常系: 現物 x 現金の両方向トレード')
do
    local players = newPlayers()
    local a = makeAdapter(players)
    local s = session(100, { { item = 'gold_nugget', qty = 2 } }, 20, { { item = 'deerpelt', qty = 1 } })
    local result, err = TradeFlow.finalize({ adapter = a, feeRate = 0.03 }, s)

    ok(result ~= nil, '成立する', err)
    if result then
        near(result.feeA, 3.00, 1e-9, 'A の現金 $100 分の手数料は $3')
        near(result.feeB, 0.60, 1e-9, 'B の現金 $20 分の手数料は $0.6')
        near(result.netToB, 97.00, 1e-9, 'B が受け取る純額')
        near(result.netToA, 19.40, 1e-9, 'A が受け取る純額')
    end
    ok(players[1].items.gold_nugget == 3, 'A の gold_nugget が 5→3 に減る')
    ok(players[2].items.gold_nugget == 2, 'B が gold_nugget を 2 個受け取る')
    ok(players[2].items.deerpelt == 2, 'B の deerpelt が 3→2 に減る')
    ok(players[1].items.deerpelt == 1, 'A が deerpelt を 1 個受け取る')
    near(players[1].money, 200 - 100 + 19.40, 1e-9, 'A の所持金が正しく増減する')
    near(players[2].money, 50 - 20 + 97.00, 1e-9, 'B の所持金が正しく増減する')
end

print()
print('物々交換（現金 0）には手数料がかからない')
do
    local players = newPlayers()
    local a = makeAdapter(players)
    local s = session(0, { { item = 'gold_nugget', qty = 1 } }, 0, { { item = 'deerpelt', qty = 1 } })
    local result = TradeFlow.finalize({ adapter = a, feeRate = 0.03 }, s)
    ok(result ~= nil, '成立する')
    near(result.feeA, 0, 1e-9, '手数料 0')
    near(result.feeB, 0, 1e-9, '手数料 0')
    near(players[1].money, 200, 1e-9, 'A の所持金は変わらない')
    near(players[2].money, 50, 1e-9, 'B の所持金は変わらない')
end

print()
print('失敗系: どこで失敗しても両者の状態が開始前と完全に一致する')

local function snapshot(players)
    local out = {}
    for src, p in pairs(players) do
        out[src] = { money = p.money, items = {} }
        for item, qty in pairs(p.items) do out[src].items[item] = qty end
    end
    return out
end

local function assertUnchanged(before, players, label)
    for src, snap in pairs(before) do
        ok(players[src].money == snap.money, label .. ': ' .. src .. ' の所持金が変化していない')
        for item, qty in pairs(snap.items) do
            ok((players[src].items[item] or 0) == qty, label .. ': ' .. src .. ' の ' .. item .. ' 数量が変化していない')
        end
    end
end

do
    local players = newPlayers()
    local before = snapshot(players)
    local a = makeAdapter(players)
    -- A は gold_nugget を 5 しか持っていないのに 99 個提示する
    local s = session(0, { { item = 'gold_nugget', qty = 99 } }, 0, {})
    local result, err = TradeFlow.finalize({ adapter = a, feeRate = 0.03 }, s)
    ok(result == nil and err == 'item_short_a', '提示品不足で中止する（品目チェック段階、何も動かしていない）')
    assertUnchanged(before, players, '品目不足')
end

do
    local players = newPlayers()
    local before = snapshot(players)
    local a = makeAdapter(players)
    -- B の所持金は $50 なのに $9999 を提示させる
    local s = session(0, {}, 9999, {})
    local result, err = TradeFlow.finalize({ adapter = a, feeRate = 0.03 }, s)
    ok(result == nil and err == 'cash_short_b', '現金不足で中止する')
    assertUnchanged(before, players, '現金不足')
end

do
    local players = newPlayers()
    local before = snapshot(players)
    local a = makeAdapter(players, { cannotCarry = { [2] = true } })
    local s = session(0, { { item = 'gold_nugget', qty = 1 } }, 0, {})
    local result, err = TradeFlow.finalize({ adapter = a, feeRate = 0.03 }, s)
    ok(result == nil and err == 'cannot_carry_b', '受け取り側が持てない場合は中止する（まだ何も取り上げていない）')
    assertUnchanged(before, players, '所持上限')
end

do
    -- A の品は正常に取り上げられた後、B の品の取り上げが失敗するケース。
    -- これが「片方だけ取り上げて戻し忘れる」バグが一番起きやすい箇所
    local players = newPlayers()
    local before = snapshot(players)
    local a = makeAdapter(players, { failRemoveItem = function(src, item) return src == 2 and item == 'deerpelt' end })
    local s = session(0, { { item = 'gold_nugget', qty = 2 } }, 0, { { item = 'deerpelt', qty = 1 } })
    local result, err = TradeFlow.finalize({ adapter = a, feeRate = 0.03 }, s)
    ok(result == nil and err == 'remove_failed_b', 'B からの取り上げ失敗で中止する')
    assertUnchanged(before, players, 'B取り上げ失敗（A から取った分が正しく戻っているか）')
end

do
    -- 現物は両者から取り上げ済みだが、B の現金だけ取り上げに失敗するケース。
    -- 現物 2 人分 + A の現金、を全部戻せているかを見る
    local players = newPlayers()
    local before = snapshot(players)
    local a = makeAdapter(players, { failRemoveMoney = function(src) return src == 2 end })
    local s = session(50, { { item = 'gold_nugget', qty = 2 } }, 10, { { item = 'deerpelt', qty = 1 } })
    local result, err = TradeFlow.finalize({ adapter = a, feeRate = 0.03 }, s)
    ok(result == nil and err == 'cash_remove_failed_b', 'B からの現金取り上げ失敗で中止する')
    assertUnchanged(before, players, '現金取り上げ失敗（現物2人分+A現金が正しく戻っているか）')
end

print()
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
