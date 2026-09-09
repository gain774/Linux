--[[
  店舗側の検証（純粋関数）。

  クライアントから来る値は何ひとつ信用しない。店舗 ID・品目・数量・方向は
  すべてここで突き合わせる。FiveM にも VORP にも依存しないので単体テストできる。
]]
ShopGuard = {}

--- 営業時間の判定。open == close または hours 未設定なら 24 時間営業。
--- 深夜をまたぐ設定（open 21 / close 7）にも対応する。
function ShopGuard.isOpen(shop, hour)
    local h = shop.hours
    if not h or h.open == h.close then return true end
    if h.open < h.close then
        return hour >= h.open and hour < h.close
    end
    return hour >= h.open or hour < h.close
end

--- その店舗がその方向でその品目を扱っているか
function ShopGuard.allows(shop, item, direction)
    local list = (direction == 'sell') and shop.sell or shop.buy
    if not list then return false end
    for _, name in ipairs(list) do
        if name == item then return true end
    end
    return false
end

--[[
  取引 1 件の検証。

  opts = {
    item, direction, hour, distance,
    now, lastTradeAt, cooldownMs, maxDistance,
  }
  戻り値: true / nil, エラーコード
]]
function ShopGuard.validate(shop, opts)
    if not shop then return nil, 'unknown_shop' end
    if opts.direction ~= 'sell' and opts.direction ~= 'buy' then return nil, 'bad_direction' end

    -- 距離はメニューを開いた時だけでなく取引のたびに見る。
    -- 開いたまま移動する／座標を偽装する経路を塞ぐため。
    if opts.distance == nil or opts.distance > opts.maxDistance then return nil, 'out_of_range' end
    if not ShopGuard.isOpen(shop, opts.hour) then return nil, 'closed' end

    if opts.item then
        if not ShopGuard.allows(shop, opts.item, opts.direction) then return nil, 'item_not_traded' end
    end

    if opts.lastTradeAt and opts.now and (opts.now - opts.lastTradeAt) < (opts.cooldownMs or 0) then
        return nil, 'too_fast'
    end

    return true
end
