Config = Config or {}

-- 需給による価格変動そのもの（§4）。false にすると全て固定価格になる
Config.Dynamic = { enabled = true }

-- 物価水準レイヤー（§4.5）。Phase 1〜2 では cpi_mult は 1.0 のまま動かない
Config.PriceLevel = { enabled = true }

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

Config.Debug = false
