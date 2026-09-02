ACConfig = {}

-- 動作モード
--   'log'     … 検知しても記録するだけ（導入直後はこれ。誤検知の洗い出し用）
--   'enforce' … 蓄積した違反点数に応じてキック・BAN を行う
ACConfig.Mode = 'log'

-- この権限以上は検知対象外。管理メニューのテレポートや車両スポーンで
-- 誤検知するため、admin 以上は除外しておく
ACConfig.ExemptPermission = 'admin'

-- 違反点数の段階。点数は AC.Decay 秒ごとに 1 減る
ACConfig.Escalation = {
    kick = 6,      -- この点数でキック
    ban  = 12,     -- この点数で BAN
    banMinutes = 0, -- 0 は無期限
}

-- 点数が 1 減るまでの秒数
ACConfig.Decay = 300

-- 検知ごとの重み
ACConfig.Weight = {
    health      = 3,
    armour      = 2,
    speed       = 2,
    teleport    = 3,
    weapon      = 4,
    explosion   = 4,
    giveWeapon  = 4,
    clearTasks  = 2,
    spam        = 1,
}

-- 定期チェックの間隔（ミリ秒）
ACConfig.Interval = 3000

ACConfig.Health = {
    -- 通常の最大体力は 200。ここを超えたら体力ハック
    max = 200,
    -- 装甲の上限
    maxArmour = 105,
}

ACConfig.Movement = {
    -- 徒歩でこれを超える速度（m/s）は異常。パラシュート降下でも 60 は超えない
    maxOnFoot = 25.0,
    -- 車両を含めた上限（m/s）。ジェット機の巡航でも 150 程度
    maxAny = 180.0,
    -- 1 チェック間隔でこの距離（m）を超えて移動したらテレポート扱い
    maxJump = 400.0,
    -- 参加・リスポーン直後はこの秒数だけ判定しない
    graceSeconds = 20,
}

-- 所持していたら即検知する武器。一般プレイでは手に入らないものだけを入れる
ACConfig.BlacklistedWeapons = {
    'WEAPON_MINIGUN',
    'WEAPON_RPG',
    'WEAPON_GRENADELAUNCHER',
    'WEAPON_GRENADELAUNCHER_SMOKE',
    'WEAPON_RAILGUN',
    'WEAPON_FIREWORK',
    'WEAPON_HOMINGLAUNCHER',
    'WEAPON_COMPACTLAUNCHER',
    'WEAPON_RAYMINIGUN',
    'WEAPON_RAYPISTOL',
    'WEAPON_RAYCARBINE',
}

-- ネットワークイベントの扱い
ACConfig.NetEvents = {
    -- 他人に武器を渡すイベント。正規のリソースはサーバー経由で渡すため通常は不要
    blockGiveWeapon = true,
    -- 他人の行動を強制キャンセルするイベント。嫌がらせに使われる
    blockClearPedTasks = true,
    -- 10 秒あたりの爆発の上限
    explosionPer10s = 5,
    -- 完全に禁止する爆発タイプ（explosionType の数値）
    blockedExplosions = {},
}
