Config = {}

-- 表示言語（shared/locale/ 配下のファイル名と対応）
Config.Locale = 'ja'

-- 新規キャラクターの初期資金
Config.StartingCash = 500
Config.StartingBank = 5000

-- キャラクターデータの自動保存間隔（ミリ秒）
Config.AutosaveInterval = 60000

-- 初期スポーン地点（ロスサントス空港前）
Config.DefaultSpawn = { x = -1037.7, y = -2737.7, z = 20.2, heading = 328.0 }

-- 権限レベル。数値が大きいほど強い
Config.Permissions = {
    user  = 0,
    mod   = 1,
    admin = 2,
    owner = 3,
}

-- サーバー起動時に必ずこの権限を与える license（`license:xxxx` 形式）
-- 例: Config.Owners = { 'license:1234abcd...' }
Config.Owners = {}

-- 所持金の上限（オーバーフローと不正付与の歯止め）
Config.MoneyLimit = 999999999

-- ログ出力先
Config.Log = {
    console = true,
    -- Discord Webhook URL。空文字なら送信しない
    discordWebhook = '',
    -- gain_logs テーブルへ書き込むか
    database = true,
}

-- 既存リソース向け互換レイヤー。不要なら false
Config.Compat = {
    esx = true,
    qbcore = true,
}

-- net イベントの既定レート制限（1プレイヤーあたり per ミリ秒で max 回）
Config.EventRateLimit = {
    max = 10,
    per = 1000,
}
