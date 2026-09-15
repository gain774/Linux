--[[
  レシピの取り込み（設計ドキュメント §5.1）

  vorp_crafting の config.lua をテキストとして読み、サンドボックスで評価して
  Config.Crafting を取り出す。他リソースの shared_script は直接参照できないので、
  これが実用的な方法。

  FiveM にも DB にも依存しない。素の Lua でテストできる。
]]
RecipeImport = {}

RecipeImport.SOURCE = 'vorp_crafting'

--[[
  設定ファイルを安全に評価する。

  評価するのは他人の設定ファイルなので、環境は空のテーブルから作り、
  io / os / require などは渡さない。設定でよく使われる関数だけスタブする。
]]
function RecipeImport.evaluate(source, chunkName)
    if type(source) ~= 'string' then return nil, 'not_a_string' end

    local env = {
        -- 設定ファイルが素で使う可能性のあるものだけ
        pairs = pairs, ipairs = ipairs, type = type, tonumber = tonumber, tostring = tostring,
        math = math, string = string, table = table, select = select,
        -- 座標などを書いていても落ちないようにする
        vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
        vec3    = function(x, y, z) return { x = x, y = y, z = z } end,
        GetHashKey = function() return 0 end,
        joaat      = function() return 0 end,
    }

    local chunk, err = load(source, chunkName or 'config', 't', env)
    if not chunk then return nil, 'syntax: ' .. tostring(err) end

    local ok, runErr = pcall(chunk)
    if not ok then return nil, 'runtime: ' .. tostring(runErr) end

    return env
end

--- 入力から「実際に消費される素材」だけを取り出す。
--- take = false は道具（消費されない）なので原価に入れない。
local function consumedInputs(entry)
    -- TakeItems が明示的に false なら、そのレシピは何も消費しない
    if entry.TakeItems == false then return nil, 'no_items_taken' end

    local merged, order = {}, {}
    for _, item in ipairs(entry.Items or {}) do
        if item.name and item.take ~= false then
            local qty = tonumber(item.count) or 0
            if qty > 0 then
                if not merged[item.name] then
                    merged[item.name] = 0
                    order[#order + 1] = item.name
                end
                -- 同じ素材が複数行に分かれていることがあるので足し合わせる
                merged[item.name] = merged[item.name] + qty
            end
        end
    end

    if #order == 0 then return nil, 'no_consumed_inputs' end

    local inputs = {}
    for i, name in ipairs(order) do
        inputs[i] = { item = name, qty = merged[name] }
    end
    return inputs
end

--[[
  vorp_crafting の Config.Crafting をレシピ表に変換する。

  戻り値: recipes, skipped
    recipes = { { outputItem, outputQty, inputs = { {item, qty}, ... } }, ... }
    skipped = { { label, reason }, ... }

  取り込まない条件と、その理由:
    weapon            武器は loadout 側で管理され addItem / subItem が効かない
    currency_mode     素材ではなく金で買うので、素材原価にならない
    multiple_rewards  出力が複数あると入力の原価をどう按分するか決められない。
                      黙って全額を片方に付けると下限価格が過大になる
    no_items_taken    TakeItems = false は何も消費しないので原価が無い
    duplicate_output  同じ品を作る別レシピ。最初のものだけ採り、残りは報告する
]]
function RecipeImport.parseVorpCrafting(source)
    local env, err = RecipeImport.evaluate(source, 'vorp_crafting/config.lua')
    if not env then return nil, err end

    local list = env.Config and env.Config.Crafting
    if type(list) ~= 'table' then return nil, 'no_crafting_table' end

    local recipes, skipped, seen = {}, {}, {}
    for _, entry in ipairs(list) do
        local label = entry.Text or '(無題)'

        local function skip(reason) skipped[#skipped + 1] = { label = label, reason = reason } end

        if entry.Type == 'weapon' then
            skip('weapon')
        elseif entry.UseCurrencyMode then
            skip('currency_mode')
        elseif type(entry.Reward) ~= 'table' or #entry.Reward == 0 then
            skip('no_reward')
        elseif #entry.Reward > 1 then
            skip('multiple_rewards')
        elseif not entry.Reward[1].name then
            skip('reward_without_name')
        else
            local inputs, why = consumedInputs(entry)
            if not inputs then
                skip(why)
            else
                local out = entry.Reward[1].name
                if seen[out] then
                    skip('duplicate_output')
                else
                    seen[out] = true
                    recipes[#recipes + 1] = {
                        outputItem = out,
                        outputQty  = tonumber(entry.Reward[1].count) or 1,
                        inputs     = inputs,
                    }
                end
            end
        end
    end

    return recipes, skipped
end

--- 取り込み結果の要約。--dry-run の表示に使う
function RecipeImport.summarize(recipes, skipped)
    local reasons = {}
    for _, s in ipairs(skipped or {}) do
        reasons[s.reason] = (reasons[s.reason] or 0) + 1
    end
    return { imported = #(recipes or {}), skipped = #(skipped or {}), reasons = reasons }
end

_G.RecipeImport = RecipeImport
return RecipeImport
