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
