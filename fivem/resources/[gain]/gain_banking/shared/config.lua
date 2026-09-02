BankConfig = {}

-- 銀行の窓口。ここでは送金まで行える
BankConfig.Banks = {
    { label = 'フリーカ銀行（レジオンスクエア）', x = 149.93,   y = -1040.30, z = 29.37 },
    { label = 'フリーカ銀行（ロックフォード）',   x = -1212.98, y = -330.84,  z = 37.79 },
    { label = 'フリーカ銀行（バートン）',         x = -351.53,  y = -49.52,   z = 49.04 },
    { label = 'フリーカ銀行（アルタ）',           x = 314.19,   y = -278.62,  z = 54.17 },
    { label = 'フリーカ銀行（グレートオーシャン）', x = -2962.60, y = 482.20,   z = 15.70 },
    { label = 'フリーカ銀行（ルート68）',         x = 1175.06,  y = 2706.86,  z = 38.09 },
    { label = 'フリーカ銀行（パレト・ベイ）',     x = -112.20,  y = 6469.29,  z = 31.63 },
    { label = 'パシフィック・スタンダード銀行',   x = 235.01,   y = 216.32,   z = 106.29 },
}

-- ATM として扱うプロップ。引き出し・預け入れのみ
BankConfig.AtmProps = {
    'prop_atm_01',
    'prop_atm_02',
    'prop_atm_03',
    'prop_fleeca_atm',
}

-- 操作できる距離（m）
BankConfig.Radius = 1.6

-- 銀行のブリップを地図に出す
BankConfig.Blip = {
    enabled = true,
    sprite = 108,
    color = 2,
    scale = 0.7,
    label = '銀行',
}

-- 送金の制限
BankConfig.Transfer = {
    min = 1,
    max = 1000000,
    -- 手数料（割合）。0.01 で 1%
    feeRate = 0.0,
}

-- 取引履歴に残す件数（表示用）
BankConfig.HistoryLimit = 15
