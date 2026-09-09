--[[
  NPC 売買の決済フロー（設計ドキュメント §10）

  このファイルはフレームワークにも FiveM にも依存しない。
  adapter（所持金と現物の操作）と economy（価格の見積りと確定）を注入して使う。
  順序を間違えると金か現物が増えるので、素の Lua でテストできる形に切り出してある。

  deps = {
    adapter = { getIdentifier, getMoney, addMoney, removeMoney,
                addItem, removeItem, getItemCount, canCarry },
    economy = { quoteSell, quoteBuy, commitSell, commitBuy, void },
  }
]]

local F = {}

local function validQty(qty)
    return type(qty) == 'number' and qty > 0 and qty % 1 == 0
end

--[[
  プレイヤーが NPC に売る。

  順序の理由:
    現物を先に引く。引けなければ何も起きていない状態で止まれる。
    価格の確定（commit）は現物を引いた後。インベントリ操作は yield するので、
    その間に価格が動く可能性がある。**確定値は commit の戻り値であって見積りではない。**
    入金は最後。VORP の addCurrency は失敗しないので、ここまで来れば整合が崩れない。
]]
function F.sellToNpc(deps, source, item, qty, shopId)
    local a, econ = deps.adapter, deps.economy
    if not validQty(qty) then return nil, 'qty_invalid' end

    local identifier = a.getIdentifier(source)
    if not identifier then return nil, 'no_character' end

    -- 扱えない品目・数量はここで弾く。現物に触る前に落としたい
    local quote = econ.quoteSell(item, qty, identifier)
    if not quote or not quote.ok then
        return nil, (quote and quote.error) or 'quote_failed'
    end

    if a.getItemCount(source, item) < qty then return nil, 'not_enough_items' end

    if not a.removeItem(source, item, qty) then return nil, 'remove_item_failed' end

    local commit = econ.commitSell(identifier, item, qty, shopId)
    if not commit or not commit.ok then
        a.addItem(source, item, qty)          -- 現物を返す
        return nil, (commit and commit.error) or 'commit_failed'
    end

    a.addMoney(source, commit.total)
    return commit
end

--[[
  プレイヤーが NPC から買う。

  順序の理由:
    所持金の確認と価格の確定の間で yield してはいけない。yield すると、
    確認した残高と実際に引く額がズレる。canCarry（yield する）を先に済ませ、
    getMoney → commit → removeMoney を続けて実行する。
    現物の付与は最後で、失敗したら返金して取引を取り消す。
]]
function F.buyFromNpc(deps, source, item, qty, shopId)
    local a, econ = deps.adapter, deps.economy
    if not validQty(qty) then return nil, 'qty_invalid' end

    local identifier = a.getIdentifier(source)
    if not identifier then return nil, 'no_character' end

    local quote = econ.quoteBuy(item, qty, identifier)
    if not quote or not quote.ok then
        return nil, (quote and quote.error) or 'quote_failed'
    end

    if not a.canCarry(source, item, qty) then return nil, 'cannot_carry' end

    -- ここから現物付与まで yield しない
    local money  = a.getMoney(source)
    local commit = econ.commitBuy(identifier, item, qty, shopId)
    if not commit or not commit.ok then
        return nil, (commit and commit.error) or 'commit_failed'
    end

    if money < commit.total then
        econ.void(commit)
        return nil, 'not_enough_money'
    end

    a.removeMoney(source, commit.total)

    if not a.addItem(source, item, qty) then
        a.addMoney(source, commit.total)      -- 返金
        econ.void(commit)                     -- 仮想在庫と取引記録も戻す
        return nil, 'add_item_failed'
    end

    return commit
end

_G.DynTxFlow = F
return F
