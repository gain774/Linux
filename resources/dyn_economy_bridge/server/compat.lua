--[[
  他リソースとの干渉を起動時に検出・回避する。

  検出した内容はコンソールに出すだけで、他リソースの設定は書き換えない。
  勝手に他人のリソースを変更するほうが事故が大きいので、
  こちらが降りるか（品目の無効化）、警告を出すかのどちらかに留める。
]]
DynCompat = {}

local function warn(fmt, ...)
    print(('^3[dyn_economy_bridge] ' .. fmt .. '^0'):format(...))
end

local function info(fmt, ...)
    print(('[dyn_economy_bridge] ' .. fmt):format(...))
end

--[[
  dyn_economy が扱う品目を vorp_inventory の登録内容と突き合わせる。

  vorp_inventory に登録が無い品目を残すと:
    - 売買のたびに「Item [x] does not exist in DB.」がコンソールに出続ける
    - canCarryItem が常に false を返すので、購入が全部 cannot_carry で失敗する
  武器は items テーブルではなく loadout 側で管理されているので、
  ここで自動的に弾かれる（addItem / subItem は武器に使えない）。
]]
--- deps を渡すと外部リソースを使わずに動く（テスト用）
function DynCompat.validateItems(deps)
    deps = deps or {
        listItems  = function() return exports.dyn_economy:ListItems() end,
        getItemDB  = function(name) return exports.vorp_inventory:getItemDB(name) end,
        setEnabled = function(name, on) return exports.dyn_economy:SetItemEnabled(name, on) end,
    }
    local names = deps.listItems() or {}
    local missing, degradable = {}, {}

    for _, name in ipairs(names) do
        local dbItem = deps.getItemDB(name)
        if not dbItem then
            missing[#missing + 1] = name
            deps.setEnabled(name, false)
        elseif not BridgeConfig.compat.allowDegradable
            and (tonumber(dbItem.maxDegradation) or 0) > 0 then
            degradable[#degradable + 1] = name
            deps.setEnabled(name, false)
        end
    end

    if #missing > 0 then
        warn('vorp_inventory に登録が無いため %d 品目を無効化しました: %s',
            #missing, table.concat(missing, ', '))
        warn('  items テーブルに追加するか、config/items.lua から外してください')
        warn('  （武器は addItem / subItem で扱えないので、この Mod では扱えません）')
    end

    if #degradable > 0 then
        warn('劣化アイテムのため %d 品目を無効化しました: %s',
            #degradable, table.concat(degradable, ', '))
        warn('  価格エンジンは個体の劣化度を見ないので、状態の悪い品を満額で売れてしまいます')
        warn('  承知のうえで扱うなら BridgeConfig.compat.allowDegradable = true')
    end

    info('品目の突き合わせ完了: %d 件中 %d 件を無効化', #names, #missing + #degradable)
    return missing, degradable
end

--[[
  vorp_stores の RandomPrices / DynamicStore が有効なままだと、
  価格と在庫を二重に制御することになる。

  - RandomPrices … 再起動のたびに価格をランダムに振り直す。需給の結果が毎回消える
  - DynamicStore … 店舗ごとの在庫上限を独自に持つ。仮想在庫と二重管理になる

  config.lua をテキストとして読んで検出する。他リソースの shared_script は
  こちらから参照できないため、これが実用的な唯一の方法。
]]
--- config.lua の中身から衝突している設定を数える。純粋関数なのでテストできる
function DynCompat.findStoreConflicts(raw)
    local found = {}
    if not raw then return found end
    for line in raw:gmatch('[^\r\n]+') do
        if not line:match('^%s*%-%-') then                     -- コメント行は無視
            local code = line:gsub('%-%-.*$', '')              -- 行末コメントも落とす
            for _, key in ipairs({ 'RandomPrices', 'DynamicStore' }) do
                if code:match(key .. '%s*=%s*true') then
                    found[key] = (found[key] or 0) + 1
                end
            end
        end
    end
    return found
end

function DynCompat.checkStoreConflicts()
    if GetResourceState('vorp_stores') ~= 'started' then return false end

    local raw = LoadResourceFile('vorp_stores', 'config.lua')
    if not raw then
        warn('vorp_stores の config.lua を読めませんでした。RandomPrices と DynamicStore を手で確認してください')
        return false
    end

    local found = DynCompat.findStoreConflicts(raw)
    if next(found) == nil then return false end

    warn('vorp_stores と設定が衝突しています:')
    for key, count in pairs(found) do
        warn('  %s = true が %d 箇所。dyn_economy と二重に価格／在庫を制御します', key, count)
    end
    warn('  vorp_stores の config.lua で両方 false にしてください')
    return true
end

function DynCompat.run()
    local c = BridgeConfig.compat or {}
    if c.validateItems ~= false then DynCompat.validateItems() end
    if c.warnStoreConflicts ~= false then DynCompat.checkStoreConflicts() end
end
