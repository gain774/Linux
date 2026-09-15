--[[
  個人間取引（P2P）の実売買価格を参考値として保持する（§8.2）。

  仮想在庫・基準価格には一切触らない。あくまで「NPC 買取 1.20 / 実勢 1.85」のような
  UI 表示と、任意（既定オフ）の緩やかな基準価格補正の入力にするだけ。
  記録はサーバーのメモリ上だけで、DB 永続化も再起動をまたいだ保持もしない
  （§8.2 の VWAP は「直近 24h」が定義そのものなので、再起動で空になっても実害は薄い）。
]]
DynPlayerRef = {}

local samples = {}   -- item -> { {t, item, qty, unitPrice}, ... }

local function windowSec()
    return (Config.PlayerRef and Config.PlayerRef.windowHours or 24) * 3600
end

--- 個人間取引の 1 件を記録する。qty <= 0 や unitPrice <= 0 は無視する
function DynPlayerRef.record(item, qty, unitPrice)
    if not Config.PlayerRef or not Config.PlayerRef.enabled then return false end
    if not item or not qty or qty <= 0 or not unitPrice or unitPrice <= 0 then return false end

    local t = os.time()
    local list = samples[item] or {}
    samples[item] = DynVwapMath.addSample(list, { t = t, item = item, qty = qty, unitPrice = unitPrice }, t, windowSec())
    return true
end

--- item の直近ウィンドウの VWAP。記録が無ければ vwap=nil
function DynPlayerRef.get(item)
    local list = samples[item]
    if not list or #list == 0 then return { vwap = nil, qty = 0, samples = 0 } end
    -- 参照するたびに窓外を刈る（record が来ない品目でも古いサンプルを残さない）
    local t = os.time()
    local kept = {}
    for _, s in ipairs(samples[item]) do
        if t - s.t <= windowSec() then kept[#kept + 1] = s end
    end
    samples[item] = kept
    if #kept == 0 then return { vwap = nil, qty = 0, samples = 0 } end
    local vwap, qty, n = DynVwapMath.vwap(kept)
    return { vwap = vwap, qty = qty, samples = n }
end

--- テスト・診断用に全消去
function DynPlayerRef.reset()
    samples = {}
end
