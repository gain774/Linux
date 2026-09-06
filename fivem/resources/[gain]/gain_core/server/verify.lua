-- 台帳の検算。コンソールから何度でも走らせる。
--
-- 「残高は履歴から再現できる」は口で言っても意味がないので、
-- 実データで照合する。ずれたら、どのキャラのどの口座がいくらずれたかを出す。

local function reconcile()
    local rows = MySQL.query.await([[
        SELECT c.citizenid,
               c.cash, c.bank,
               COALESCE(cs.s, 0) AS cash_ledger,
               COALESCE(bk.s, 0) AS bank_ledger
        FROM gain_characters c
        LEFT JOIN (SELECT citizenid, SUM(delta) s FROM gain_transactions
                   WHERE account = 'cash' GROUP BY citizenid) cs ON cs.citizenid = c.citizenid
        LEFT JOIN (SELECT citizenid, SUM(delta) s FROM gain_transactions
                   WHERE account = 'bank' GROUP BY citizenid) bk ON bk.citizenid = c.citizenid
    ]]) or {}

    local bad = 0
    for _, r in ipairs(rows) do
        for _, acc in ipairs({ 'cash', 'bank' }) do
            -- SUM() は文字列や小数で返ることがある。型を揃えてから比べる
            local balance = math.floor(tonumber(r[acc]) or 0)
            local ledger = math.floor(tonumber(r[acc .. '_ledger']) or 0)
            if balance ~= ledger then
                bad = bad + 1
                print(('[gain] NG %s %s: 残高 %d / 台帳 %d / 差 %+d')
                    :format(r.citizenid, acc, balance, ledger, balance - ledger))
            end
        end
    end

    print(('[gain] 検算: キャラ %d 件 / ずれ %d 件'):format(#rows, bad))
    if bad == 0 then print('[gain] SUM(delta) == 残高 が全口座で成立している') end
    return bad
end

--- 台帳の無い残高変動が残っていないか。account が空の行は移行前のもの。
local function orphans()
    local n = MySQL.scalar.await(
        "SELECT COUNT(*) FROM gain_transactions WHERE account = '' OR account IS NULL") or 0
    if n > 0 then
        print(('[gain] 注意: 口座の分からない履歴が %d 件ある（移行前の行）。照合から外している'):format(n))
    end
end

RegisterCommand('gainverify', function(src)
    if src ~= 0 then return end
    reconcile()
    orphans()
end, true)

exports('Reconcile', reconcile)
