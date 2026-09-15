--[[
  目標成長曲線ターゲティングの純粋関数（設計ドキュメント §7、既定 OFF）。
  FiveM にも DB にも依存しない。CensusMath.median を使うので、
  fxmanifest ではこれより先に census_math.lua を読み込む。
]]
ProgressionMath = {}

--[[
  曲線の点と点の間を log-log 線形補間する。成長は逓減するのが自然なので、
  直線補間より素直に繋がる（§7.1）。両端は外挿せず、端点の値を使う。
  途中の区間で day や value が 0 以下（対数を取れない）場合だけ、
  その区間限定で通常の線形補間にフォールバックする。

  @param curve { { day = n, value = v }, ... }（順不同でよい。内部でソートする）
]]
function ProgressionMath.curveValue(curve, day)
    if type(curve) ~= 'table' or #curve == 0 or not day or day <= 0 then return nil end

    local pts = {}
    for _, p in ipairs(curve) do pts[#pts + 1] = p end
    table.sort(pts, function(a, b) return a.day < b.day end)

    if day <= pts[1].day then return pts[1].value end
    if day >= pts[#pts].day then return pts[#pts].value end

    for i = 1, #pts - 1 do
        local a, b = pts[i], pts[i + 1]
        if day >= a.day and day <= b.day then
            if a.day <= 0 or a.value <= 0 or b.value <= 0 or b.day == a.day then
                local t = (b.day == a.day) and 0 or (day - a.day) / (b.day - a.day)
                return a.value + t * (b.value - a.value)
            end
            local lx1, lx2 = math.log(a.day), math.log(b.day)
            local ly1, ly2 = math.log(a.value), math.log(b.value)
            local t = (math.log(day) - lx1) / (lx2 - lx1)
            return math.exp(ly1 + t * (ly2 - ly1))
        end
    end
    return nil
end

--- 曲線の起点（一番小さい day の点の値）。§6.3 の startingMode='curve' が
--- 「day=0 相当」として使う。曲線は day<=先頭点で先頭点の値を返す仕様なので、
--- これは実質 curveValue(curve, 先頭のday) と同じだが、意図を名前で示す
function ProgressionMath.curveStart(curve)
    if type(curve) ~= 'table' or #curve == 0 then return nil end
    local minDay, minVal
    for _, p in ipairs(curve) do
        if not minDay or p.day < minDay then minDay, minVal = p.day, p.value end
    end
    return minVal
end

--- 経過「日」を basis に応じて決める（§7.1）
function ProgressionMath.dayOf(basis, hoursPerDay, playtimeHours, calendarDays)
    if basis == 'calendar' then return calendarDays end
    hoursPerDay = hoursPerDay or 2.0
    if hoursPerDay <= 0 then return nil end
    return (playtimeHours or 0) / hoursPerDay
end

--- 在籍度バケット（§7.2）
function ProgressionMath.bucketOf(day)
    if not day then return nil end
    if day <= 7 then return 'early' end
    if day <= 30 then return 'mid' end
    return 'late'
end

--- minSamples 未満のバケットを取り除く（標本が薄いと暴れるため）
function ProgressionMath.filterMinSamples(buckets, minSamples)
    local out = {}
    for name, b in pairs(buckets or {}) do
        if b.values and #b.values >= (minSamples or 5) then out[name] = b end
    end
    return out
end

--[[
  重み付き対数平均誤差 E（§7.3）。バケットごとの中央値と目標の比を対数で扱う
  （「2倍稼ぎすぎ」と「半分しか稼げていない」を対称に扱うため）。

  @param buckets { early = { values = {...}, avgDay = n }, mid = ..., late = ... }
  @param curve   目標曲線
  @param weights { early = 2.0, mid = 1.0, late = 0.5 }
]]
function ProgressionMath.evaluate(buckets, curve, weights)
    local sumW, sumWlnr = 0, 0
    local details = {}
    for name, b in pairs(buckets or {}) do
        if b.values and #b.values > 0 then
            local median = CensusMath.median(b.values)
            local target = ProgressionMath.curveValue(curve, b.avgDay)
            if target and target > 0 and median and median > 0 then
                local ratio = median / target
                local w = (weights and weights[name]) or 1.0
                local n = #b.values
                sumW = sumW + w * n
                sumWlnr = sumWlnr + w * n * math.log(ratio)
                details[name] = { n = n, median = median, target = target, ratio = ratio, weight = w }
            end
        end
    end
    if sumW <= 0 then return nil end
    return { E = sumWlnr / sumW, details = details }
end

function ProgressionMath.isInBand(E, tolerance)
    if not E then return true end
    return math.abs(E) <= math.log(1 + (tolerance or 0.15))
end

--[[
  income_mult の更新（§7.3）。1 日 ±maxDailyAdj でクランプしたうえで、
  絶対域 [0.50, 2.00] を超えない。
]]
function ProgressionMath.updateIncomeMult(prevMult, E, Kp, maxDailyAdj)
    prevMult = prevMult or 1.0
    if not E then return prevMult end
    Kp = Kp or 0.5
    maxDailyAdj = maxDailyAdj or 0.03

    local raw = prevMult * math.exp(-Kp * E)
    local lo, hi = prevMult * (1 - maxDailyAdj), prevMult * (1 + maxDailyAdj)
    if raw < lo then raw = lo elseif raw > hi then raw = hi end
    if raw < 0.50 then raw = 0.50 elseif raw > 2.00 then raw = 2.00 end
    return raw
end

--[[
  §7.6 到達可能性の検査。Mod 経由の収入がそのプレイヤーの総収入増加分の
  どれだけを占めるか。coverage が低いバケットが続くなら、値を動かしても
  目標に届かないというサイン（安全装置。機能ではない）。
]]
function ProgressionMath.coverage(modIncome, totalIncomeDelta)
    if not totalIncomeDelta or totalIncomeDelta <= 0 then return nil end
    local c = (modIncome or 0) / totalIncomeDelta
    if c < 0 then c = 0 elseif c > 1 then c = 1 end
    return c
end
