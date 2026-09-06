-- 台帳。残高の永続化と取引履歴を一手に引き受ける。
--
-- 設計仕様は「残高の変更は必ず取引履歴を伴い、残高は履歴から再現できる」と
-- 定めている。これを Lua の規約で守ろうとすると、経路を1つ足すたびに
-- 書き忘れが生まれる。だから構造で守る。
--
--   ・gain_characters の cash / bank を書く SQL はここだけ
--   ・UPDATE と INSERT gain_transactions は必ず同じトランザクション
--   ・更新は相対（cash = cash + ?）。絶対代入をやめることで、
--     オフライン入金など他経路の書き込みを踏み潰さなくなる
--
-- 不変条件: SUM(gain_transactions.delta) == gain_characters.<account>

Ledger = {}

local pending = {}
local scheduled = false

--- 台帳に1行積む。実際の書き込みは同じ tick の終わりにまとめて行う。
---@param e table { citizenid, account, delta, balance, kind, amount, counterparty, reason }
function Ledger.push(e)
    pending[#pending + 1] = e

    -- 常駐スレッドは作らない。積まれたときだけ1回予約する
    if not scheduled then
        scheduled = true
        SetTimeout(0, function() Ledger.flush() end)
    end
end

--- 積まれた分を1トランザクションで書き出す。
function Ledger.flush(sync)
    scheduled = false
    if #pending == 0 then return end

    local batch = pending
    pending = {}

    -- キャラクターごとに差分をまとめる。1人が同じ tick に複数動いても1回の UPDATE で済む
    local delta = {}
    for _, e in ipairs(batch) do
        local d = delta[e.citizenid]
        if not d then d = { cash = 0, bank = 0 }; delta[e.citizenid] = d end
        d[e.account] = (d[e.account] or 0) + e.delta
    end

    local queries = {}
    for citizenid, d in pairs(delta) do
        queries[#queries + 1] = {
            query = 'UPDATE gain_characters SET cash = cash + ?, bank = bank + ? WHERE citizenid = ?',
            values = { d.cash, d.bank, citizenid },
        }
    end
    for _, e in ipairs(batch) do
        queries[#queries + 1] = {
            query = [[
                INSERT INTO gain_transactions
                    (citizenid, account, kind, amount, delta, balance, counterparty, reason)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ]],
            values = {
                e.citizenid, e.account, e.kind or 'adjust',
                math.abs(e.delta), e.delta, e.balance or 0,
                e.counterparty or '', e.reason or '',
            },
        }
    end

    local function done(ok)
        if ok then return end
        -- ここで失敗すると残高と台帳がずれる。メモリはロールバックしない
        -- （事後のロールバックは二重支払いを生む）。大きく鳴らして検算に任せる
        GainLog.write('error', '台帳の書き込みに失敗', { rows = #batch })
    end

    if sync then
        done(MySQL.transaction.await(queries))
    else
        MySQL.transaction(queries, done)
    end
end

--- 退出時・リソース停止時に使う。取りこぼしを残さない。
function Ledger.flushNow()
    Ledger.flush(true)
end
