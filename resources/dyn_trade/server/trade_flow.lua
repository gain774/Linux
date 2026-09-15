--[[
  個人間取引の決済フロー（dyn_economy_bridge/server/txflow.lua と同じ方針）。

  FiveM にも VORP にも依存しない。adapter を注入して使うので、素の Lua で
  「途中で失敗したときにちゃんと全部戻るか」までテストできる。

  deps = {
    adapter = { getItemCount, getMoney, canCarry, addItem, removeItem, addMoney, removeMoney },
    feeRate = number,
  }
  session = {
    a = { src = ..., offer = { items = {{item,qty},...}, cash = number } },
    b = { src = ..., offer = { items = {...}, cash = number } },
  }
]]

local F = {}

--[[
  順序の理由（安全設計）:
    1. 現在の所持を再確認する。提示してから使い込んだ／落とした可能性があるため。
    2. 受け取る側が持てるか確認する。
    3. 両者から先に全部取り上げる。片方でも取り上げに失敗したら、その場で
       既に取り上げた分を全部返して中止する（片手落ちを残さない）。
    4. ここまで来たら両者から取り上げ済み。品物 → 現金の順で相手に渡す。
       渡す段階はほぼ失敗しない操作（取り上げた自分の在庫に足すだけ）なので、
       ここで失敗しても検出・回復する手段を増やすより「渡し切る」方を優先する。
]]
function F.finalize(deps, session)
    local a = deps.adapter
    local A, B = session.a, session.b

    for _, e in ipairs(A.offer.items) do
        if a.getItemCount(A.src, e.item) < e.qty then return nil, 'item_short_a' end
    end
    for _, e in ipairs(B.offer.items) do
        if a.getItemCount(B.src, e.item) < e.qty then return nil, 'item_short_b' end
    end
    if A.offer.cash > a.getMoney(A.src) then return nil, 'cash_short_a' end
    if B.offer.cash > a.getMoney(B.src) then return nil, 'cash_short_b' end

    for _, e in ipairs(B.offer.items) do
        if not a.canCarry(A.src, e.item, e.qty) then return nil, 'cannot_carry_a' end
    end
    for _, e in ipairs(A.offer.items) do
        if not a.canCarry(B.src, e.item, e.qty) then return nil, 'cannot_carry_b' end
    end

    local takenA, takenB = {}, {}
    for _, e in ipairs(A.offer.items) do
        if not a.removeItem(A.src, e.item, e.qty) then
            for _, t in ipairs(takenA) do a.addItem(A.src, t.item, t.qty) end
            return nil, 'remove_failed_a'
        end
        takenA[#takenA + 1] = e
    end
    for _, e in ipairs(B.offer.items) do
        if not a.removeItem(B.src, e.item, e.qty) then
            for _, t in ipairs(takenA) do a.addItem(A.src, t.item, t.qty) end
            for _, t in ipairs(takenB) do a.addItem(B.src, t.item, t.qty) end
            return nil, 'remove_failed_b'
        end
        takenB[#takenB + 1] = e
    end

    --[[
      注意: `cond and f() or true` は f() が正当に false を返し得る場合は使えない
      （false or true が true になり、失敗を検出できなくなる）。必ず if で書く。
    ]]
    local cashTakenA = true
    if A.offer.cash > 0 then
        cashTakenA = a.removeMoney(A.src, A.offer.cash)
    end
    if not cashTakenA then
        for _, t in ipairs(takenA) do a.addItem(A.src, t.item, t.qty) end
        for _, t in ipairs(takenB) do a.addItem(B.src, t.item, t.qty) end
        return nil, 'cash_remove_failed_a'
    end

    local cashTakenB = true
    if B.offer.cash > 0 then
        cashTakenB = a.removeMoney(B.src, B.offer.cash)
    end
    if not cashTakenB then
        for _, t in ipairs(takenA) do a.addItem(A.src, t.item, t.qty) end
        for _, t in ipairs(takenB) do a.addItem(B.src, t.item, t.qty) end
        if A.offer.cash > 0 then a.addMoney(A.src, A.offer.cash) end
        return nil, 'cash_remove_failed_b'
    end

    for _, e in ipairs(B.offer.items) do a.addItem(A.src, e.item, e.qty) end
    for _, e in ipairs(A.offer.items) do a.addItem(B.src, e.item, e.qty) end

    local feeA, netToB = TradeMath.feeFor(A.offer.cash, deps.feeRate)
    local feeB, netToA = TradeMath.feeFor(B.offer.cash, deps.feeRate)
    if netToB > 0 then a.addMoney(B.src, netToB) end
    if netToA > 0 then a.addMoney(A.src, netToA) end

    return { feeA = feeA, feeB = feeB, netToA = netToA, netToB = netToB }
end

_G.TradeFlow = F
return F
