Config = Config or {}

-- 需給による価格変動そのもの（§4）。false にすると全て固定価格になる
Config.Dynamic = { enabled = true }

-- 物価水準レイヤー（§4.5）。需給とは別軸の全体倍率。
-- cpi_mult は較正レイヤー（§6〜§7、いずれも未実装）が動かすので、今は 1.0 のまま。
-- categoryMult は季節・イベント用に手で与える（例: winter = { crop = 1.25 }）。
Config.PriceLevel = {
    enabled      = true,
    categoryMult = {},
}

-- レシピ原価による下限価格（§5）
Config.Recipes = {
    enabled     = true,
    craftMargin = 1.10,   -- 原価の何倍を買取下限にするか
    maxDepth    = 6,
    refreshMin  = 15,     -- 原価キャッシュの再計算間隔（分）
}

-- 通貨と丸め
Config.Currency = {
    step  = 0.01,   -- 丸め単位
    label = '$',
}

-- 新規サーバー向けのアンカー（§6.2 B）。
-- 既存サーバーへ後乗せする場合は Phase 5.5 の bootstrap 較正が currency_scale を上書きする。
Config.Anchor = { item = 'corn', price = 0.75 }

-- 税（§9.1）。Phase 1〜2 では記帳先の国庫がまだ無いので、
-- 徴収額の計算と取引ログへの記録だけを行う。
Config.Tax = {
    enabled   = true,
    sellShare = 0.5,   -- スプレッド由来の税を売り側／買い側にどう配分するか
}

Config.Db = {
    autoMigrate = true,       -- 起動時に sql/schema.sql を流す
    persistSec  = 60,         -- 仮想在庫を DB に書き戻す間隔（秒）
}

--[[
  資産センサス（§6.4）。起動時と定期的にサーバー全体の所持金を棚卸しする。

  国庫（dyn_treasury）は誰の財布にも入っていないので、ここには現れない。
  流通量と国庫を分けて扱うという設計（§9.2）が自然に満たされる。
]]
Config.Census = {
    enabled       = true,
    onStartup     = true,
    startupDelay  = 60,     -- 他リソースの読み込みと競合しないよう待つ（秒）
    intervalHours = 24,
    activeDays    = 14,     -- 直近この日数にログインした人を統計の対象にする
    outlierMAD    = 5.0,    -- 中央値 + この係数 × MAD を超えたら外れ値
    driftTolerance = 0.25,  -- 総額のズレの許容。超えたら長期較正を保留する

    -- キャラクターと現金。VORP の標準構成に合わせてある
    base = {
        table = 'characters', owner = 'charidentifier',
        column = 'money',     lastLogin = 'LastLogin',
    },

    -- 追加の財布。テーブルが無ければ黙って飛ばす。
    -- vorp_banking は所持金を bank_users に置くので、これを合算しないと
    -- 総額が常に合わず、drift が毎回異常判定になる。
    wallets = {
        { table = 'bank_users', owner = 'charidentifier', column = 'money' },
    },

    -- 物価の基準バスケット。時系列で比べられるよう固定した品目にする。
    -- 空なら扱っている全品目から作る（品目を足すたびに基準が変わるので推奨しない）。
    basket = { 'corn', 'wheat', 'animal_meat', 'coal', 'bread' },
}
