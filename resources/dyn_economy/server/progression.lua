--[[
  目標成長曲線ターゲティング（§7、既定 OFF）。

  「○日でこのくらい稼いでいてほしい」という目標曲線と実測のズレを income_mult
  （NPC 買取＝プレイヤーの稼ぎ）に変換する。数式は shared/progression_math.lua
  （純粋関数）にあり、ここは DB から材料を集めて適用し、監査ログを残すだけ。

  §7.4 の注記（マネーサプライ PI 制御と競合して発振する）は、pricing.lua で
  income_mult（このレイヤー）と global_mult（§6.7）を別々の econ キー・
  別々のスタック段として実装しているため、このリソースでは構造的に発生しない。
  ドキュメント通り「Progression ON のとき §6.7 を止めたい」場合は
  `/dyn_toggle moneysupply off` を使えばよい。
]]
DynProgression = {}

local function warn(fmt, ...) print(('^3[dyn_economy] ' .. fmt .. '^0'):format(...)) end
local function info(fmt, ...) print(('[dyn_economy] ' .. fmt):format(...)) end

-- ============================== 実績の記録 ==============================

--- NPC 売買のたびに呼ぶ。earned/spent の累計と first_seen/last_seen を更新する
local function upsertProgress(identifier, earnedDelta, spentDelta)
    if not Config.Progression.enabled or not DynDb.isReady() or not identifier then return end
    DynDb.execute([[
        INSERT INTO dyn_player_progress (identifier, first_seen, last_seen, earned_total, spent_total, updated_at)
        VALUES (?, NOW(), NOW(), ?, ?, NOW())
        ON DUPLICATE KEY UPDATE
            last_seen    = NOW(),
            earned_total = earned_total + VALUES(earned_total),
            spent_total  = spent_total + VALUES(spent_total),
            updated_at   = NOW()
    ]], { identifier, earnedDelta or 0, spentDelta or 0 })
end

AddEventHandler('dyn_economy:committed', function(tx)
    if not tx or not tx.identifier or not tx.total then return end
    if tx.direction == 'sell' then
        upsertProgress(tx.identifier, tx.total, 0)
    elseif tx.direction == 'buy' then
        upsertProgress(tx.identifier, 0, tx.total)
    end
end)

--- 個人間取引（dyn_trade）など、NPC 経由ではない収入を加算する。
--- 「NPC売却＋委託所（実質はP2P直接取引）売上の累計」（§7.5）に対応する
function DynProgression.recordEarned(identifier, amount)
    if not amount or amount <= 0 then return false end
    upsertProgress(identifier, amount, 0)
    return true
end

-- ============================== 曲線 ==============================

--- DB（dyn_progress_curve）に行があればそちらを優先する（§7.5: 再起動無しで編集可能に）
local function activeCurve()
    if DynDb.isReady() then
        local rows = DynDb.query('SELECT day_index, target_value FROM dyn_progress_curve')
        if rows and #rows > 0 then
            local curve = {}
            for _, r in ipairs(rows) do
                curve[#curve + 1] = { day = tonumber(r.day_index), value = tonumber(r.target_value) }
            end
            return curve
        end
    end
    return Config.Progression.curve
end

--- §6.3 startingMode='curve' が使う「day0相当」の値
function DynProgression.curveDay0()
    return ProgressionMath.curveStart(activeCurve())
end

-- ============================== 日次評価 ==============================

--- 直近 activeDays にログインしたプレイヤーの実績行
local function activeRows()
    return DynDb.query([[
        SELECT identifier, playtime_hours, earned_total, spent_total, networth, earned_at_eval,
               DATEDIFF(NOW(), first_seen) AS calendar_days
        FROM dyn_player_progress
        WHERE last_seen >= DATE_SUB(NOW(), INTERVAL ? DAY)
    ]], { Config.Progression.activeDays or 14 }) or {}
end

--- 現在の所持金+銀行残高（§6.4 のセンサスと同じ集計を流用する）
local function currentWealthLookup()
    local samples = DynCensus.collect() or {}
    local byId = {}
    for _, s in ipairs(samples) do byId[s.id] = s.amount end
    return byId
end

function DynProgression.runDaily()
    if not Config.Progression or not Config.Progression.enabled then return end
    if not DynDb.isReady() then return end

    local cfg = Config.Progression
    local rows = activeRows()
    if #rows == 0 then return end

    local wealth = currentWealthLookup()
    local curve = activeCurve()

    -- バケット別に値と day を集める（同時に coverage の分子・分母も積む）
    local buckets = {}
    local coverageSum = { earned = {}, wealth = {} }
    for _, r in ipairs(rows) do
        local playtime = tonumber(r.playtime_hours) or 0
        local day = ProgressionMath.dayOf(cfg.basis, cfg.hoursPerDay, playtime, tonumber(r.calendar_days))
        if day then
            local bucket = ProgressionMath.bucketOf(day)
            local earnedTotal = tonumber(r.earned_total) or 0
            local value = (cfg.metric == 'networth') and (wealth[r.identifier] or 0) or earnedTotal

            local b = buckets[bucket] or { values = {}, days = {} }
            b.values[#b.values + 1] = value
            b.days[#b.days + 1] = day
            buckets[bucket] = b

            -- coverage（§7.6）: このプレイヤーの前回評価からの Mod 経由収入と、
            -- 実際の資産増加分。負の増加（散財・略奪された等）は 0 扱いにして
            -- 母数をおかしくしない
            local wealthNow = wealth[r.identifier]
            local prevWealth = tonumber(r.networth) or 0
            local prevEarned = tonumber(r.earned_at_eval) or 0
            if wealthNow then
                local deltaEarned = math.max(0, earnedTotal - prevEarned)
                local deltaWealth = math.max(0, wealthNow - prevWealth)
                coverageSum.earned[bucket] = (coverageSum.earned[bucket] or 0) + deltaEarned
                coverageSum.wealth[bucket] = (coverageSum.wealth[bucket] or 0) + deltaWealth
            end
        end
    end

    -- avgDay を計算してから評価用の形に整える
    for name, b in pairs(buckets) do
        local sum = 0
        for _, d in ipairs(b.days) do sum = sum + d end
        b.avgDay = sum / #b.days
    end
    buckets = ProgressionMath.filterMinSamples(buckets, cfg.minSamples)

    local result = ProgressionMath.evaluate(buckets, curve, cfg.bucketWeight)

    -- 実績の記録更新（次回の coverage 差分計算の基準にする）。評価に使ったかどうかに
    -- 関わらず、今回わかった値で毎回更新する
    for _, r in ipairs(rows) do
        local wealthNow = wealth[r.identifier]
        if wealthNow then
            DynDb.execute('UPDATE dyn_player_progress SET networth = ?, earned_at_eval = earned_total WHERE identifier = ?',
                { wealthNow, r.identifier })
        end
    end

    if not result then
        info('目標成長曲線: 評価できるバケットがありません（標本不足）')
        return
    end

    local prevMult = DynState.econ('income_mult')
    local inBand = ProgressionMath.isInBand(result.E, cfg.tolerance)
    local newMult = prevMult

    -- coverage が低いバケットだけ警告する（§7.6: 機能ではなく安全装置）
    local lowCoverage = false
    for bucket in pairs(result.details) do
        local cov = ProgressionMath.coverage(coverageSum.earned[bucket], coverageSum.wealth[bucket])
        if cov and cov < (cfg.coverageWarn or 0.5) then
            lowCoverage = true
            warn('目標成長曲線: %s 層の収入の %.0f%% が Mod 外です。補正の効果が薄い可能性があります',
                bucket, (1 - cov) * 100)
        end
    end

    if not inBand and not lowCoverage then
        newMult = ProgressionMath.updateIncomeMult(prevMult, result.E, cfg.Kp, cfg.maxDailyAdj)
        if math.abs(newMult - prevMult) > 1e-9 then
            DynState.setEcon('income_mult', newMult)
            info('目標成長曲線: E=%+.3f（目標比 %+.0f%%） income_mult %.4f -> %.4f',
                result.E, (math.exp(result.E) - 1) * 100, prevMult, newMult)
        end
    elseif lowCoverage then
        info('目標成長曲線: coverage 不足のため今回の補正を見送りました')
    end

    if DynDb.isReady() then
        for bucket, d in pairs(result.details) do
            local cov = ProgressionMath.coverage(coverageSum.earned[bucket], coverageSum.wealth[bucket])
            DynDb.execute([[
                INSERT INTO dyn_progress_eval (evaluated_at, bucket, n, median_value, target_value, ratio, applied_mult, coverage)
                VALUES (NOW(), ?, ?, ?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE n=VALUES(n), median_value=VALUES(median_value), target_value=VALUES(target_value),
                    ratio=VALUES(ratio), applied_mult=VALUES(applied_mult), coverage=VALUES(coverage)
            ]], { bucket, d.n, d.median, d.target, d.ratio, newMult, cov })
        end
    end
end

-- ============================== 診断コマンド ==============================

RegisterCommand('dyn_progress', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(tostring(src), 'dyn_economy.admin') then return end
    local function reply(msg)
        if src == 0 then print(msg) else TriggerClientEvent('chat:addMessage', src, { args = { 'dyn_economy', msg } }) end
    end

    local cfg = Config.Progression
    reply(('基準: %s (%.1fh = 1日) / 指標: %s / 状態: %s')
        :format(cfg.basis, cfg.hoursPerDay, cfg.metric, cfg.enabled and 'ON' or 'OFF'))
    if not cfg.enabled then
        return reply('Config.Progression.enabled = false のため動作していません')
    end
    reply(('income_mult 現在値: %.4f'):format(DynState.econ('income_mult')))

    if args[1] == '--apply' then
        DynProgression.runDaily()
        return reply('評価を実行しました（結果は上のログ、または次の /dyn_progress で確認）')
    end

    if not DynDb.isReady() then return reply('DB が無いため評価履歴を表示できません') end
    local rows = DynDb.query([[
        SELECT bucket, n, median_value, target_value, ratio, applied_mult, coverage
        FROM dyn_progress_eval
        WHERE evaluated_at = (SELECT MAX(evaluated_at) FROM dyn_progress_eval)
        ORDER BY FIELD(bucket, 'early','mid','late')
    ]]) or {}
    if #rows == 0 then return reply('評価履歴がまだありません（--apply で試すか、日次ジョブの実行を待ってください）') end
    for _, r in ipairs(rows) do
        reply(('%-6s 人数%-3d 実測中央値%8.1f 目標%8.1f 達成率%6.2fx 倍率%6.3f coverage%s')
            :format(r.bucket, r.n, r.median_value, r.target_value, r.ratio, r.applied_mult,
                    r.coverage and (('%.2f'):format(r.coverage)) or '—'))
    end
end, false)
