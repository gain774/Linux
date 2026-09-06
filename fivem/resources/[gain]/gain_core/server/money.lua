-- 所持金の操作。判定はすべてサーバー側で行い、クライアントからの数値は使わない。
--
-- 上限を超える加算は「額を減らして通す」のではなく拒否する。
-- 部分適用を許すと、預入・引出・送金のような「片方を減らして片方を増やす」
-- 構成で補償ができなくなる。減らした側をいくら戻すべきかが呼び出し側から
-- 見えないためで、実際にそれで金銭が消える経路があった。
--
-- 残高を変えたら必ず台帳に積む。書き込みは Ledger が1箇所で行う。

Money = {}

local ACCOUNTS = { cash = true, bank = true }

--- 1回の操作額として妥当か。残高上限とは別の概念で、こちらは「一度に動かせる額」。
local function sanitize(amount)
    amount = tonumber(amount)
    if not amount then return nil end

    amount = math.floor(amount)
    if amount <= 0 then return nil end
    if amount > Config.MoneyLimit then return nil end

    return amount
end

--- reason は文字列でも table でもよい。table なら台帳に kind と相手先を残せる。
--- 旧来の文字列呼び出しをそのまま通すための型ディスパッチ。
local function meta(m)
    if type(m) == 'table' then
        return m.kind or 'adjust', m.reason or '', m.counterparty or ''
    end
    return 'adjust', m or '', ''
end

--- 残高を取得する。
function Money.get(player, account)
    if not player or not ACCOUNTS[account] then return 0 end
    return player.money[account] or 0
end

--- 差分を適用する。すべての増減はここを通る。
--- メモリを変える前に検証を終える。丸めない。
---@return boolean ok
---@return table result { applied, balance, error }
function Money.apply(player, account, delta, m)
    if not player then return false, { error = 'no_player' } end
    if not ACCOUNTS[account] then return false, { error = 'invalid' } end

    delta = tonumber(delta)
    if not delta or delta ~= delta or delta == 0 then
        return false, { error = 'invalid' }
    end
    delta = math.floor(delta)

    local before = player.money[account] or 0
    local after = before + delta

    if after < 0 then
        return false, { error = 'insufficient', balance = before }
    end
    if after > Config.MoneyLimit then
        -- 丸めない。呼び出し側が検出できない消失を作らないため
        return false, { error = 'limit', balance = before }
    end

    player.money[account] = after
    player.sync()

    local kind, reason, counterparty = meta(m)
    Ledger.push({
        citizenid = player.citizenid, account = account,
        delta = delta, balance = after,
        kind = kind, reason = reason, counterparty = counterparty,
    })

    GainLog.write('money', delta > 0 and '入金' or '出金', {
        player = player.name, citizenid = player.citizenid,
        account = account, amount = math.abs(delta), balance = after,
        reason = reason ~= '' and reason or '-',
    })

    return true, { applied = delta, balance = after }
end

--- 加算する。上限を超えるなら false。丸めない。
function Money.add(player, account, amount, m)
    amount = sanitize(amount)
    if not amount then return false end
    return (Money.apply(player, account, amount, m))
end

--- 減算する。残高不足なら false を返し、残高は変えない。
function Money.remove(player, account, amount, m)
    amount = sanitize(amount)
    if not amount then return false end
    return (Money.apply(player, account, -amount, m))
end

--- 残高を直接指定する（管理操作用）。差分を台帳に載せるので照合が壊れない。
function Money.set(player, account, amount, m)
    if not player or not ACCOUNTS[account] then return false end

    amount = tonumber(amount)
    if not amount then return false end
    amount = math.floor(amount)
    if amount < 0 or amount > Config.MoneyLimit then return false end

    local delta = amount - (player.money[account] or 0)
    if delta == 0 then return true end

    if type(m) ~= 'table' then m = { kind = 'adjust', reason = m } end
    m.kind = m.kind or 'adjust'
    return (Money.apply(player, account, delta, m))
end

--- 口座間を移す。両側を先に検査してから同時に動かす。
--- 片方だけ反映されることが原理的に起きないので、預入・引出はこれを使う。
function Money.move(player, from, to, amount, m)
    if not player or not ACCOUNTS[from] or not ACCOUNTS[to] or from == to then
        return false, 'invalid'
    end

    amount = sanitize(amount)
    if not amount then return false, 'invalid' end

    local a, b = player.money[from] or 0, player.money[to] or 0
    if a - amount < 0 then return false, 'insufficient' end
    if b + amount > Config.MoneyLimit then return false, 'limit' end

    if type(m) ~= 'table' then m = { kind = 'move', reason = m } end

    local ok = Money.apply(player, from, -amount, m)
    if not ok then return false, 'failed' end

    ok = Money.apply(player, to, amount, m)
    if not ok then
        -- 事前検査を通しているので基本起きない。起きたら戻す
        Money.apply(player, from, amount, { kind = 'refund', reason = '移動の失敗を戻した' })
        return false, 'failed'
    end

    return true
end
