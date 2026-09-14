--[[
  個人間取引（P2P）の交渉セッション。

  安全設計の要点:
    - 品物・現金は「提示」段階では一切動かさない（エスクロー方式にしない）。
      提示はただの数値の記録で、双方が確認した瞬間に初めて現物を検証・移動する。
      理由: 参照カウント方式は「取り消し忘れ」「切断時の返却漏れ」がバグると
      即・複製/消失事故になる。何も動かさなければ、その種のバグはそもそも起きない。
    - 確定直前に必ず現在の所持を再確認する（提示してから使い込む／落とす可能性があるため）。
    - 内容が変わったら（品目追加・削除・現金変更）両者の確認は必ず解除する。
      片方が確認した後に相手が中身を変えて騙し討ちする、を構造的に防ぐ。
    - 決済は「両者から先に全部取り上げてから、両者に渡す」の順で行い、
      取り上げに失敗したら、既に取り上げた分をその場で全部返して中止する
      （dyn_economy_bridge/server/txflow.lua と同じ、片手落ちを残さない設計）。
]]

local sessions = {}         -- id -> session
local activeSession = {}    -- src -> sessionId
local pendingInvites = {}   -- targetSrc -> { from = src, expiresAt = ms }
local nextId = 0

local function nowMs() return math.floor(os.clock() * 1000) end

local function money(v) return ('%s%.2f'):format(Config.currencyLabel or '$', v or 0) end

local function sideOf(session, src)
    if session.a.src == src then return 'a', 'b' end
    if session.b.src == src then return 'b', 'a' end
    return nil, nil
end

local function getSession(src)
    local id = activeSession[src]
    return id and sessions[id]
end

local function newSession(srcA, srcB)
    nextId = nextId + 1
    local id = nextId
    local session = {
        id = id,
        a = { src = srcA, offer = { items = {}, cash = 0 }, confirmed = false },
        b = { src = srcB, offer = { items = {}, cash = 0 }, confirmed = false },
        lastActivityAt = nowMs(),
    }
    sessions[id] = session
    activeSession[srcA] = id
    activeSession[srcB] = id
    return session
end

--- dyn_economy が入っていれば定価を「目安」として一緒に返す。無くても取引自体は動く
local function priceHint(item)
    if GetResourceState('dyn_economy') ~= 'started' then return nil end
    local ok, info = pcall(function() return exports.dyn_economy:GetItemInfo(item) end)
    if not ok or not info then return nil end
    return info.npcBuy, info.label
end

local function itemDisplay(e)
    local refPrice, label = priceHint(e.item)
    return { item = e.item, qty = e.qty, label = label or e.item, refPrice = refPrice }
end

local function offerPayload(side)
    local out = { cash = side.offer.cash, confirmed = side.confirmed, items = {} }
    for _, e in ipairs(side.offer.items) do
        out.items[#out.items + 1] = itemDisplay(e)
    end
    return out
end

local function buildSync(session, src)
    local my, other = sideOf(session, src)
    if not my then return nil end
    return {
        sessionId = session.id,
        otherName = TradeAdapter.getName(session[other].src) or ('プレイヤー#' .. session[other].src),
        mine  = offerPayload(session[my]),
        other = offerPayload(session[other]),
        feeRate = Config.feeRate,
    }
end

local function pushSync(session)
    session.lastActivityAt = nowMs()
    TriggerClientEvent('dyn_trade:sync', session.a.src, buildSync(session, session.a.src))
    TriggerClientEvent('dyn_trade:sync', session.b.src, buildSync(session, session.b.src))
end

local function endSession(session, reason, notify)
    activeSession[session.a.src] = nil
    activeSession[session.b.src] = nil
    sessions[session.id] = nil
    if notify then
        TradeAdapter.notify(session.a.src, reason)
        TradeAdapter.notify(session.b.src, reason)
    end
    TriggerClientEvent('dyn_trade:closed', session.a.src, reason)
    TriggerClientEvent('dyn_trade:closed', session.b.src, reason)
end

local function abortFinalize(session, reason)
    session.a.confirmed = false
    session.b.confirmed = false
    TradeAdapter.notify(session.a.src, reason)
    TradeAdapter.notify(session.b.src, reason)
    pushSync(session)
end

--- 相手に渡した後の記帳（任意）。失敗しても取引そのものは既に成立している
local function recordTx(session, feeA, feeB)
    if not TradeDb.isReady() then return end
    local idA = TradeAdapter.getIdentifier(session.a.src) or 'unknown'
    local idB = TradeAdapter.getIdentifier(session.b.src) or 'unknown'
    TradeDb.insert([[
        INSERT INTO dyn_p2p_tx (created_at, char_a, char_b, items_a, items_b, cash_a, cash_b, fee_a, fee_b)
        VALUES (NOW(), ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        idA, idB,
        json.encode(session.a.offer.items), json.encode(session.b.offer.items),
        session.a.offer.cash, session.b.offer.cash, feeA, feeB,
    })
end

local FINALIZE_ERRORS = {
    item_short_a       = '取引失敗: 提示品が不足しています',
    item_short_b       = '取引失敗: 相手の提示品が不足しています',
    cash_short_a       = '取引失敗: 所持金が不足しています',
    cash_short_b       = '取引失敗: 相手の所持金が不足しています',
    cannot_carry_a     = '取引失敗: これ以上持てません',
    cannot_carry_b     = '取引失敗: 相手がこれ以上持てません',
    remove_failed_a    = '取引失敗: 品を受け取れませんでした',
    remove_failed_b    = '取引失敗: 相手から品を受け取れませんでした',
    cash_remove_failed_a = '取引失敗: 現金を受け取れませんでした',
    cash_remove_failed_b = '取引失敗: 相手から現金を受け取れませんでした',
}

--[[
  確定処理。両者が確認した瞬間に一度だけ呼ばれる。実際の検証・現物移動・巻き戻しは
  server/trade_flow.lua（FiveM 非依存、単体テスト済み）に任せ、ここでは
  その結果を通知・記帳・セッション終了に変換するだけ
]]
local function finalizeTrade(session)
    if not TradeAdapter.isReady() then
        return abortFinalize(session, '取引処理を行えませんでした（フレームワーク未準備）')
    end

    local result, err = TradeFlow.finalize({ adapter = TradeAdapter, feeRate = Config.feeRate }, session)
    if not result then
        return abortFinalize(session, FINALIZE_ERRORS[err] or ('取引失敗: ' .. tostring(err)))
    end

    local A, B = session.a, session.b
    local totalFee = result.feeA + result.feeB
    if totalFee > 0 then
        -- 一方向の通知。dyn_treasury が入っていなければ単に誰も拾わないだけ
        TriggerEvent('dyn_trade:fee', {
            amount = totalFee, sessionId = session.id,
            note = ('P2P取引 手数料 (session %d)'):format(session.id),
        })
    end

    recordTx(session, result.feeA, result.feeB)

    TradeAdapter.notify(A.src, ('取引成立: 受取 %s（手数料 %s）'):format(money(result.netToA), money(result.feeB)))
    TradeAdapter.notify(B.src, ('取引成立: 受取 %s（手数料 %s）'):format(money(result.netToB), money(result.feeA)))

    endSession(session, '取引が成立しました', false)
end

-- ============================== イベント ==============================

local function findNearestPlayer(src, maxDist)
    local srcPed = GetPlayerPed(src)
    if not srcPed or srcPed == 0 then return nil end
    local srcCoords = GetEntityCoords(srcPed)
    local best, bestDist
    for _, playerId in ipairs(GetPlayers()) do
        local candidate = tonumber(playerId)
        if candidate and candidate ~= src then
            local ped = GetPlayerPed(candidate)
            if ped and ped ~= 0 then
                local dist = #(GetEntityCoords(ped) - srcCoords)
                if dist <= maxDist and (not bestDist or dist < bestDist) then
                    best, bestDist = candidate, dist
                end
            end
        end
    end
    return best
end

CreateThread(function()
    while not TradeAdapter.isReady() do Wait(200) end

    -- 取引中のプレイヤーが「アイテムを追加」を選んだときの一覧取得
    TradeAdapter.core().Callback.Register('dyn_trade:getInventory', function(src, cb)
        if not activeSession[src] then return cb({}) end
        cb(TradeAdapter.listInventory(src))
    end)

    TradeAdapter.registerUsableItem(Config.item, function(args)
        local src = args.source
        if activeSession[src] then
            return TradeAdapter.notify(src, 'あなたは既に取引中です')
        end
        local mine = pendingInvites[src]
        if mine and mine.expiresAt > nowMs() then
            return TradeAdapter.notify(src, '返答待ちの申し込みがあります')
        end

        local target = findNearestPlayer(src, Config.inviteDistance)
        if not target then
            return TradeAdapter.notify(src, '近くに取引相手がいません')
        end
        if activeSession[target] then
            return TradeAdapter.notify(src, 'その相手は取引中です')
        end
        local existing = pendingInvites[target]
        if existing and existing.expiresAt > nowMs() then
            return TradeAdapter.notify(src, 'その相手は他の申し込みに応答中です')
        end

        pendingInvites[target] = { from = src, expiresAt = nowMs() + Config.inviteTimeoutMs }
        TradeAdapter.notify(src, ('%s に取引を申し込みました'):format(TradeAdapter.getName(target) or ('プレイヤー#' .. target)))
        TriggerClientEvent('dyn_trade:invited', target, TradeAdapter.getName(src) or ('プレイヤー#' .. src))
    end)
end)

RegisterNetEvent('dyn_trade:respond', function(accept)
    local src = source
    local inv = pendingInvites[src]
    pendingInvites[src] = nil
    if not inv or inv.expiresAt < nowMs() then
        return TradeAdapter.notify(src, '申し込みは期限切れです')
    end
    if not accept then
        return TradeAdapter.notify(inv.from, '取引の申し込みが断られました')
    end
    if activeSession[inv.from] or activeSession[src] then
        return TradeAdapter.notify(src, 'どちらかが既に取引中です')
    end

    local session = newSession(inv.from, src)
    TriggerClientEvent('dyn_trade:open', inv.from)
    TriggerClientEvent('dyn_trade:open', src)
    pushSync(session)
end)

RegisterNetEvent('dyn_trade:setCash', function(amount)
    local src = source
    local session = getSession(src)
    if not session then return end
    local my = sideOf(session, src)
    amount = tonumber(amount)
    if not amount or amount < 0 then
        return TradeAdapter.notify(src, '金額が正しくありません')
    end
    amount = TradeMath.round2(amount)
    if amount > TradeAdapter.getMoney(src) then
        return TradeAdapter.notify(src, '所持金より多い額は設定できません')
    end

    session[my].offer.cash = amount
    session.a.confirmed = false
    session.b.confirmed = false
    pushSync(session)
end)

RegisterNetEvent('dyn_trade:addItem', function(item, qty)
    local src = source
    local session = getSession(src)
    if not session then return end
    local my = sideOf(session, src)

    qty = math.floor(tonumber(qty) or 0)
    if type(item) ~= 'string' or item == '' or qty <= 0 then
        return TradeAdapter.notify(src, '数量が正しくありません')
    end

    local offer = session[my].offer
    local idx, already = nil, 0
    for i, e in ipairs(offer.items) do
        if e.item == item then idx, already = i, e.qty break end
    end
    if not idx and #offer.items >= Config.maxOfferItems then
        return TradeAdapter.notify(src, ('一度に出せる品目は%d種類までです'):format(Config.maxOfferItems))
    end

    local total = already + qty
    if TradeAdapter.getItemCount(src, item) < total then
        return TradeAdapter.notify(src, 'その数は持っていません')
    end

    if idx then
        offer.items[idx].qty = total
    else
        offer.items[#offer.items + 1] = { item = item, qty = qty }
    end

    session.a.confirmed = false
    session.b.confirmed = false
    pushSync(session)
end)

RegisterNetEvent('dyn_trade:removeItem', function(item)
    local src = source
    local session = getSession(src)
    if not session then return end
    local my = sideOf(session, src)
    local offer = session[my].offer
    for i, e in ipairs(offer.items) do
        if e.item == item then table.remove(offer.items, i) break end
    end
    session.a.confirmed = false
    session.b.confirmed = false
    pushSync(session)
end)

RegisterNetEvent('dyn_trade:confirm', function()
    local src = source
    local session = getSession(src)
    if not session then return end
    local my = sideOf(session, src)
    session[my].confirmed = true

    if session.a.confirmed and session.b.confirmed then
        finalizeTrade(session)
    else
        pushSync(session)
    end
end)

RegisterNetEvent('dyn_trade:unconfirm', function()
    local src = source
    local session = getSession(src)
    if not session then return end
    local my = sideOf(session, src)
    session[my].confirmed = false
    pushSync(session)
end)

RegisterNetEvent('dyn_trade:cancel', function()
    local src = source
    local session = getSession(src)
    if not session then return end
    endSession(session, '取引はキャンセルされました', true)
end)

AddEventHandler('playerDropped', function()
    local src = source
    pendingInvites[src] = nil
    for target, inv in pairs(pendingInvites) do
        if inv.from == src then pendingInvites[target] = nil end
    end
    local session = getSession(src)
    if session then
        endSession(session, '相手が切断したため取引はキャンセルされました', true)
    end
end)

-- 放置された交渉・期限切れの申し込みを掃除する
CreateThread(function()
    while true do
        Wait(30000)
        local now = nowMs()
        for id, session in pairs(sessions) do
            if now - session.lastActivityAt > Config.sessionTimeoutMs then
                endSession(session, '一定時間操作がなかったため取引はキャンセルされました', true)
            end
        end
        for target, inv in pairs(pendingInvites) do
            if inv.expiresAt < now then pendingInvites[target] = nil end
        end
    end
end)

CreateThread(function()
    Wait(1000)
    if MySQL then
        TradeDb.setReady(true)
        if Config.autoMigrate then TradeDb.migrate() end
    else
        print('^3[dyn_trade] oxmysql が無いためメモリ上だけで動作します（監査ログなし）^0')
    end
    print('[dyn_trade] 起動完了')
end)
