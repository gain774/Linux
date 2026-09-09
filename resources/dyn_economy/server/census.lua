--[[
  資産センサス（設計ドキュメント §6.4）

  統計そのものは shared/census_math.lua（純粋関数・単体テスト済み）にある。
  ここは DB から金額を集めて、結果を残し、異常なら較正を止める役目だけを持つ。

  国庫（dyn_treasury）はここに現れない。誰の財布にも入っていない金なので、
  流通量と国庫が自然に分かれる（§9.2）。
]]
DynCensus = {}

local missingWallets = {}   -- 一度警告したテーブルは黙る
local held = false

local function warn(fmt, ...) print(('^3[dyn_economy] ' .. fmt .. '^0'):format(...)) end
local function info(fmt, ...) print(('[dyn_economy] ' .. fmt):format(...)) end

--[[
  クエリの組み立て（純粋関数）。

  テーブル名も列名も設定から来るので、識別子はバッククォートで囲む。
  生成した SQL が実テーブルに対して通るかは tests/census_sql_check.sh が
  VORP と同じ形のテーブルを作って確認する。
]]
function DynCensus.baseQuery(base)
    return ([[
        SELECT `%s` AS id, `%s` AS amount,
               (`%s` >= DATE_SUB(NOW(), INTERVAL ? DAY)) AS active
        FROM `%s`
    ]]):format(base.owner, base.column, base.lastLogin, base.table)
end

function DynCensus.walletQuery(w)
    return ([[
        SELECT `%s` AS id, SUM(`%s`) AS amount FROM `%s` GROUP BY `%s`
    ]]):format(w.owner, w.column, w.table, w.owner)
end

--- 全キャラクターの所持金を集める。追加の財布があれば足し込む。
function DynCensus.collect()
    local cfg  = Config.Census
    local base = cfg.base

    local rows = DynDb.query(DynCensus.baseQuery(base), { cfg.activeDays })

    if not rows then
        warn('%s を読めませんでした。センサスを中止します', base.table)
        return nil
    end

    local byId, samples = {}, {}
    for _, r in ipairs(rows) do
        local s = {
            id     = tostring(r.id),
            amount = tonumber(r.amount) or 0,
            active = tonumber(r.active) == 1,
        }
        byId[s.id] = s
        samples[#samples + 1] = s
    end

    for _, w in ipairs(cfg.wallets or {}) do
        local extra = DynDb.query(DynCensus.walletQuery(w))

        if extra then
            for _, r in ipairs(extra) do
                local s = byId[tostring(r.id)]
                -- 対応するキャラクターがいない残高は、統計には入れず総額にだけ足す
                if s then
                    s.amount = s.amount + (tonumber(r.amount) or 0)
                else
                    samples[#samples + 1] = { id = tostring(r.id),
                                              amount = tonumber(r.amount) or 0, active = false }
                end
            end
        elseif not missingWallets[w.table] then
            missingWallets[w.table] = true
            warn('%s を読めませんでした。この財布は総額に含まれません', w.table)
        end
    end

    return samples
end

--- 前回センサス以降に Mod 経由で増減した額。
--- dyn_npc_tx.total はプレイヤーが受け取った／支払った額（税引き後）なので、
--- 国庫に入った税は自動的に除かれる。
local function modNetSince(since)
    if not since then return 0 end
    local row = DynDb.query([[
        SELECT COALESCE(SUM(CASE WHEN direction = 'sell' THEN total ELSE -total END), 0) AS net
        FROM dyn_npc_tx
        WHERE voided = 0 AND created_at > ?
    ]], { since })
    return row and row[1] and tonumber(row[1].net) or 0
end

local function previousSnapshot()
    local row = DynDb.query(
        'SELECT snapshot_at, money_total FROM dyn_econ_snapshot ORDER BY snapshot_at DESC LIMIT 1')
    return row and row[1] or nil
end

--- 基準バスケットの価格。固定した品目の購入単価の合計
local function basketPrice()
    local names = Config.Census.basket
    if not names or #names == 0 then
        names = {}
        for item in pairs(DynState.all()) do names[#names + 1] = item end
        table.sort(names)
    end
    local total, counted = 0, 0
    for _, item in ipairs(names) do
        local q = DynPricing.quote(item, 1, 'buy')
        if q then total = total + q.priceNow; counted = counted + 1 end
    end
    return counted > 0 and total or nil
end

--- 較正を保留しているか（§6.5〜6.7・§7 の長期較正が参照する）
function DynCensus.isHeld() return held end

function DynCensus.setHeld(v)
    held = v and true or false
    DynState.setEcon('calibration_hold', held and 1 or 0)
end

--- センサスを 1 回実行する
function DynCensus.run()
    if not Config.Census.enabled then return nil end
    if not DynDb.isReady() then
        warn('DB が無いためセンサスを実行できません')
        return nil
    end

    local samples = DynCensus.collect()
    if not samples then return nil end

    local r = CensusMath.summarize(samples, { outlierMAD = Config.Census.outlierMAD })

    local prev = previousSnapshot()
    local expected, drift, drifting
    if prev then
        expected = (tonumber(prev.money_total) or 0) + modNetSince(prev.snapshot_at)
        drift    = CensusMath.drift(r.total, expected)
        drifting = CensusMath.isDrifting(r.total, expected, Config.Census.driftTolerance)
    end

    local basket = basketPrice()

    DynDb.execute([[
        INSERT INTO dyn_econ_snapshot
            (snapshot_at, money_total, money_median, money_p90, money_p99,
             characters, active_players, outliers, basket_price, currency_scale,
             expected_total, drift, held)
        VALUES (NOW(), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { r.total, r.median, r.p90, r.p99, r.n, r.activeN, #r.outliers,
          basket, DynState.econ('currency_scale'), expected, drift,
          drifting and 1 or 0 })

    for _, o in ipairs(r.outliers) do
        DynDb.execute([[
            INSERT INTO dyn_wealth_outlier (detected_at, identifier, amount, median_ref, mad_score)
            VALUES (NOW(), ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE amount = VALUES(amount)
        ]], { o.id, o.amount, r.median or 0, o.madScore })
    end

    info('センサス: 総額 %.2f / キャラ %d 人（アクティブ %d） / 中央値 %s / 外れ値 %d 件',
        r.total, r.n, r.activeN, r.median and ('%.2f'):format(r.median) or '-', #r.outliers)

    if drifting then
        DynCensus.setHeld(true)
        warn('資産センサス異常: 総額が予測より %+.0f%%（予測 %.0f / 実測 %.0f）',
            (r.total / math.max(expected, 1) - 1) * 100, expected, r.total)
        warn('  Mod 外の入出金または複製の可能性があります。長期較正を保留しました。')
        for i = 1, math.min(3, #r.outliers) do
            warn('  上位乖離: %s (%.0f, MAD %.1f 個分)',
                r.outliers[i].id, r.outliers[i].amount, r.outliers[i].madScore)
        end
        warn('  確認後 /dyn_census --accept で保留を解除してください。')
    end

    -- 短期の需給変動（§4）は止めない。止めると店が全部固定価格になってゲームが壊れる。
    r.expected, r.drift, r.held = expected, drift, drifting
    return r
end

RegisterCommand('dyn_census', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(tostring(src), 'dyn_economy.admin') then return end
    local function reply(msg)
        if src == 0 then print(msg)
        else TriggerClientEvent('chat:addMessage', src, { args = { 'dyn_economy', msg } }) end
    end

    if args[1] == '--accept' then
        DynCensus.setHeld(false)
        return reply('較正の保留を解除しました')
    end

    local r = DynCensus.run()
    if not r then return reply('センサスを実行できませんでした（ログを確認してください）') end
    reply(('総額 %.2f / キャラ %d 人（アクティブ %d） / 外れ値 %d 件')
        :format(r.total, r.n, r.activeN, #r.outliers))
    reply(('  中央値 %s / p90 %s / 保留 %s')
        :format(r.median and ('%.2f'):format(r.median) or '-',
                r.p90 and ('%.2f'):format(r.p90) or '-',
                r.held and 'あり' or 'なし'))
end, false)
