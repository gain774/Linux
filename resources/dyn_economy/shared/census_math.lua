--[[
  資産センサスの統計（設計ドキュメント §6.4）

  外れ値は「除外するが、無かったことにはしない」。
    - 中央値などの統計からは除外する（1 人の大富豪に物価を動かされないため）
    - 総額には算入する（存在する金は存在する）
    - 一覧は運営に見せる（切り分けは人間がやる）

  平均と標準偏差ではなく中央値と MAD を使う。平均と標準偏差は外れ値自身に
  引きずられるので、大富豪が 1 人いるだけで基準が壊れる。

  FiveM にも DB にも依存しない。素の Lua でテストできる。
]]
CensusMath = {}

-- MAD を正規分布の標準偏差と同じ尺度に揃える定数
CensusMath.MAD_SCALE = 1.4826

local function sortedCopy(values)
    local out = {}
    for i, v in ipairs(values) do out[i] = v end
    table.sort(out)
    return out
end

--- 中央値。空なら nil
function CensusMath.median(values)
    local n = #values
    if n == 0 then return nil end
    local s = sortedCopy(values)
    local mid = (n + 1) / 2
    if n % 2 == 1 then return s[mid] end
    return (s[mid - 0.5] + s[mid + 0.5]) / 2
end

--- 分位数（線形補間）。p は 0〜1
function CensusMath.percentile(values, p)
    local n = #values
    if n == 0 then return nil end
    if n == 1 then return values[1] end
    local s = sortedCopy(values)
    local pos = 1 + (n - 1) * math.max(0, math.min(1, p))
    local lo = math.floor(pos)
    local hi = math.ceil(pos)
    if lo == hi then return s[lo] end
    return s[lo] + (s[hi] - s[lo]) * (pos - lo)
end

--- 中央絶対偏差
function CensusMath.mad(values, med)
    if #values == 0 then return nil end
    med = med or CensusMath.median(values)
    local devs = {}
    for i, v in ipairs(values) do devs[i] = math.abs(v - med) end
    return CensusMath.median(devs)
end

--[[
  センサス 1 回分の集計。

  samples = { { id = 'char1', amount = 1234.5, active = true }, ... }
  opts    = { outlierMAD = 5.0 }

  戻り値:
    total      … 全員の合計（外れ値も含む。これがマネーサプライ）
    n          … 全員の人数
    activeN    … 統計の対象になった人数（アクティブかつ外れ値でない）
    median / mad / p90 / p99 … アクティブかつ外れ値を除いた統計
    threshold  … 外れ値の判定境界
    outliers   … { { id, amount, madScore }, ... } 金額の大きい順
]]
function CensusMath.summarize(samples, opts)
    opts = opts or {}
    local k = opts.outlierMAD or 5.0

    local total, n = 0, 0
    local activeAmounts = {}
    for _, s in ipairs(samples or {}) do
        local amount = tonumber(s.amount) or 0
        total = total + amount
        n = n + 1
        if s.active then activeAmounts[#activeAmounts + 1] = amount end
    end

    local result = {
        total = total, n = n, activeN = 0,
        median = nil, mad = nil, p90 = nil, p99 = nil,
        threshold = nil, outliers = {},
    }
    if #activeAmounts == 0 then return result end

    local med = CensusMath.median(activeAmounts)
    local mad = CensusMath.mad(activeAmounts, med)
    result.median = med
    result.mad    = mad

    -- MAD が 0（過半数が同額）だと閾値が中央値そのものになり、
    -- わずかでも多い人が全員外れ値になってしまう。その場合は外れ値なしとして扱う。
    local threshold = (mad and mad > 0) and (med + k * mad * CensusMath.MAD_SCALE) or nil
    result.threshold = threshold

    local inliers = {}
    for _, s in ipairs(samples or {}) do
        if s.active then
            local amount = tonumber(s.amount) or 0
            if threshold and amount > threshold then
                result.outliers[#result.outliers + 1] = {
                    id = s.id, amount = amount,
                    madScore = (amount - med) / (mad * CensusMath.MAD_SCALE),
                }
            else
                inliers[#inliers + 1] = amount
            end
        end
    end

    table.sort(result.outliers, function(a, b) return a.amount > b.amount end)

    result.activeN = #inliers
    if #inliers > 0 then
        -- 外れ値を抜いたうえで統計を取り直す
        result.median = CensusMath.median(inliers)
        result.mad    = CensusMath.mad(inliers, result.median)
        result.p90    = CensusMath.percentile(inliers, 0.90)
        result.p99    = CensusMath.percentile(inliers, 0.99)
    end

    return result
end

--[[
  総額の健全性チェック（§6.4）。

  expected = 前回の総額 + Mod 経由の金の純増
  ズレが大きいということは、Mod の外で金が出入りしている（管理者の付与、
  他スクリプト、複製バグ）。そのまま較正すると、その結果を「正常な経済成長」と
  誤認して全アイテムを値上げしてしまうので、疑わしい時点で止める。
]]
function CensusMath.drift(actual, expected)
    actual   = tonumber(actual) or 0
    expected = tonumber(expected) or 0
    return math.abs(actual - expected) / math.max(math.abs(expected), 1)
end

function CensusMath.isDrifting(actual, expected, tolerance)
    return CensusMath.drift(actual, expected) > (tonumber(tolerance) or 0.25)
end

_G.CensusMath = CensusMath
return CensusMath
