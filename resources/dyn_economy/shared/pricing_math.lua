--[[
  価格式の純粋関数群（設計ドキュメント §4）

  このファイルは FiveM / RedM の API を一切参照しない。
  素の Lua で dofile() して単体テストできることを意図的な制約としている。
  （tests/run.lua がそうしている）
]]

local M = {}

-- 仮想在庫がこれ以下にならない下限。0 に触れると (S0/S)^e が発散する
M.MIN_STOCK = 1e-3

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
M.clamp = clamp

function M.round(v, step)
    step = step or 0.01
    if step <= 0 then return v end
    return math.floor(v / step + 0.5) * step
end

--- 仮想在庫の均衡回帰（§4.3）
--- S(t+dt) = S0 + (S(t) - S0) * 2^(-dt / halfLife)
function M.decayStock(stock, targetStock, dtMinutes, halfLifeMin)
    if not halfLifeMin or halfLifeMin <= 0 or not dtMinutes or dtMinutes <= 0 then
        return stock
    end
    local k = 2 ^ (-dtMinutes / halfLifeMin)
    return targetStock + (stock - targetStock) * k
end

--- クランプ前の単価（§4.1）
function M.rawUnitPrice(p0, targetStock, stock, elasticity)
    if stock < M.MIN_STOCK then stock = M.MIN_STOCK end
    if elasticity <= 0 then return p0 end
    return p0 * (targetStock / stock) ^ elasticity
end

--- 単価が p0 * mult になる在庫量。p(x) は x について単調減少なので、
--- mult が大きいほど小さい x に対応する。
function M.stockAtMult(targetStock, elasticity, mult)
    return targetStock * mult ^ (-1 / elasticity)
end

--- 曲線区間の定積分 ∫[a,b] p0 * (S0/x)^e dx
local function curveIntegral(p0, targetStock, elasticity, a, b)
    if b <= a then return 0 end
    if math.abs(elasticity - 1) < 1e-9 then
        return p0 * targetStock * (math.log(b) - math.log(a))
    end
    local c = p0 * (targetStock ^ elasticity) / (1 - elasticity)
    return c * (b ^ (1 - elasticity) - a ^ (1 - elasticity))
end

--- 上下限クランプ込みの定積分（§4.2 + §4.1 のクランプ）
---
--- 単価を数量方向に積分するので、まとめ売りは自動的に単価が下がる。
--- クランプは「積分してから頭を押さえる」のではなく、価格が上下限に張り付く
--- 在庫区間で積分を分割して厳密に計算する。分割点は閉形式で出る:
---   p(x) = p0 * mult  ⟺  x = S0 * mult^(-1/e)
function M.integrateClamped(p0, targetStock, elasticity, minMult, maxMult, a, b)
    if minMult > maxMult then minMult, maxMult = maxMult, minMult end
    if a < M.MIN_STOCK then a = M.MIN_STOCK end
    if b < a then b = a end
    if b <= a then return 0 end
    -- 弾力性 0 は「需給で動かない品」。固定価格として扱う
    if elasticity <= 0 then return p0 * (b - a) end

    local xHigh = M.stockAtMult(targetStock, elasticity, maxMult) -- これ未満は上限に張り付く
    local xLow  = M.stockAtMult(targetStock, elasticity, minMult) -- これ超過は下限に張り付く
    local total = 0

    local hi = math.min(b, xHigh)
    if hi > a then total = total + p0 * maxMult * (hi - a) end

    local c1, c2 = math.max(a, xHigh), math.min(b, xLow)
    if c2 > c1 then total = total + curveIntegral(p0, targetStock, elasticity, c1, c2) end

    local lo = math.max(a, xLow)
    if b > lo then total = total + p0 * minMult * (b - lo) end

    return total
end

--- プレイヤーが NPC に qty 個売ったときの総額（税抜き）。在庫は増える方向。
function M.totalSell(p0, targetStock, elasticity, minMult, maxMult, stock, qty)
    if qty <= 0 then return 0 end
    return M.integrateClamped(p0, targetStock, elasticity, minMult, maxMult, stock, stock + qty)
end

--- プレイヤーが NPC から qty 個買ったときの総額（税抜き）。在庫は減る方向。
--- 在庫が下限を割る分は上限価格で数える（数量は必ず保存する）。
function M.totalBuy(p0, targetStock, elasticity, minMult, maxMult, stock, qty)
    if qty <= 0 then return 0 end
    local a = stock - qty
    local extra = 0
    if a < M.MIN_STOCK then
        extra = (M.MIN_STOCK - a) * p0 * maxMult
        a = M.MIN_STOCK
    end
    return M.integrateClamped(p0, targetStock, elasticity, minMult, maxMult, a, stock) + extra
end

--- スプレッドから対称な税率を出す（§9.1）
--- 販売価格 / 買取価格 = (1 + t) / (1 - t) = 1 / (1 - spread) を満たす t
function M.taxFromSpread(spread)
    if not spread or spread <= 0 then return 0 end
    if spread >= 1 then spread = 0.99 end
    return spread / (2 - spread)
end

--- レシピ原価から実効的な下限倍率を出す（§5.3）
--- 下限を min_mult ではなく「原価 × マージン」に引き上げることで、
--- 素材を買って作って売ると赤字、という状態を構造的に潰す。
function M.effectiveMinMult(p0, minMult, maxMult, matCost, craftMargin)
    if not matCost or matCost <= 0 or p0 <= 0 then return minMult end
    local floorMult = (matCost * (craftMargin or 1.0)) / p0
    return clamp(math.max(minMult, floorMult), 0, maxMult)
end

_G.DynMath = M
return M
