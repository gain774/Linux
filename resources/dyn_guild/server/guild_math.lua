--[[
  組合・補助金の純粋ロジック（設計ドキュメント §9.3〜9.5）。
  FiveM にも DB にも依存しないので単体テストできる。

  州別・週次の税収を原資にする（ユーザー要望: RedM は州で分かれているので
  税を一つに丸めず、州ごと・週ごとに分ける）。dyn_treasury の
  GetStateWeekIncome(state, period) が返す「その州・その週の純税収」を
  入力として受け取り、ここでは配分だけを決める。
]]
GuildMath = {}

--[[
  申請内容の検証（申請する瞬間に決まる項目だけ）。DB 側の一意性
  （組合名の重複・1 キャラ1 組合）はここでは見ない（呼び出し側が
  UNIQUE 制約とクエリで確認する）。人数は申請後に /guild join で集まる
  運用を想定しているので、ここではなく canApprove 側で見る。

  @param app { name, category, state, founder }
  @param categories 許可されているカテゴリの一覧
  @param states 許可されている州の一覧（RedM の実在の州名）
]]
function GuildMath.validateApplication(app, categories, states)
    if type(app) ~= 'table' then return false, 'bad_argument' end
    if not app.name or app.name:gsub('%s+', '') == '' then return false, 'name_required' end
    if not app.category then return false, 'category_required' end

    local catOk = false
    for _, c in ipairs(categories or {}) do
        if c == app.category then catOk = true break end
    end
    if not catOk then return false, 'bad_category' end

    local stateOk = false
    for _, s in ipairs(states or {}) do
        if s == app.state then stateOk = true break end
    end
    if not stateOk then return false, 'bad_state' end

    if not app.founder then return false, 'founder_required' end
    return true
end

--- 承認できる状態か（人数が集まっているか）。status='pending' かどうかは呼び出し側の DB クエリで見る
function GuildMath.canApprove(memberCount, minFounders)
    return (tonumber(memberCount) or 0) >= (minFounders or 3)
end

--- 90 日無活動で自動失効するかどうか
function GuildMath.isInactive(lastActiveUnix, nowUnix, days)
    if not lastActiveUnix then return false end
    days = days or 90
    return (nowUnix - lastActiveUnix) >= days * 86400
end

--- 加入から補助対象になるまでの待機（§9.5: 作って即もらうのを防ぐ）
function GuildMath.isWaitOver(joinedAtUnix, nowUnix, waitDays)
    if not joinedAtUnix then return false end
    waitDays = waitDays or 7
    return (nowUnix - joinedAtUnix) >= waitDays * 86400
end

--[[
  1 人1日あたりの補助上限。config で明示されていればそれを使い、
  無ければ dyn_economy のアンカー価格 × 倍率から導出する
  （§9.5: 「§7 の目標曲線の day1 相当額、無ければバスケット1個分」の簡略版）。
  どちらも取れなければ最後のフォールバック値を使う。
]]
function GuildMath.perPersonDailyCap(configuredCap, anchorPrice, anchorMultiplier, fallback)
    if configuredCap and configuredCap > 0 then return configuredCap end
    if anchorPrice and anchorPrice > 0 then return anchorPrice * (anchorMultiplier or 20) end
    return fallback or 10
end

--[[
  州・週の予算。dyn_treasury から取った「その州・その週の純税収」に
  budgetRatio を掛けるだけ（§9.4 の月次予算をそのまま週次スコープへ縮小）。
  収入がマイナス（取り消し超過など）なら予算は 0。
]]
function GuildMath.weeklyBudget(stateWeekIncome, budgetRatio)
    local income = tonumber(stateWeekIncome) or 0
    local ratio  = tonumber(budgetRatio) or 0
    local budget = income * ratio
    return budget > 0 and budget or 0
end

--- 組合ごとの週次上限。予算をその州の承認済み組合数で均等割りする
function GuildMath.perGuildCap(weeklyBudget, approvedGuildCountInState)
    local n = tonumber(approvedGuildCountInState) or 0
    if n <= 0 then return 0 end
    return (tonumber(weeklyBudget) or 0) / n
end

--[[
  「YYYY-Www」形式の週ラベル。dyn_treasury/server/ledger_math.lua の
  TreasuryMath.weekLabel と**同一の式**（意図的な複製。リソースをまたいで
  Lua ファイルは共有できないため）。組合の週次予算は dyn_treasury が
  集計した州別週次の税収を原資にするので、週の境目がこことズレると
  「先週分のはずが今週の予算から引かれる」といった食い違いが起きる。
  この関数を変えるときは dyn_treasury 側も必ず同じに直すこと。
]]
function GuildMath.weekLabel(unixTime)
    local t = os.date('!*t', unixTime)
    local dayOfYear = tonumber(os.date('!%j', unixTime))
    local week = math.floor((dayOfYear - 1) / 7) + 1
    return ('%04d-W%02d'):format(t.year, week)
end

--[[
  実績払い（accrual）の補助額を計算する（§9.4 モードB）。

  shipments: { { identifier, item, qty }, ... }  -- その週、その組合のメンバーが
             NPC に売却した実績（dyn_economy:committed の sell を拾って積んだもの）
  rules:     item -> { unitAmount, enabled }      -- dyn_guild_subsidy_rules
  members:   identifier -> { eligible = bool }     -- 加入7日経過などの判定済みフラグ
  opts:      { memberDailyCap, guildWeeklyCap }

  返り値: { total, byMember = { identifier -> amount }, lines = { {identifier,item,qty,amount}, ... } }
]]
function GuildMath.accrualPayout(shipments, rules, members, opts)
    opts = opts or {}
    local memberWeeklyCap = (opts.memberDailyCap or math.huge) * 7
    local guildWeeklyCap  = opts.guildWeeklyCap or math.huge

    local byMember, lines = {}, {}
    for _, s in ipairs(shipments or {}) do
        local rule = rules and rules[s.item]
        local elig = members and members[s.identifier]
        if rule and rule.enabled ~= false and rule.unitAmount and elig and elig.eligible then
            local amount = s.qty * rule.unitAmount
            if amount > 0 then
                byMember[s.identifier] = (byMember[s.identifier] or 0) + amount
                lines[#lines + 1] = { identifier = s.identifier, item = s.item, qty = s.qty, amount = amount }
            end
        end
    end

    -- メンバーごとの週次上限でクランプ
    for id, amount in pairs(byMember) do
        if amount > memberWeeklyCap then byMember[id] = memberWeeklyCap end
    end

    local total = 0
    for _, amount in pairs(byMember) do total = total + amount end

    -- 組合全体の週次上限を超えたら、各メンバー分を比例縮小する
    -- （誰か 1 人を優先して打ち切るより、全員に公平に効かせる）
    if total > guildWeeklyCap and total > 0 then
        local scale = guildWeeklyCap / total
        for id, amount in pairs(byMember) do byMember[id] = amount * scale end
        for _, line in ipairs(lines) do line.amount = line.amount * scale end
        total = guildWeeklyCap
    end

    return { total = total, byMember = byMember, lines = lines }
end
