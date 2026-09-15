--[[
  自動較正の日次ジョブ（§6.2〜§6.7・§6.9）。

  数式は shared/calibration_math.lua（純粋関数）にある。ここは DB から材料を
  集めて渡し、結果を適用し、監査ログを残すだけ。

  安全装置（§6.9）:
  - Config.Calibration.enabled がキルスイッチ。false ならこのファイルは何もしない
  - DynCensus.isHeld() が true の間（資産センサスの drift 異常）は §6.5〜6.7 を止める
    （§4 の需給変動は止めない — dyn_economy 本体の仕事なのでここには関係ない）
  - 全て 1 日 1 回・小刻み・クランプ（wealth ±2%/日、yield ±3%/日、global 0.70〜1.30）
  - dyn_items.pinned の品目は §6.6 の対象外
  - 標本下限（yieldMinUniqueSellers / yieldMinPlaytimeHours）未満は据え置き
]]
DynCalibration = {}

local function warn(fmt, ...) print(('^3[dyn_economy] ' .. fmt .. '^0'):format(...)) end
local function info(fmt, ...) print(('[dyn_economy] ' .. fmt):format(...)) end

-- ============================== §6.2 bootstrap（後乗せ較正） ==============================

--- 既存の固定価格表から currency_scale を逆算する（ドライラン。適用はしない）
function DynCalibration.bootstrapDryRun(existingPrices)
    local index = {}
    for name, it in pairs(DynState.all()) do index[name] = it.priceIndex end
    return CalibrationMath.bootstrapFromExisting(existingPrices, index)
end

function DynCalibration.applyBootstrapScale(scale)
    if not scale or scale <= 0 then return false end
    DynState.setEcon('currency_scale', scale)
    return true
end

-- ============================== §6.3 新規キャラの開始所持金 ==============================

--- そのサーバーの物価から新規キャラの開始所持金を決める。呼ぶのは
--- dyn_economy_bridge（VORP の新規キャラ作成イベントを拾う側）
function DynCalibration.startingCash()
    local cfg = Config.Economy or { startingMode = 'basket', startingBaskets = 1.5 }
    local basketPrice
    if cfg.startingMode == 'basket' then
        local total, n = 0, 0
        for _, item in ipairs(Config.Census.basket or {}) do
            local q = DynPricing.quote(item, 1, 'buy')
            if q then total = total + q.priceNow; n = n + 1 end
        end
        basketPrice = n > 0 and total or nil
    end
    return CalibrationMath.startingCash(cfg.startingMode, {
        baskets = cfg.startingBaskets, basketPrice = basketPrice, fixed = cfg.startingFixed,
        -- curve モード（§7 併用）は progression.lua が導入され次第、day0 の値を渡す
        curveDay0 = (_G.DynProgression and DynProgression.curveDay0()) or nil,
    })
end

-- ============================== §6.5 所持金分布への追従 ==============================

local function runWealth(snapshot)
    if not Config.Calibration.wealth then return end
    if not snapshot.median or not snapshot.basket or snapshot.basket <= 0 then return end

    local target = DynState.econOr('pp_target', nil)
    if not target then
        -- 初回はこの時点の購買力を「維持したい基準」として記録するだけ（動かさない）
        target = snapshot.median / snapshot.basket
        DynState.setEcon('pp_target', target)
        info('所持金分布への追従: 購買力の目標値を %.4f で初期化しました', target)
        return
    end

    local prev = DynState.econ('wealth_mult')
    local next_ = CalibrationMath.purchasingPowerScale(
        prev, snapshot.median, snapshot.basket, target,
        Config.Calibration.wealthK, Config.Calibration.wealthDailyClamp)
    if math.abs(next_ - prev) > 1e-9 then
        DynState.setEcon('wealth_mult', next_)
        info('所持金分布への追従: wealth_mult %.6f -> %.6f（購買力 %.2f / 目標 %.2f）',
            prev, next_, snapshot.median / snapshot.basket, target)
    end
end

-- ============================== §6.6 収集効率アンカー ==============================

--- 当日の (item -> { qty, sellers(set), hours }) を dyn_npc_tx + dyn_player_playtime から作る
local function collectDailyYield()
    local rows = DynDb.query([[
        SELECT item, identifier, SUM(qty) AS qty
        FROM dyn_npc_tx
        WHERE direction = 'sell' AND voided = 0 AND created_at >= CURDATE()
        GROUP BY item, identifier
    ]]) or {}

    local playtime = DynDb.query('SELECT identifier, hours FROM dyn_player_playtime WHERE day = CURDATE()') or {}
    local hoursOf = {}
    for _, r in ipairs(playtime) do hoursOf[r.identifier] = tonumber(r.hours) or 0 end

    local byItem = {}
    for _, r in ipairs(rows) do
        local b = byItem[r.item] or { qty = 0, sellerCount = 0, hours = 0, seen = {} }
        b.qty = b.qty + (tonumber(r.qty) or 0)
        if not b.seen[r.identifier] then
            b.seen[r.identifier] = true
            b.sellerCount = b.sellerCount + 1
            b.hours = b.hours + (hoursOf[r.identifier] or 0)
        end
        byItem[r.item] = b
    end
    return byItem
end

local function runYield()
    if not Config.Calibration.yield then return end
    if not DynDb.isReady() then return end

    local cfg = Config.Calibration
    local byItem = collectDailyYield()

    -- 標本条件を満たす品目だけで、その日の実測時給の中央値（目標バンドの基準）を作る
    local hourlySamples, hourlyOf = {}, {}
    for item, b in pairs(byItem) do
        if b.sellerCount >= cfg.yieldMinUniqueSellers and b.hours >= cfg.yieldMinPlaytimeHours then
            local it = DynState.get(item)
            local q = it and DynPricing.quote(item, 1, 'sell')
            if it and not it.pinned and q then
                local rate = b.qty / b.hours
                local hourly = rate * q.priceNow
                hourlyOf[item] = { hourly = hourly, rate = rate, b = b }
                hourlySamples[#hourlySamples + 1] = hourly
            end
        end
    end

    if #hourlySamples == 0 then return end
    local medianHourly = CensusMath.median(hourlySamples)
    local lo, hi = CalibrationMath.yieldTargetBand(medianHourly, cfg.yieldBandLowMult, cfg.yieldBandHighMult)

    local adjustedCount = 0
    for item, data in pairs(hourlyOf) do
        local it = DynState.get(item)
        local newIndex = CalibrationMath.yieldAdjust(it.priceIndex, data.hourly, lo, hi, cfg.yieldMaxDailyPct)
        if newIndex and math.abs(newIndex - it.priceIndex) > 1e-9 then
            local oldIndex = it.priceIndex
            DynState.setPriceIndex(item, newIndex)
            adjustedCount = adjustedCount + 1
            info('収集効率アンカー: %s の price_index %.4f -> %.4f（時給 %.2f、目標帯 %.2f〜%.2f）',
                item, oldIndex, newIndex, data.hourly, lo, hi)
        end
        if DynDb.isReady() then
            DynDb.execute([[
                INSERT INTO dyn_item_yield (item, day, qty_sold, unique_sellers, playtime_hours, est_rate, est_hourly, applied)
                VALUES (?, CURDATE(), ?, ?, ?, ?, ?, 1)
                ON DUPLICATE KEY UPDATE qty_sold=VALUES(qty_sold), unique_sellers=VALUES(unique_sellers),
                    playtime_hours=VALUES(playtime_hours), est_rate=VALUES(est_rate), est_hourly=VALUES(est_hourly), applied=1
            ]], { item, data.b.qty, data.b.sellerCount, data.b.hours, data.rate, data.hourly })
        end
    end
    if adjustedCount > 0 then
        info('収集効率アンカー: %d 品目の price_index を補正しました（中央時給 %.2f）', adjustedCount, medianHourly)
    end
end

-- ============================== §6.7 マネーサプライ PI 制御 ==============================

local function runMoneySupply(snapshot, prevSnapshot)
    if not Config.Calibration.moneySupply then return end
    if not prevSnapshot then return end

    local growth = CalibrationMath.dailyGrowth(snapshot.total, tonumber(prevSnapshot.money_total))
    if not growth then return end

    local cfg = Config.Calibration
    local integral = DynState.econOr('ms_integral', 0)
    local buy, sell, newIntegral = CalibrationMath.moneySupplyPI(
        integral, growth, cfg.moneySupplyTargetGrowth, cfg.moneySupplyKp, cfg.moneySupplyKi)

    DynState.setEcon('global_mult_buy', buy)
    DynState.setEcon('global_mult_sell', sell)
    DynState.setEcon('ms_integral', newIntegral)
    info('マネーサプライ PI: 成長率 %+.2f%% (目標 %+.2f%%) -> 買取倍率 %.4f / 販売倍率 %.4f',
        growth * 100, cfg.moneySupplyTargetGrowth * 100, buy, sell)
end

-- ============================== 日次ジョブ本体 ==============================

--- 直近2件のスナップショットを取る（今回分＋比較対象の前回分）
local function lastTwoSnapshots()
    local rows = DynDb.query('SELECT * FROM dyn_econ_snapshot ORDER BY snapshot_at DESC LIMIT 2') or {}
    return rows[1], rows[2]
end

--- センサス実行後に呼ぶ。長期較正（§6.5〜6.7）は資産センサスが正常だった回だけ動かす
function DynCalibration.runDaily(censusResult)
    if not Config.Calibration or not Config.Calibration.enabled then return end
    if not censusResult then return end

    if Config.Calibration.bootstrap == false then
        -- bootstrap 自体は起動時 1 回きりの初期値決定（§6.2）なので、日次ジョブでは
        -- 何もしない。ここに来るのは wealth/yield/moneySupply の話だけ
    end

    if DynCensus.isHeld() then
        warn('資産センサスが異常を保留中のため、長期較正（§6.5〜6.7）をスキップしました')
        return
    end

    local snapshot = {
        total  = censusResult.total,
        median = censusResult.median,
        basket = censusResult.basketPrice,
    }
    runWealth(snapshot)
    runYield()

    local _, prevRow = lastTwoSnapshots()
    runMoneySupply(snapshot, prevRow)
end

RegisterCommand('dyn_calibrate', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(tostring(src), 'dyn_economy.admin') then return end
    local function reply(msg)
        if src == 0 then print(msg) else TriggerClientEvent('chat:addMessage', src, { args = { 'dyn_economy', msg } }) end
    end

    if args[1] ~= '--dry-run' then
        return reply('使い方: /dyn_calibrate --dry-run  （§6.9: 適用は別コマンドが要る設計。今は自動診断のみ）')
    end

    reply(('bootstrap=%s wealth=%s yield=%s moneySupply=%s（キルスイッチ enabled=%s）')
        :format(tostring(Config.Calibration.bootstrap), tostring(Config.Calibration.wealth),
                tostring(Config.Calibration.yield), tostring(Config.Calibration.moneySupply),
                tostring(Config.Calibration.enabled)))
    reply(('現在値: currency_scale=%.6f wealth_mult=%.6f global_mult_buy=%.4f global_mult_sell=%.4f')
        :format(DynState.econ('currency_scale'), DynState.econ('wealth_mult'),
                DynState.econ('global_mult_buy'), DynState.econ('global_mult_sell')))
    reply(('資産センサスの保留状態: %s'):format(DynCensus.isHeld() and 'あり（較正停止中）' or 'なし'))
end, false)

local TOGGLE_KEYS = {
    dynamic     = { get = function() return Config.Dynamic.enabled end, set = function(v) Config.Dynamic.enabled = v end },
    recipes     = { get = function() return Config.Recipes.enabled end, set = function(v) Config.Recipes.enabled = v end },
    bootstrap   = { get = function() return Config.Calibration.bootstrap end, set = function(v) Config.Calibration.bootstrap = v end },
    wealth      = { get = function() return Config.Calibration.wealth end, set = function(v) Config.Calibration.wealth = v end },
    yield       = { get = function() return Config.Calibration.yield end, set = function(v) Config.Calibration.yield = v end },
    moneysupply = { get = function() return Config.Calibration.moneySupply end, set = function(v) Config.Calibration.moneySupply = v end },
    pricelevel  = { get = function() return Config.PriceLevel.enabled end, set = function(v) Config.PriceLevel.enabled = v end },
    tax         = { get = function() return Config.Tax.enabled end, set = function(v) Config.Tax.enabled = v end },
}

RegisterCommand('dyn_toggle', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(tostring(src), 'dyn_economy.admin') then return end
    local function reply(msg)
        if src == 0 then print(msg) else TriggerClientEvent('chat:addMessage', src, { args = { 'dyn_economy', msg } }) end
    end

    if args[1] == 'list' or not args[1] then
        for key, t in pairs(TOGGLE_KEYS) do
            reply(('%-12s %s'):format(key, t.get() and 'ON' or 'OFF'))
        end
        return
    end

    local key = TOGGLE_KEYS[args[1]]
    if not key then
        return reply('使い方: /dyn_toggle <' .. table.concat((function()
            local ks = {} for k in pairs(TOGGLE_KEYS) do ks[#ks+1]=k end table.sort(ks) return ks
        end)(), '|') .. '> <on|off> | /dyn_toggle list')
    end
    if args[2] ~= 'on' and args[2] ~= 'off' then
        return reply(('現在: %s = %s'):format(args[1], key.get() and 'ON' or 'OFF'))
    end
    key.set(args[2] == 'on')
    reply(('%s を %s にしました'):format(args[1], args[2]:upper()))
end, false)
