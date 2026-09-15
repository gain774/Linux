--[[
  国庫の出納の判定（純粋関数）。

  「その取引から税をいくら、どちら向きに記帳するか」だけを決める。
  DB にも FiveM にも依存しないので単体テストできる。
]]
TreasuryMath = {}

--- 取引 1 件から作る記帳。税が無い取引は記帳しない（nil を返す）。
--- @param tx table dyn_economy:committed のペイロード
--- @param state string|nil 店舗の所在州。不明なら 'unassigned'
--- @return table|nil { direction, source, amount, refType, refId, note, state }
function TreasuryMath.entryForCommit(tx, state)
    if type(tx) ~= 'table' then return nil end
    local tax = tonumber(tx.tax)
    if not tax or tax <= 0 then return nil end
    if tx.direction ~= 'sell' and tx.direction ~= 'buy' then return nil end

    return {
        direction = 'in',
        -- 買取（プレイヤーが売る）と販売（プレイヤーが買う）で税の出どころが違う。
        -- 後から「どちらでどれだけ集まったか」を分けて見たいので別々に記録する。
        source    = (tx.direction == 'sell') and 'npc_tax_sell' or 'npc_tax_buy',
        amount    = tax,
        refType   = 'dyn_npc_tx',
        refId     = tx.txId,
        note      = tx.item and (tx.item .. ' x' .. tostring(tx.qty)) or nil,
        state     = state or 'unassigned',
    }
end

--- 取り消された取引の打ち消し記帳。
--- 取り消しで税だけ国庫に残ると、集めていない金が積み上がる。
function TreasuryMath.entryForVoid(tx, state)
    local entry = TreasuryMath.entryForCommit(tx, state)
    if not entry then return nil end
    entry.direction = 'out'
    entry.source    = 'void_refund'
    entry.note      = '取り消し: ' .. (entry.note or '')
    return entry
end

--- 個人間取引（dyn_trade）の手数料を記帳する。
--- P2P 取引はどの州で成立したか特定できないので、既定では state 未指定
--- （'unassigned' 扱い）になる。
--- @param payload table dyn_trade:fee のペイロード { amount, sessionId, note }
function TreasuryMath.entryForP2PFee(payload, state)
    if type(payload) ~= 'table' then return nil end
    local amount = tonumber(payload.amount)
    if not amount or amount <= 0 then return nil end

    return {
        direction = 'in',
        source    = 'p2p_trade_fee',
        amount    = amount,
        refType   = 'dyn_p2p_tx',
        refId     = payload.sessionId,
        note      = payload.note,
        state     = state or 'unassigned',
    }
end

--[[
  「YYYY-Www」形式の週ラベル。年初からの経過日数 ÷ 7 を切り上げた簡略版で、
  ISO 8601 の週番号（年またぎの厳密な規則）ではない。組合補助金の週次予算
  サイクルが「毎週リセットされる連番」であれば足りるので、厳密な ISO 週より
  実装をシンプルに保つことを優先している。UTC 基準で決定的に計算する。
]]
function TreasuryMath.weekLabel(unixTime)
    local t = os.date('!*t', unixTime)
    local dayOfYear = tonumber(os.date('!%j', unixTime))
    local week = math.floor((dayOfYear - 1) / 7) + 1
    return ('%04d-W%02d'):format(t.year, week)
end

--- 残高に記帳を適用した結果
function TreasuryMath.apply(balance, entry)
    balance = tonumber(balance) or 0
    if not entry then return balance end
    if entry.direction == 'in' then return balance + entry.amount end
    return balance - entry.amount
end

--[[
  補助金に回せる額（§9.2）。

  国庫をすべて配ると準備金が尽きる。逆に貯め続けると流通から金が消えたままになり、
  デフレ圧になる。月間税収の reserveMonths か月分を残し、超過分だけを予算にする。
]]
function TreasuryMath.spendable(balance, monthlyIncome, reserveMonths)
    balance       = tonumber(balance) or 0
    monthlyIncome = tonumber(monthlyIncome) or 0
    reserveMonths = tonumber(reserveMonths) or 0
    local reserve = monthlyIncome * reserveMonths
    local free    = balance - reserve
    return free > 0 and free or 0, reserve
end
