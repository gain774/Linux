--[[
  個人間取引の純粋関数。FiveM にも DB にも依存しないので単体テストできる
  （dyn_economy/shared/pricing_math.lua と同じ方針）。
]]
TradeMath = {}

function TradeMath.round2(v)
    return math.floor((tonumber(v) or 0) * 100 + 0.5) / 100
end

--[[
  現金提示額から手数料を引いた、相手に渡る純額を計算する。
  物々交換（cash = 0）には手数料をかけない。
]]
function TradeMath.feeFor(cash, feeRate)
    cash = tonumber(cash) or 0
    if cash <= 0 then return 0, 0 end
    local fee = TradeMath.round2(cash * (tonumber(feeRate) or 0))
    local net = TradeMath.round2(cash - fee)
    return fee, net
end

--[[
  dyn_economy へ参考価格として渡せる形（§8.2）に分解できる取引だけ単価を返す。
  「片方が現金のみ、もう片方が単一品目のみ」でなければ nil
  （複数品目・現金の両建ては単価に分解できないので記録しない）。

  session = { a = { offer = { items = {...}, cash = n } }, b = { offer = {...} } }
]]
function TradeMath.deriveUnitPrice(session)
    local a, b = session.a.offer, session.b.offer

    local function isCashOnly(side)   return #side.items == 0 and side.cash > 0 end
    local function isSingleItem(side) return #side.items == 1 and side.cash == 0 end

    local buyer, seller
    if isCashOnly(a) and isSingleItem(b) then
        buyer, seller = a, b
    elseif isCashOnly(b) and isSingleItem(a) then
        buyer, seller = b, a
    else
        return nil
    end

    local e = seller.items[1]
    if not e or not e.qty or e.qty <= 0 then return nil end

    return e.item, e.qty, buyer.cash / e.qty
end
