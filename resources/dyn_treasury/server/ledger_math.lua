--[[
  国庫の出納の判定（純粋関数）。

  「その取引から税をいくら、どちら向きに記帳するか」だけを決める。
  DB にも FiveM にも依存しないので単体テストできる。
]]
TreasuryMath = {}

--- 取引 1 件から作る記帳。税が無い取引は記帳しない（nil を返す）。
--- @param tx table dyn_economy:committed のペイロード
--- @return table|nil { direction, source, amount, refType, refId, note }
function TreasuryMath.entryForCommit(tx)
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
    }
end

--- 取り消された取引の打ち消し記帳。
--- 取り消しで税だけ国庫に残ると、集めていない金が積み上がる。
function TreasuryMath.entryForVoid(tx)
    local entry = TreasuryMath.entryForCommit(tx)
    if not entry then return nil end
    entry.direction = 'out'
    entry.source    = 'void_refund'
    entry.note      = '取り消し: ' .. (entry.note or '')
    return entry
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
