--[[
  この resource 専用の VORP アダプタ。

  dyn_economy_bridge/server/vorp.lua と役割が重なって見えるが、あちらは
  「NPC と決済する」ための片方向の口座操作しか公開していない
  （GetItemCount / GetMoney / GetIdentifier のみ export）。
  個人間取引は双方向に現物・現金を動かすので、ここだけで完結する薄いラッパを
  別に持つ（"フレームワークごとに書き換える羽目になる" のを避ける、という
  bridge 側と同じ理由でリソースを分けている）。

  確認に使ったバージョン: vorp_core 3.3 / vorp_inventory 4.5
]]

local Core

CreateThread(function()
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

TradeAdapter = {}

function TradeAdapter.isReady()
    return Core ~= nil
end

--- Callback 登録など、アダプタに無い vorp_core の機能が要る箇所向け
function TradeAdapter.core()
    return Core
end

function TradeAdapter.getName(source)
    local c = character(source)
    if not c then return nil end
    local full = ((c.firstname or '') .. ' ' .. (c.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return full ~= '' and full or nil
end

--- 監査ログに使う識別子。dyn_economy_bridge と同じくキャラクター単位
function TradeAdapter.getIdentifier(source)
    local c = character(source)
    if not c then return nil end
    return tostring(c.charIdentifier)
end

function TradeAdapter.getMoney(source)
    local c = character(source)
    return c and (tonumber(c.money) or 0) or 0
end

function TradeAdapter.addMoney(source, amount)
    if not amount or amount <= 0 then return true end
    local c = character(source)
    if not c then return false end
    c.addCurrency(0, amount)
    return true
end

--- 残高チェックは呼び出し側の責任（dyn_economy_bridge/server/vorp.lua と同じ方針）
function TradeAdapter.removeMoney(source, amount)
    if not amount or amount <= 0 then return true end
    local c = character(source)
    if not c then return false end
    c.removeCurrency(0, amount)
    return true
end

function TradeAdapter.getItemCount(source, item)
    return tonumber(exports.vorp_inventory:getItemCount(source, nil, item)) or 0
end

function TradeAdapter.addItem(source, item, qty)
    return exports.vorp_inventory:addItem(source, item, qty) == true
end

function TradeAdapter.removeItem(source, item, qty)
    return exports.vorp_inventory:subItem(source, item, qty) == true
end

function TradeAdapter.canCarry(source, item, qty)
    return exports.vorp_inventory:canCarryItem(source, item, qty) == true
end

--- 提示品を選ぶメニュー用。所持品の一覧を取る
function TradeAdapter.listInventory(source)
    local ok, items = pcall(function() return exports.vorp_inventory:getUserInventoryItems(source) end)
    if not ok or type(items) ~= 'table' then return {} end
    return items
end

function TradeAdapter.notify(source, text)
    if not Core then return end
    Core.NotifyRightTip(source, text, Config.notifyDuration or 4000)
end

function TradeAdapter.registerUsableItem(item, cb)
    exports.vorp_inventory:registerUsableItem(item, cb, GetCurrentResourceName())
end
