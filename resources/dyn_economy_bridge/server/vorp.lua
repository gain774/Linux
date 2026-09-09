--[[
  VORP アダプタ（設計ドキュメント §10.1）

  確認に使ったバージョン: vorp_core 3.3 / vorp_inventory 4.5

  API の要点:
    Core            = exports.vorp_core:GetCore()          -- 'getCore' イベントは非推奨
    User            = Core.getUser(source)
    Character       = User.getUsedCharacter                -- 関数ではなくプロパティ
    Character.addCurrency(type, amount) / removeCurrency(type, amount)
                       type: 0 = ドル / 1 = ゴールド / 2 = ROL
    exports.vorp_inventory:addItem(source, name, amount, metadata, cb, ...)
    exports.vorp_inventory:subItem(source, name, amount, metadata, cb, ...)
    exports.vorp_inventory:getItemCount(source, cb, itemName, metadata, percentage)
                       ※ cb が第 2 引数。順番を間違えやすい
    exports.vorp_inventory:canCarryItem(source, itemName, amount, cb)

  vorp_inventory の各 export は cb を省略すると戻り値を同期的に返す
  （内部の respond() が cb を呼びつつ値も return する）。ここでは同期形で使う。
]]

local Core

CreateThread(function()
    -- vorp_core の起動順に依存しないよう、取れるまで待つ
    while not Core do
        local ok, core = pcall(function() return exports.vorp_core:GetCore() end)
        if ok and core then
            Core = core
        else
            Wait(500)
        end
    end
end)

local function character(source)
    if not Core then return nil end
    local user = Core.getUser(source)
    if not user then return nil end
    return user.getUsedCharacter
end

--- metadata は「未指定なら必ず nil」で渡すこと。
--- vorp_inventory は `if metadata then` で分岐するので、空テーブル {} を渡すと
--- Lua では truthy になり「メタデータ付きアイテムを探す」経路に入って 0 件になる。
local function meta(m)
    if m and next(m) ~= nil then return m end
    return nil
end

local VorpAdapter = {
    name = 'vorp',
}

function VorpAdapter.isReady()
    return Core ~= nil
end

--- 取引の主体はアカウントではなくキャラクター。
--- 1 アカウントで複数キャラを持つ運用があるので、財布が別なら経済上も別人として扱う。
function VorpAdapter.getIdentifier(source)
    local c = character(source)
    if not c then return nil end
    return tostring(c.charIdentifier)
end

--- 分析用。同一アカウントの複数キャラをまとめて見たいときに使う
function VorpAdapter.getAccountIdentifier(source)
    local c = character(source)
    return c and c.identifier or nil
end

function VorpAdapter.getMoney(source)
    local c = character(source)
    if not c then return 0 end
    if BridgeConfig.currency == 1 then return tonumber(c.gold) or 0 end
    if BridgeConfig.currency == 2 then return tonumber(c.rol) or 0 end
    return tonumber(c.money) or 0
end

function VorpAdapter.addMoney(source, amount)
    if not amount or amount <= 0 then return false end
    local c = character(source)
    if not c then return false end
    c.addCurrency(BridgeConfig.currency, amount)
    return true
end

--- VORP の removeCurrency は残高を検査せずマイナスまで引く。
--- 残高の確認は呼び出し側（txflow）の責任で、ここでは行わない。
function VorpAdapter.removeMoney(source, amount)
    if not amount or amount <= 0 then return false end
    local c = character(source)
    if not c then return false end
    c.removeCurrency(BridgeConfig.currency, amount)
    return true
end

function VorpAdapter.addItem(source, item, qty, metadata)
    return exports.vorp_inventory:addItem(source, item, qty, meta(metadata)) == true
end

function VorpAdapter.removeItem(source, item, qty, metadata)
    return exports.vorp_inventory:subItem(source, item, qty, meta(metadata)) == true
end

function VorpAdapter.getItemCount(source, item, metadata)
    return tonumber(exports.vorp_inventory:getItemCount(source, nil, item, meta(metadata))) or 0
end

function VorpAdapter.canCarry(source, item, qty)
    return exports.vorp_inventory:canCarryItem(source, item, qty) == true
end

function VorpAdapter.notify(source, text)
    if not BridgeConfig.notify or not Core then return end
    Core.NotifyRightTip(source, text, BridgeConfig.notifyDuration or 4000)
end

_G.DynAdapters = _G.DynAdapters or {}
_G.DynAdapters.vorp = VorpAdapter
