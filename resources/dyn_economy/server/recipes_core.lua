--[[
  レシピ原価の再帰計算（設計ドキュメント §5.2）

  DB にも FiveM にも依存しない。呼び出し側が ctx で
  レシピ表と素材価格の引き方を注入する。素の Lua でテストできる。

  ctx = {
    recipes = { [outputItem] = { outputQty = n, inputs = { {item=, qty=}, ... } }, ... },
    priceOf = function(item) -> number|nil     -- 素材の現在買値
    fallbackPrice = function(item) -> number|nil -- 価格未定義の素材の代替値（任意）
    maxDepth = 6,                              -- 既定 6
  }
]]

local R = {}

R.DEFAULT_MAX_DEPTH = 6

local function priceFor(item, ctx, memo)
    local cached = memo.price[item]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    local p = ctx.priceOf and ctx.priceOf(item) or nil
    if p == nil and ctx.fallbackPrice then
        p = ctx.fallbackPrice(item)
    end
    memo.price[item] = (p == nil) and false or p
    return p
end

local function costOf(item, ctx, memo, visiting, depth)
    local cached = memo.cost[item]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end

    local recipe = ctx.recipes[item]
    if not recipe then return nil end                    -- 素材そのもの。原価は持たない
    if visiting[item] then return nil end                -- 循環参照
    if depth > (ctx.maxDepth or R.DEFAULT_MAX_DEPTH) then return nil end

    visiting[item] = true
    local total = 0
    for _, input in ipairs(recipe.inputs or {}) do
        -- 素材にもレシピがあれば、その原価を優先して使う（再帰）
        local sub = costOf(input.item, ctx, memo, visiting, depth + 1)
        local unit = sub or priceFor(input.item, ctx, memo)
        if unit == nil then
            visiting[item] = nil
            return nil                                    -- 値段の付けようがない素材が混ざっている
        end
        total = total + unit * input.qty
    end
    visiting[item] = nil

    local outputQty = recipe.outputQty or 1
    if outputQty <= 0 then return nil end
    local result = total / outputQty
    memo.cost[item] = result
    return result
end

local function newMemo() return { cost = {}, price = {} } end

--- 単一アイテムの原価。計算できなければ nil
function R.computeCost(item, ctx, memo)
    return costOf(item, ctx, memo or newMemo(), {}, 1)
end

--- 複数アイテムの原価をまとめて計算する。素材価格とサブレシピはメモ化されて共有される
function R.computeCostAll(items, ctx)
    local memo = newMemo()
    local out = {}
    for _, item in ipairs(items) do
        out[item] = costOf(item, ctx, memo, {}, 1)
    end
    return out
end

_G.DynRecipesCore = R
return R
