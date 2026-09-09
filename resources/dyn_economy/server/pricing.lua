--[[
  価格スタック（設計ドキュメント §4.6）

  最終価格の決まり方はこのファイルの composeBase() と quote() に閉じている。
  価格の決定が複数箇所に散らばると後から誰も追えなくなるので、意図的に 1 箇所へ集約する。
]]
DynPricing = {}

--- 個人補正（§11.1 の連投ペナルティ）。Phase 3 以降で実装するためのフック。
--- 今は常に 1.0 を返すが、呼び出し位置と breakdown への記録だけ先に用意しておく。
function DynPricing.personalMultiplier(_identifier, _item, _direction)
    return 1.0
end

--- 成長曲線による補正（§7）。既定 OFF なので 1.0。
function DynPricing.incomeMultiplier()
    return DynState.econ('income_mult') or 1.0
end

--- 価格スタック 1〜4 段目。需給（5 段目）より前の「基準価格」を組み立てる。
local function composeBase(it, direction, identifier)
    local b = {}
    b.index  = it.priceIndex                                       -- 1. 相対価値
    b.scale  = DynState.econ('currency_scale')                     -- 2. 通貨スケール
    b.cpi    = Config.PriceLevel.enabled and DynState.econ('cpi_mult') or 1.0  -- 3. 物価水準
    b.cat    = Config.PriceLevel.enabled and DynState.categoryMult(it.category) or 1.0
    -- 4. 成長曲線補正は金のソース側（プレイヤーが NPC に売る側）にだけ掛ける
    b.income = (direction == 'sell') and DynPricing.incomeMultiplier() or 1.0
    b.personal = DynPricing.personalMultiplier(identifier, it.item, direction)
    local p0 = b.index * b.scale * b.cpi * b.cat * b.income
    return p0, b
end

local function taxRates(it)
    if not Config.Tax.enabled then return 0, 0 end
    local t = DynMath.taxFromSpread(it.spread)
    local share = DynMath.clamp(Config.Tax.sellShare or 0.5, 0, 1)
    local taxSell = DynMath.clamp(2 * t * share, 0, 0.95)
    local taxBuy  = math.max(2 * t * (1 - share), 0)
    return taxSell, taxBuy
end

--- 需給の下限倍率。レシピ原価が分かっていればそちらへ引き上げる（§5.3）
local function minMultFor(it, p0)
    if not Config.Recipes.enabled then return it.minMult end
    return DynMath.effectiveMinMult(p0, it.minMult, it.maxMult, it.matCost, Config.Recipes.craftMargin)
end

--- 共通の見積り。direction は 'sell'（プレイヤーが NPC に売る）か 'buy'。
--- 在庫は動かさない。
function DynPricing.quote(itemName, qty, direction, identifier)
    qty = tonumber(qty) or 0
    if qty <= 0 then return nil, 'qty_invalid' end

    local it = DynState.get(itemName)
    if not it then return nil, 'unknown_item' end
    if not it.enabled then return nil, 'item_disabled' end
    if direction == 'sell' and not it.npcSellable then return nil, 'not_sellable' end
    if direction == 'buy'  and not it.npcBuyable  then return nil, 'not_buyable' end

    local p0, b = composeBase(it, direction, identifier)
    local minMult = minMultFor(it, p0)
    b.floor = (minMult > it.minMult) and minMult or nil
    b.cap   = it.maxMult

    -- 需給が無効なら基準価格で固定（クランプも積分も不要）
    local elasticity = Config.Dynamic.enabled and it.elasticity or 0

    local fair
    if direction == 'sell' then
        fair = DynMath.totalSell(p0, it.targetStock, elasticity, minMult, it.maxMult, it.stock, qty)
    else
        fair = DynMath.totalBuy(p0, it.targetStock, elasticity, minMult, it.maxMult, it.stock, qty)
    end
    fair = fair * b.personal

    local taxSell, taxBuy = taxRates(it)
    local total, tax
    if direction == 'sell' then
        b.tax = 1 - taxSell
        total = fair * b.tax
        tax   = fair - total
    else
        b.tax = 1 + taxBuy
        total = fair * b.tax
        tax   = total - fair
    end

    total = DynMath.round(total, Config.Currency.step)
    tax   = DynMath.round(tax, Config.Currency.step)

    -- 表示用の現在単価（数量 1 個ぶんの限界価格）
    local unitNow = DynMath.clamp(
        DynMath.rawUnitPrice(p0, it.targetStock, it.stock, elasticity),
        p0 * minMult, p0 * it.maxMult) * b.personal * b.tax

    if direction == 'sell' then it.cachedBuy = unitNow else it.cachedSell = unitNow end

    return {
        item        = itemName,
        direction   = direction,
        qty         = qty,
        total       = total,
        unitAvg     = total / qty,
        priceNow    = unitNow,
        tax         = tax,
        stock       = it.stock,
        basePrice   = p0,
        breakdown   = b,
    }
end

function DynPricing.quoteSell(itemName, qty, identifier)
    return DynPricing.quote(itemName, qty, 'sell', identifier)
end

function DynPricing.quoteBuy(itemName, qty, identifier)
    return DynPricing.quote(itemName, qty, 'buy', identifier)
end

--[[
  確定。仮想在庫を動かし、取引を記録する。

  重要: このリソースは金銭とインベントリを触らない。
  呼び出し側（店舗リソース／ブリッジ）が所持金と現物の検証・移動を済ませたうえで、
  価格の確定としてこれを呼ぶ。責務を分けておかないと、
  フレームワークごとにこのファイルを書き換える羽目になる。
]]
function DynPricing.commit(identifier, itemName, qty, direction, shopId)
    local q, err = DynPricing.quote(itemName, qty, direction, identifier)
    if not q then return nil, err end

    local it = DynState.get(itemName)
    local before = it.stock
    DynState.addStock(itemName, direction == 'sell' and qty or -qty)
    local after = DynState.get(itemName).stock

    q.stockBefore = before
    q.stockAfter  = after
    q.txId        = DynLedger.record(identifier, q, shopId)
    return q
end

--[[
  確定した取引を取り消す（仮想在庫を戻し、取引を voided にする）。

  決済の途中で失敗したときに呼ぶ。呼び出し側が「金は動かせなかったが在庫だけ動いた」
  という状態を残さないための逃げ道であり、通常の運用では使わない。
]]
function DynPricing.void(q)
    if not q or q.voided then return false end
    DynState.addStock(q.item, q.direction == 'sell' and -q.qty or q.qty)
    DynLedger.void(q.txId)
    q.voided = true
    return true
end

function DynPricing.commitSell(identifier, itemName, qty, shopId)
    return DynPricing.commit(identifier, itemName, qty, 'sell', shopId)
end

function DynPricing.commitBuy(identifier, itemName, qty, shopId)
    return DynPricing.commit(identifier, itemName, qty, 'buy', shopId)
end

--- 原価計算のための素材単価（§5.2）。
--- レシピ原価による下限（§5.3）を意図的に無視する。
--- 原価が価格を押し上げ、その価格でまた原価を計算する、という循環を避けるため。
function DynPricing.materialUnitPrice(itemName)
    local it = DynState.get(itemName)
    if not it or not it.enabled then return nil end
    local p0 = composeBase(it, 'sell', nil)
    local elasticity = Config.Dynamic.enabled and it.elasticity or 0
    return DynMath.clamp(
        DynMath.rawUnitPrice(p0, it.targetStock, it.stock, elasticity),
        p0 * it.minMult, p0 * it.maxMult)
end
