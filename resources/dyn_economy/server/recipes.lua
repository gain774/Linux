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

--[[
  クラフトリソースからレシピを取り込む（§5.1）。

  既定はドライラン。差分を見てから適用する。
  自動では走らせない ── レシピ表は変わりにくいのに、取り込みを間違えると
  原価が狂って全品の下限価格が動く。起動のたびに黙って走る種類の処理ではない。
]]
function DynRecipes.import(opts)
    opts = opts or {}
    local resource = opts.resource or RecipeImport.SOURCE

    if GetResourceState(resource) == 'missing' then
        return nil, ('%s が見つかりません'):format(resource)
    end

    local raw = LoadResourceFile(resource, 'config.lua')
    if not raw then
        return nil, ('%s/config.lua を読めませんでした'):format(resource)
    end

    local recipes, skipped = RecipeImport.parseVorpCrafting(raw)
    if not recipes then
        return nil, ('解析に失敗しました: %s'):format(tostring(skipped))
    end

    local result = RecipeImport.summarize(recipes, skipped)
    result.recipes = recipes
    result.skippedList = skipped
    result.applied = false

    if not opts.apply then return result end
    if not DynDb.isReady() then return nil, 'DB がありません' end

    -- 取り込み元ごとに入れ替える。他の source で手で入れたレシピは残す。
    -- dyn_recipe_inputs は外部キーの ON DELETE CASCADE で一緒に消える。
    DynDb.execute('DELETE FROM dyn_recipes WHERE source = ?', { resource })

    for _, r in ipairs(recipes) do
        local id = DynDb.insert(
            'INSERT INTO dyn_recipes (output_item, output_qty, source) VALUES (?, ?, ?)',
            { r.outputItem, r.outputQty, resource })
        if id then
            for _, i in ipairs(r.inputs) do
                DynDb.execute(
                    'INSERT INTO dyn_recipe_inputs (recipe_id, item, qty) VALUES (?, ?, ?)',
                    { id, i.item, i.qty })
            end
        end
    end

    result.applied = true
    result.loaded  = DynRecipes.load()
    result.costed  = DynRecipes.refresh()
    return result
end

function DynRecipes.costOf(itemName)
    local it = DynState.get(itemName)
    return it and it.matCost or nil
end
