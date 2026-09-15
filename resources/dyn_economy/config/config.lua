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

--[[
  個人間取引（dyn_trade 等）の実売買価格を参考値として集計する（§8.2）。

  記録するのは「現金のみ ⇄ 単一品目のみ」の取引だけ。複数品目・両建て現金は
  単価に分解できないため対象外（DynVwapMath.deriveUnitPrice が判定する）。

  driftToP0 は既定オフ。オンにすると実勢 VWAP が P0（基準価格）から長期間
  乖離したとき、P0 自体を 1 日 driftDailyPct ぶんだけゆっくり寄せる（§8.2 の任意機能）。
  仮想在庫・需給変動（§4）には一切影響しない。
]]
Config.PlayerRef = {
    enabled       = true,
    windowHours   = 24,      -- VWAP の集計窓
    driftToP0     = false,   -- ★既定 OFF
    driftDailyPct = 0.01,    -- driftToP0 有効時、1 日あたりの P0 補正上限
    driftMinQty   = 20,      -- この取引量に満たない品目は補正しない（標本が薄いと暴れるため）
}

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
    basket = { 'corn', 'wheat', 'meat', 'coal', 'flour' },
}

--[[
  新規キャラの開始所持金（§6.3）。既存キャラの所持金には絶対に触らない
  （適用されるのは vorp_NewCharacter イベントで検知した新規作成キャラのみ）。
]]
Config.Economy = {
    startingMode    = 'basket',  -- 'basket'（推奨） | 'curve'（§7 併用時） | 'fixed'
    startingBaskets = 1.5,       -- startingMode='basket' のとき、基準バスケット何個分から始めるか
    startingFixed   = 100,       -- startingMode='fixed' のときだけ使う
}

--[[
  自動較正（§6〜§6.9）。手で物価を書き直す作業を「スカラー1個の較正」に縮める。

  全レイヤーを独立に切れる（§7.7 のトグル表どおり）。上から下に行くほど
  経済への介入が強くなるので、bootstrap 以外は既定 OFF。2週間ほど実測を
  溜めてから有効化することを推奨する（§6.10）。
]]
Config.Calibration = {
    enabled   = true,   -- ★キルスイッチ。false でこの節（§6.5〜6.7）をすべて止める
                         -- （§4 の需給変動・§6.2 の起動時較正には影響しない）
    bootstrap = true,   -- 導入時の初期値決定（§6.2）
    wealth    = false,  -- 所持金分布への追従（§6.5）
    yield     = false,  -- 収集効率アンカー（§6.6）
    moneySupply = false, -- マネーサプライ PI 制御（§6.7）

    -- §6.5 所持金分布への追従
    wealthK           = 0.15,   -- 1 日あたりの反応の強さ
    wealthDailyClamp  = 0.02,   -- 1 日 ±2%
    wealthSinkCoupling = 0.5,   -- β。NPC 買取（金のソース）側の連動を弱める係数

    -- §6.6 収集効率アンカー
    yieldMinUniqueSellers = 5,
    yieldMinPlaytimeHours = 20,
    yieldBandLowMult   = 0.7,   -- 目標時給バンドの下限（その日の中央時給の何倍か）
    yieldBandHighMult  = 1.3,
    yieldMaxDailyPct   = 0.03,  -- price_index の 1 日あたりの変化上限 ±3%
    -- 何分おきにプレイ時間を積み上げるか（playtime.lua のティック間隔）
    playtimeTickMinutes = 5,

    -- §6.7 マネーサプライ PI 制御
    moneySupplyTargetGrowth = 0.0,   -- 1 日あたりの目標成長率
    moneySupplyKp = 2.0,
    moneySupplyKi = 0.5,

    -- 日次ジョブを回す時刻。intervalHours ごとではなく「1 日 1 回」に固定する
    -- （§6.9: 全ての較正は 1 日 1 回・小刻み・クランプ、が安全装置の前提のため）
    dailyStartupDelaySec = 90,
}

--[[
  目標成長曲線ターゲティング（§7）。**既定 OFF。** 経済に最も強く介入する
  レイヤーなので、§6 の較正が安定してから有効にする前提で作られている。

  「§6.7 マネーサプライ PI 制御と競合して発振する」という設計ドキュメントの
  注意（§7.4）は、そちらが global_mult を、こちらが income_mult を動かす
  ようにスタック上で分離してあるため、このリソースでは実質的に発生しない
  （別々の econ キー・別々のスタック段なので取り合いにならない）。
  ドキュメント通りの挙動が欲しければ `/dyn_toggle moneysupply off` で
  §6.7 を切ればよい。
]]
Config.Progression = {
    enabled     = false,       -- ★既定 OFF
    basis       = 'playtime',  -- 'playtime'（推奨） | 'calendar'
    hoursPerDay = 2.0,         -- basis='playtime' のとき「1 日」とみなす時間
    metric      = 'earned',    -- 'earned'（推奨） | 'networth'

    curve = {
        { day = 1,  value =    50 },
        { day = 3,  value =   180 },
        { day = 7,  value =   500 },
        { day = 14, value =  1200 },
        { day = 30, value =  3000 },
        { day = 90, value = 12000 },
    },

    tolerance   = 0.15,   -- ±15% の不感帯
    maxDailyAdj = 0.03,   -- 1 日あたりの補正上限 ±3%
    minSamples  = 5,      -- コホートの最低人数
    Kp          = 0.5,
    sinkCoupling = 0.0,   -- >0 なら NPC 販売価格も逆向きに動かす（0〜1）
    bucketWeight = { early = 2.0, mid = 1.0, late = 0.5 },

    activeDays       = 14,  -- 直近この日数ログインしていない人は評価対象外
    coverageWarn     = 0.5, -- coverage がこれを下回るバケットが続いたら警告して補正を打ち切る
}
