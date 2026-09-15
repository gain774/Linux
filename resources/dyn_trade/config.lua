--[[
  個人間取引（P2P）の設定。

  NPC 店舗（dyn_shop）とは別物。NPC 相手は dyn_economy が決めた価格でしか
  売買できないが、こちらはプレイヤー同士が金額を自由に決める。
  dyn_economy の定価は「目安」として画面に出すだけで、価格そのものは縛らない。
]]
Config = {}

-- 取引を始めるのに使うアイテム。使うと一番近いプレイヤーに申し込みを送る。
-- 消費はしない（何度でも使える道具として扱う）。items テーブルに無ければ
-- sql/schema.sql が起動時に登録する
Config.item = 'trade_ledger'

-- 申し込み時に対象にできる距離（メートル）
Config.inviteDistance = 3.0

-- 申し込みの返答を待つ時間（ミリ秒）。この間に応答が無ければ申し込みは自動的に流れる
Config.inviteTimeoutMs = 20000

-- 交渉セッションが一定時間操作されなかったら自動的に打ち切る（ミリ秒）。
-- 片方が放置・切断してもう片方が延々と待たされる事故を防ぐ
Config.sessionTimeoutMs = 10 * 60000

-- 片側が同時に提示できる品目の種類数（1 種類の中の数量には上限を設けない）
Config.maxOfferItems = 12

--[[
  現金部分にかかる手数料率。§ユーザー要望:
  「ほぼ自由取引だが手数料を3%ほど払う必要がある」

  現物同士の物々交換（現金 0）には手数料は発生しない。
  現金が動いた分だけ、双方それぞれの現金提示額に対して取る
  （A が $100 出し B が $50 出す取引なら、A 分から $3、B 分から $1.5 を徴収する）。
  徴収した分は消さず dyn_treasury（導入していれば）に記帳する。
]]
Config.feeRate = 0.03

Config.currencyLabel = '$'
Config.notifyDuration = 4000

-- 起動時に items テーブルへ取引アイテムを自動登録するか
Config.autoRegisterItem = true

-- 起動時に sql/schema.sql を流すか（監査ログ用テーブル + 取引アイテムの登録）
Config.autoMigrate = true
