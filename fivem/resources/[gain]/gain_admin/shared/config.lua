AdminConfig = {}

-- メニューを開くキー（FiveM のキー名）。設定 → キー割り当てから変更もできる
AdminConfig.MenuKey = 'F6'

-- 操作ごとに必要な権限。Config.Permissions のキーを使う
AdminConfig.Actions = {
    menu       = 'mod',
    players    = 'mod',
    heal       = 'mod',
    revive     = 'mod',
    tpto       = 'mod',
    bring      = 'mod',
    spectate   = 'mod',
    kick       = 'mod',
    vehicle    = 'admin',
    givemoney  = 'admin',
    ban        = 'admin',
    unban      = 'admin',
    setperm    = 'owner',
}

-- 一度に付与できる金額の上限（誤操作と権限乱用の歯止め）
AdminConfig.MaxGiveMoney = 1000000

-- BAN 期間の選択肢（分）。0 は無期限
AdminConfig.BanDurations = {
    { label = '1時間',  minutes = 60 },
    { label = '1日',    minutes = 1440 },
    { label = '1週間',  minutes = 10080 },
    { label = '無期限', minutes = 0 },
}
