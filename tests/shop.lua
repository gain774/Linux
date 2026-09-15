--[[
  店舗側の検証（dyn_shop/server/guard.lua）のテスト。
  クライアントから来る値を信用しない部分なので、ここが緩いと成立してはいけない
  取引が通る。
    lua5.4 tests/shop.lua
]]

local root = (arg[0]:match('^(.*)/tests/shop%.lua$') or '.')
dofile(root .. '/resources/dyn_shop/server/guard.lua')

local passed, failed = 0, 0
local function ok(cond, name, extra)
    if cond then passed = passed + 1
    else
        failed = failed + 1
        print(('  FAIL  %s%s'):format(name, extra and ('  -- ' .. extra) or ''))
    end
end
local function group(n) print(n) end

local shop = {
    label = 'test',
    hours = { open = 8, close = 20 },
    sell  = { 'corn', 'wheat' },
    buy   = { 'corn', 'flour' },
}

-- テーブルに nil は入れられないので、値を消したいときはこの番兵を渡す
local NIL = {}

local function opts(over)
    local o = {
        item = 'corn', direction = 'sell', hour = 12, distance = 1.0,
        now = 10000, lastTradeAt = nil, cooldownMs = 500, maxDistance = 2.5,
    }
    for k, v in pairs(over or {}) do
        o[k] = (v ~= NIL) and v or nil
    end
    return o
end

group('営業時間')
ok(ShopGuard.isOpen(shop, 8) == true,  '開店時刻ちょうどは営業中')
ok(ShopGuard.isOpen(shop, 19) == true, '閉店 1 時間前は営業中')
ok(ShopGuard.isOpen(shop, 20) == false,'閉店時刻ちょうどは営業終了')
ok(ShopGuard.isOpen(shop, 7) == false, '開店前は営業外')
ok(ShopGuard.isOpen({}, 3) == true, 'hours 未設定は 24 時間営業')
do
    local night = { hours = { open = 21, close = 5 } }
    ok(ShopGuard.isOpen(night, 23) == true, '深夜営業: 23 時は営業中')
    ok(ShopGuard.isOpen(night, 2)  == true, '深夜営業: 日をまたいだ 2 時も営業中')
    ok(ShopGuard.isOpen(night, 12) == false,'深夜営業: 昼は営業外')
    ok(ShopGuard.isOpen(night, 21) == true, '深夜営業: 開店時刻ちょうど')
    ok(ShopGuard.isOpen(night, 5)  == false,'深夜営業: 閉店時刻ちょうど')
end
ok(ShopGuard.isOpen({ hours = { open = 0, close = 0 } }, 13) == true,
   'open == close は 24 時間営業として扱う')

group('取扱品目')
ok(ShopGuard.allows(shop, 'corn', 'sell') == true, '売却リストにある品目は売れる')
ok(ShopGuard.allows(shop, 'flour', 'sell') == false, '購入リストだけの品目は売れない')
ok(ShopGuard.allows(shop, 'flour', 'buy') == true, '購入リストにある品目は買える')
ok(ShopGuard.allows(shop, 'wheat', 'buy') == false, '売却リストだけの品目は買えない')
ok(ShopGuard.allows(shop, 'gold_nugget', 'sell') == false, '扱っていない品目は通らない')
ok(ShopGuard.allows({ sell = { 'corn' } }, 'corn', 'buy') == false, 'buy リストが無ければ買えない')

group('validate')
ok(ShopGuard.validate(nil, opts()) == nil, '店舗が無ければ unknown_shop')
do
    local _, err = ShopGuard.validate(nil, opts())
    ok(err == 'unknown_shop', 'エラーコードが unknown_shop')
end
ok(ShopGuard.validate(shop, opts()) == true, '条件を満たせば通る')

do
    local _, err = ShopGuard.validate(shop, opts({ distance = 10.0 }))
    ok(err == 'out_of_range', '距離が離れていると out_of_range')
end
do
    local _, err = ShopGuard.validate(shop, opts({ distance = NIL }))
    ok(err == 'out_of_range', '距離を取得できない場合も通さない')
end
do
    local _, err = ShopGuard.validate(shop, opts({ hour = 22 }))
    ok(err == 'closed', '営業時間外は closed')
end
do
    local _, err = ShopGuard.validate(shop, opts({ item = 'gold_nugget' }))
    ok(err == 'item_not_traded', '扱っていない品目は item_not_traded')
end
do
    local _, err = ShopGuard.validate(shop, opts({ direction = 'steal' }))
    ok(err == 'bad_direction', '不正な方向は bad_direction')
end
do
    local _, err = ShopGuard.validate(shop, opts({ now = 10100, lastTradeAt = 10000 }))
    ok(err == 'too_fast', 'クールダウン中は too_fast')
    ok(ShopGuard.validate(shop, opts({ now = 10600, lastTradeAt = 10000 })) == true,
       'クールダウンを過ぎれば通る')
end
do
    -- メニューを開くだけのときは品目を渡さない。品目の検証は飛ばすが距離と時間は見る
    ok(ShopGuard.validate(shop, opts({ item = NIL })) == true, '品目なしでも距離と時間は検証する')
    local _, err = ShopGuard.validate(shop, opts({ item = NIL, distance = 99 }))
    ok(err == 'out_of_range', '品目なしでも距離は通さない')
end

group('検証の順序')
do
    -- 距離を最優先で見る。離れた場所からの偽装リクエストを、
    -- 品目や時間の判定より先に落とす
    local _, err = ShopGuard.validate(shop, opts({ distance = 99, hour = 22, item = 'gold_nugget' }))
    ok(err == 'out_of_range', '複数の条件を満たさない場合は距離を先に返す')
end

print()
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
