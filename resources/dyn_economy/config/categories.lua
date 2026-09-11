-- カテゴリ既定値（設計ドキュメント §11 の叩き台）
-- アイテム個別の設定が無い項目はここから継承される。
Categories = {
    crop     = { elasticity = 0.70, halfLifeMin =  360, minMult = 0.15, maxMult = 2.00, spread = 0.35 },
    animal   = { elasticity = 0.60, halfLifeMin =  480, minMult = 0.20, maxMult = 2.50, spread = 0.30 },
    ore      = { elasticity = 0.45, halfLifeMin = 1440, minMult = 0.30, maxMult = 2.50, spread = 0.25 },
    crafted  = { elasticity = 0.30, halfLifeMin = 2880, minMult = 0.50, maxMult = 2.00, spread = 0.20 },
    luxury   = { elasticity = 0.35, halfLifeMin = 4320, minMult = 0.40, maxMult = 3.00, spread = 0.25 },
    misc     = { elasticity = 0.40, halfLifeMin = 1440, minMult = 0.30, maxMult = 2.00, spread = 0.30 },
}

Categories.default = Categories.misc
