--[[
  レシピ原価の再計算（§5）

  計算の本体は server/recipes_core.lua（純粋関数・単体テスト済み）にある。
  こちらは DB からレシピ表を読み、素材価格の引き方を注入する役目だけを持つ。
]]
DynRecipes = {}

local recipes = {}   -- outputItem -> { outputQty, inputs = { {item, qty}, ... } }

--- dyn_recipes / dyn_recipe_inputs を読み込む。
--- 各クラフトリソースからの取り込み（インポータ）は Phase 4 の作業で、
--- ここは「取り込まれた表を使う」側。
function DynRecipes.load()
    recipes = {}
    if not DynDb.isReady() then return 0 end

    local rows = DynDb.query('SELECT id, output_item, output_qty FROM dyn_recipes') or {}
    local byId = {}
    for _, r in ipairs(rows) do
        local entry = { outputQty = tonumber(r.output_qty) or 1, inputs = {} }
        recipes[r.output_item] = entry
        byId[r.id] = entry
    end

    local inputs = DynDb.query('SELECT recipe_id, item, qty FROM dyn_recipe_inputs') or {}
    for _, i in ipairs(inputs) do
        local entry = byId[i.recipe_id]
        if entry then
            entry.inputs[#entry.inputs + 1] = { item = i.item, qty = tonumber(i.qty) or 0 }
        end
    end

    local n = 0
    for _ in pairs(recipes) do n = n + 1 end
    return n
end

function DynRecipes.all() return recipes end

--- 全アイテムの原価を計算して DynState に書き戻す
function DynRecipes.refresh()
    if not Config.Recipes.enabled then return 0 end

    local ctx = {
        recipes  = recipes,
        maxDepth = Config.Recipes.maxDepth,
        priceOf  = function(item) return DynPricing.materialUnitPrice(item) end,
        -- 価格が未定義の素材は、その素材の相対価値をそのまま代替値にする
        fallbackPrice = function(item)
            local cfg = Items[item]
            if not cfg then return nil end
            return cfg.priceIndex * DynState.econ('currency_scale')
        end,
    }

    local targets = {}
    for name in pairs(recipes) do targets[#targets + 1] = name end
    local costs = DynRecipesCore.computeCostAll(targets, ctx)

    local n = 0
    for name, cost in pairs(costs) do
        if cost then
            DynState.setMatCost(name, cost)
            n = n + 1
        end
    end
    return n
end

function DynRecipes.costOf(itemName)
    local it = DynState.get(itemName)
    return it and it.matCost or nil
end
