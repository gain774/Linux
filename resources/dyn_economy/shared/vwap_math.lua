--[[
  個人間取引（dyn_trade など）から届く実売買価格を、時間窓つきの VWAP（出来高加重平均単価）に
  まとめるための純粋関数（§8.2 相当）。FiveM/VORP に依存しない。

  単価に分解する側（「片方が現金のみ・もう片方が単一品目のみ」の判定）は取引の仲介元
  （dyn_trade/server/trade_math.lua の TradeMath.deriveUnitPrice）の責務。ここでは
  既に (item, qty, unitPrice) になったサンプルを集計するだけにして、dyn_economy が
  取引仲介側のデータ構造（session）を知らずに済むようにする。
]]

local M = {}

--- t 以前のサンプルを刈り取ってから追加する（in-place ではなく新しい配列を返す）
function M.addSample(samples, sample, nowT, windowSec)
    local kept = {}
    for _, s in ipairs(samples) do
        if nowT - s.t <= windowSec then kept[#kept + 1] = s end
    end
    kept[#kept + 1] = sample
    return kept
end

--- 出来高加重平均単価。サンプルが無ければ nil
function M.vwap(samples)
    local sumQtyPrice, sumQty = 0, 0
    for _, s in ipairs(samples) do
        sumQtyPrice = sumQtyPrice + s.unitPrice * s.qty
        sumQty = sumQty + s.qty
    end
    if sumQty <= 0 then return nil end
    return sumQtyPrice / sumQty, sumQty, #samples
end

_G.DynVwapMath = M
return M
