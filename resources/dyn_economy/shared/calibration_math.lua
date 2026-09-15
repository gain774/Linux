--[[
  自動較正の純粋関数（設計ドキュメント §6.2〜§6.7）。

  FiveM にも DB にも依存しない。DB から集めた数値を渡すと、
  「次のスケール・倍率・価格指数をいくつにするか」だけを返す。
  日次ジョブ（server/calibration.lua）が DB とのやり取り・適用・監査ログを持つ。
]]
CalibrationMath = {}

--[[
  §6.2 A: 既存サーバーへの後乗せ。固定価格表 P_existing[i] と price_index[i] の
  比の中央値から currency_scale を逆算する。

  比の分布が広すぎる場合（IQR > 中央値の50%）は自動適用せず、外れ値の一覧を返す
  だけにする（price_index がそのサーバーの価値観と合っていないサイン）。

  @param existingPrices { item = price, ... }
  @param priceIndex      { item = index, ... }
  @return table|nil { scale, samples, iqrRatio, wide, outliers = {{item,existing,expected,mult}} }
]]
function CalibrationMath.bootstrapFromExisting(existingPrices, priceIndex)
    if type(existingPrices) ~= 'table' or type(priceIndex) ~= 'table' then return nil, 'bad_argument' end

    local ratios, values = {}, {}
    for item, price in pairs(existingPrices) do
        local idx = priceIndex[item]
        if idx and idx > 0 and price and price > 0 then
            local ratio = price / idx
            ratios[#ratios + 1] = { item = item, existing = price, index = idx, ratio = ratio }
            values[#values + 1] = ratio
        end
    end
    if #values == 0 then return nil, 'no_matching_items' end

    local med = CensusMath.median(values)
    local p25 = CensusMath.percentile(values, 25)
    local p75 = CensusMath.percentile(values, 75)
    local iqr = p75 - p25
    local iqrRatio = (med and med > 0) and (iqr / med) or nil
    local wide = iqrRatio ~= nil and iqrRatio > 0.5

    local outliers = {}
    for _, r in ipairs(ratios) do
        local expected = med * r.index
        local mult = expected > 0 and (r.existing / expected) or nil
        if mult and (mult > 1.5 or mult < (1 / 1.5)) then
            outliers[#outliers + 1] = { item = r.item, existing = r.existing, expected = expected, mult = mult }
        end
    end
    table.sort(outliers, function(a, b) return math.abs(math.log(a.mult)) > math.abs(math.log(b.mult)) end)

    return { scale = med, samples = #values, iqrRatio = iqrRatio, wide = wide, outliers = outliers }
end

--[[
  §6.3 新規キャラの開始所持金。
  @param mode 'basket' | 'curve' | 'fixed'
  @param opts { baskets, basketPrice, curveDay0, fixed }
]]
function CalibrationMath.startingCash(mode, opts)
    opts = opts or {}
    if mode == 'fixed' then return tonumber(opts.fixed) or 0 end
    if mode == 'curve' then return tonumber(opts.curveDay0) or 0 end
    -- 'basket'（既定）
    local baskets = tonumber(opts.baskets) or 1
    local price   = tonumber(opts.basketPrice)
    if not price or price <= 0 then return 0 end
    return baskets * price
end

--[[
  §6.5 所持金分布への追従。購買力（所持金中央値 / バスケット価格）を
  target に近づける方向へ currency_scale を動かす。1 日 ±dailyClamp にクランプ。
]]
function CalibrationMath.purchasingPowerScale(prevScale, moneyMedian, basketPrice, targetPP, k, dailyClamp)
    prevScale = tonumber(prevScale) or 1.0
    if not moneyMedian or not basketPrice or basketPrice <= 0 then return prevScale end
    if not targetPP or targetPP <= 0 then return prevScale end

    local pp = moneyMedian / basketPrice
    local newScale = prevScale * (1 + (k or 0.15) * (pp / targetPP - 1))
    local clamp = dailyClamp or 0.02
    local lo, hi = prevScale * (1 - clamp), prevScale * (1 + clamp)
    if newScale < lo then newScale = lo end
    if newScale > hi then newScale = hi end
    return newScale
end

--[[
  §6.5 の非対称カップリング。wealth_mult（購買力追従が動かす倍率）をそのまま
  両方向にかけると「相対価格は変わらないので無意味」になる。NPC 販売（プレイヤーが
  買う＝金のシンク）は完全連動（coupling=1.0）、NPC 買取（プレイヤーが売る＝
  金のソース）は連動を弱める（coupling=β、既定0.5）ことで、サーバーが豊かに
  なるほど「買うものは高くなるが稼ぎは同じだけ上がらない」効果を作る。
  wealth_mult^coupling という指数のかけ方にしているのは、wealth_mult が 1.0 から
  ずれた分だけを coupling 倍に弱めて伝えるため（wealth_mult=1.2, coupling=0.5 なら
  1.2^0.5 ≈ 1.095 と、変化量そのものが弱まる）。
]]
function CalibrationMath.wealthCoupling(wealthMult, coupling)
    wealthMult = tonumber(wealthMult)
    if not wealthMult or wealthMult <= 0 then return 1.0 end
    return wealthMult ^ (coupling or 1.0)
end

--[[
  §6.6 収集効率アンカー。品目の実測時給が目標バンドから外れたら price_index を
  1 日 ±maxDailyPct まで補正する。
]]
function CalibrationMath.yieldAdjust(priceIndex, hourly, bandLow, bandHigh, maxDailyPct)
    priceIndex = tonumber(priceIndex)
    if not priceIndex or priceIndex <= 0 or not hourly or hourly <= 0 then return priceIndex end
    maxDailyPct = maxDailyPct or 0.03

    local mult = 1.0
    if bandHigh and hourly > bandHigh then
        mult = math.max(1 - maxDailyPct, bandHigh / hourly)
    elseif bandLow and hourly < bandLow then
        mult = math.min(1 + maxDailyPct, bandLow / hourly)
    end
    return priceIndex * mult
end

--- その日の実測中央時給から目標バンド（下限・上限）を決める
function CalibrationMath.yieldTargetBand(medianHourly, loMult, hiMult)
    if not medianHourly or medianHourly <= 0 then return nil, nil end
    return medianHourly * (loMult or 0.7), medianHourly * (hiMult or 1.3)
end

--[[
  §6.7 マネーサプライの PI 制御。金の総量の日次成長率を目標に寄せる。
  @return globalMultBuy, globalMultSell, newIntegral
]]
function CalibrationMath.moneySupplyPI(prevIntegral, growthRate, targetGrowth, Kp, Ki)
    prevIntegral = tonumber(prevIntegral) or 0
    growthRate   = tonumber(growthRate) or 0
    targetGrowth = tonumber(targetGrowth) or 0
    Kp = Kp or 2.0
    Ki = Ki or 0.5

    local e = growthRate - targetGrowth
    local integral = prevIntegral + e
    if integral > 0.5 then integral = 0.5 elseif integral < -0.5 then integral = -0.5 end

    local adj = Kp * e + Ki * integral
    local function clamp(v) if v < 0.70 then return 0.70 elseif v > 1.30 then return 1.30 else return v end end
    local globalBuy  = clamp(1 - adj)
    local globalSell = clamp(1 + adj)
    return globalBuy, globalSell, integral
end

--- 日次成長率 g = (total(t) - total(t-1)) / total(t-1)
function CalibrationMath.dailyGrowth(totalNow, totalPrev)
    totalNow = tonumber(totalNow)
    totalPrev = tonumber(totalPrev)
    if not totalNow or not totalPrev or totalPrev <= 0 then return nil end
    return (totalNow - totalPrev) / totalPrev
end
