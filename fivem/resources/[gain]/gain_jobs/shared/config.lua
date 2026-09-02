JobConfig = {}

-- 給料の支払い間隔（分）
JobConfig.PaycheckMinutes = 15

-- 勤務中（duty）のみ給料を払う
JobConfig.PayOnDutyOnly = true

-- 就職所
JobConfig.JobCenter = {
    label = 'ハローワーク',
    x = -265.09, y = -963.42, z = 31.22,
    blip = { sprite = 407, color = 5, scale = 0.8 },
}

-- 操作できる距離（m）
JobConfig.Radius = 1.8

-- ミッションのポイントに到達したと見なす距離（m）。
-- サーバー側の検証にも同じ値を使う
JobConfig.ClaimRadius = 12.0

JobConfig.Jobs = {
    unemployed = {
        label = '無職',
        grades = {
            [0] = { label = '無職', salary = 0 },
        },
    },

    garbage = {
        label = '清掃員',
        grades = {
            [0] = { label = '見習い', salary = 50 },
            [1] = { label = '作業員', salary = 80 },
            [2] = { label = '班長',   salary = 120 },
        },
        duty = { x = -322.24, y = -1545.63, z = 31.05, label = '清掃事業所' },
        mission = {
            label = 'ゴミ収集',
            vehicle = 'trash',
            stops = 5,
            payPerStop = 140,
            bonus = 350,
            returnPoint = { x = -322.24, y = -1545.63, z = 31.05 },
            points = {
                { x = 306.71,  y = -1092.60, z = 29.41 },
                { x = 106.28,  y = -1078.15, z = 29.36 },
                { x = -78.05,  y = -1093.10, z = 26.42 },
                { x = -262.98, y = -1176.85, z = 22.99 },
                { x = -415.13, y = -1290.19, z = 31.34 },
                { x = 214.36,  y = -810.71,  z = 30.79 },
                { x = 89.55,   y = -670.36,  z = 31.98 },
                { x = -145.25, y = -593.03,  z = 34.15 },
                { x = 439.83,  y = -983.20,  z = 30.69 },
                { x = -598.90, y = -930.13,  z = 23.87 },
            },
        },
    },

    taxi = {
        label = 'タクシー運転手',
        grades = {
            [0] = { label = '新人', salary = 60 },
            [1] = { label = '運転手', salary = 90 },
            [2] = { label = '主任',  salary = 130 },
        },
        duty = { x = 895.62, y = -179.15, z = 74.70, label = 'ダウンタウン・キャブ社' },
        mission = {
            label = '配車',
            vehicle = 'taxi',
            stops = 4,
            payPerStop = 200,
            bonus = 300,
            returnPoint = { x = 895.62, y = -179.15, z = 74.70 },
            points = {
                { x = -1037.75, y = -2737.60, z = 20.17 },
                { x = 228.75,   y = -865.34,  z = 30.49 },
                { x = -545.85,  y = -213.75,  z = 37.65 },
                { x = 293.53,   y = -1077.61, z = 29.38 },
                { x = -1300.68, y = -1096.72, z = 6.99  },
                { x = 1136.03,  y = -982.02,  z = 45.42 },
                { x = -3169.72, y = 1085.15,  z = 20.83 },
                { x = 1728.13,  y = 3709.20,  z = 34.13 },
            },
        },
    },

    trucker = {
        label = '運送業',
        grades = {
            [0] = { label = '見習い', salary = 70 },
            [1] = { label = 'ドライバー', salary = 110 },
            [2] = { label = '主任', salary = 150 },
        },
        duty = { x = 149.35, y = -3210.13, z = 5.93, label = '港湾倉庫' },
        mission = {
            label = '配送',
            vehicle = 'mule',
            stops = 3,
            payPerStop = 400,
            bonus = 500,
            returnPoint = { x = 149.35, y = -3210.13, z = 5.93 },
            points = {
                { x = 25.72,    y = -1347.34, z = 29.50 },
                { x = 1163.61,  y = -323.15,  z = 69.21 },
                { x = -3038.94, y = 585.94,   z = 7.91  },
                { x = 1698.13,  y = 4924.010, z = 42.06 },
                { x = 1959.62,  y = 3740.28,  z = 32.34 },
                { x = -1820.55, y = 792.51,   z = 138.12 },
            },
        },
    },
}

-- 就職所に並べる職業（unemployed は退職用に別扱い）
JobConfig.Hireable = { 'garbage', 'taxi', 'trucker' }
