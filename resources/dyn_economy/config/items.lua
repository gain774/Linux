--[[
  アイテムの相対価値（§6.1 の price_index）。

  ここに書くのは「小麦 1 に対してトウモロコシは 0.75」という比だけで、
  実際の金額ではない。サーバーの物価水準は currency_scale 側が持つので、
  この表は導入先が変わってもそのまま使える。

  targetStock は「そのアイテムが 1 日にどれくらい市場へ流れるか」の目安。
  実測が溜まったら Phase 5.5 以降の較正が調整する。

  label / desc はプレイヤーに見せる表示名・説明文（店舗メニューや通知で使う）。
  無ければ item のキー名がそのまま表示される。

  fixed = true を付けた品目は需給による価格変動を切り、基準価格に固定する
  （通貨スケールなど経済全体の較正だけは引き続き乗る）。銃・弾薬・道具のような
  「売り込まれても値崩れしてほしくない」品目向け。運用中に切り替えたい場合は
  /dyn_setfixed <item> <on|off> を使う（DB に保存され、config のこの値より優先される）。
]]
Items = {
    -- 農作物（items テーブルで実在確認済み）
    corn           = { category = 'crop',    priceIndex = 0.75, targetStock = 400, label = 'トウモロコシ'},
    wheat          = { category = 'crop',    priceIndex = 1.00, targetStock = 400, label = '小麦'},
    potato         = { category = 'crop',    priceIndex = 0.60, targetStock = 400, label = 'ポテト'},
    hop            = { category = 'crop',    priceIndex = 1.30, targetStock = 250, label = 'ホップ'},
    cocoa          = { category = 'crop',    priceIndex = 1.80, targetStock = 150, label = 'カカオ'},
    -- 動物素材
    deerpelt       = { category = 'animal',  priceIndex = 6.00, targetStock =  80, label = '鹿の毛皮'},
    coyotepelt     = { category = 'animal',  priceIndex = 4.50, targetStock =  80, label = 'コヨーテの毛皮'},
    wolfpelt       = { category = 'animal',  priceIndex = 7.00, targetStock =  60, label = 'オオカミの毛皮'},
    meat           = { category = 'animal',  priceIndex = 1.80, targetStock = 200, label = '肉'},
    fishmeat       = { category = 'animal',  priceIndex = 1.40, targetStock = 200, label = '魚肉'},
    -- 鉱物
    coal           = { category = 'ore',     priceIndex = 1.60, targetStock = 300, label = '石炭'},
    iron           = { category = 'ore',     priceIndex = 3.00, targetStock = 200, label = '鉄鉱石'},
    gold_nugget    = { category = 'luxury',  priceIndex = 45.0, targetStock =  20, label = 'ゴールドナゲット'},
    -- 加工品
    flour          = { category = 'crafted', priceIndex = 4.20, targetStock = 120, label = '小麦粉'},
    chewingtobacco = { category = 'crafted', priceIndex = 9.00, targetStock =  80, label = '噛みタバコ'},
    -- 資材
    water          = { category = 'misc',    priceIndex = 0.10, targetStock = 999, npcSellable = false, label = '水'},

    --[[
      以下は VORPCore の items テーブル(実サーバーの現行データ)を突き合わせて追加した品目。
      compat.lua が起動時に vorp_inventory への実在確認を行うので、ここに書いても
      DB に無ければ自動で無効化される（安全策）。
      priceIndex は名前から推測した初期値。実測が溜まったら調整すること。
    ]]

    -- ore
    copper                       = { category = 'ore', priceIndex = 2.20, targetStock =  250, label = '銅'},  -- 銅
    goldbar                      = { category = 'ore', priceIndex = 42.00, targetStock =   20, label = 'ゴールドバー'},  -- ゴールドバー
    ironbar                      = { category = 'ore', priceIndex = 4.50, targetStock =   70, label = '鉄棒', desc = '鉄棒(不使用)'},  -- 鉄棒(不使用)

    -- animal
    a_c_fishbluegil_01_ms        = { category = 'animal', priceIndex = 1.10, targetStock =  200, label = 'ブルーギル', desc = 'ブルーギル (中サイズ)'},  -- ブルーギル (中サイズ)
    a_c_fishbluegil_01_sm        = { category = 'animal', priceIndex = 0.80, targetStock =  300, label = 'ブルーギル', desc = 'ブルーギル (小さい)'},  -- ブルーギル (小さい)
    a_c_fishbullheadcat_01_ms    = { category = 'animal', priceIndex = 1.10, targetStock =  200, label = 'ブルヘッドナマズ', desc = 'ブルヘッドナマズ (中サイズ)'},  -- ブルヘッドナマズ (中サイズ)
    a_c_fishbullheadcat_01_sm    = { category = 'animal', priceIndex = 0.80, targetStock =  300, label = 'ブルヘッドナマズ', desc = 'ブルヘッドナマズ (小さい)'},  -- ブルヘッドナマズ (小さい)
    a_c_fishchainpickerel_01_ms  = { category = 'animal', priceIndex = 1.43, targetStock =  200, label = 'クサリカワカマス', desc = 'クサリカワカマス (中サイズ)'},  -- クサリカワカマス (中サイズ)
    a_c_fishchainpickerel_01_sm  = { category = 'animal', priceIndex = 1.04, targetStock =  300, label = 'クサリカワカマス', desc = 'クサリカワカマス (小さい)'},  -- クサリカワカマス (小さい)
    a_c_fishlargemouthbass_01_ms = { category = 'animal', priceIndex = 1.65, targetStock =  200, label = 'オオクチバス', desc = 'オオクチバス (中サイズ)'},  -- オオクチバス (中サイズ)
    a_c_fishperch_01_ms          = { category = 'animal', priceIndex = 1.10, targetStock =  200, label = 'パーチ', desc = 'パーチ (中サイズ)'},  -- パーチ (中サイズ)
    a_c_fishperch_01_sm          = { category = 'animal', priceIndex = 0.80, targetStock =  300, label = 'パーチ', desc = 'パーチ (小さい)'},  -- パーチ (小さい)
    a_c_fishrainbowtrout_01_ms   = { category = 'animal', priceIndex = 1.98, targetStock =  200, label = 'ニジマス', desc = 'ニジマス (中サイズ)'},  -- ニジマス (中サイズ)
    a_c_fishredfinpickerel_01_ms = { category = 'animal', priceIndex = 1.43, targetStock =  200, label = 'アカヒレカワカマス', desc = 'アカヒレカワカマス (中サイズ)'},  -- アカヒレカワカマス (中サイズ)
    a_c_fishredfinpickerel_01_sm = { category = 'animal', priceIndex = 1.04, targetStock =  300, label = 'アカヒレカワカマス', desc = 'アカヒレカワカマス (小さい)'},  -- アカヒレカワカマス (小さい)
    a_c_fishrockbass_01_ms       = { category = 'animal', priceIndex = 1.10, targetStock =  200, label = 'ロックバス', desc = 'ロックバス (中サイズ)'},  -- ロックバス (中サイズ)
    a_c_fishrockbass_01_sm       = { category = 'animal', priceIndex = 0.80, targetStock =  300, label = 'ロックバス', desc = 'ロックバス (小さい)'},  -- ロックバス (小さい)
    a_c_fishsalmonsockeye_01_ms  = { category = 'animal', priceIndex = 2.42, targetStock =  200, label = 'ベニザケ', desc = 'ベニザケ (中サイズ)'},  -- ベニザケ (中サイズ)
    a_c_fishsmallmouthbass_01_ms = { category = 'animal', priceIndex = 1.65, targetStock =  200, label = 'コクチバス', desc = 'コクチバス (中サイズ)'},  -- コクチバス (中サイズ)
    aligatormeat                 = { category = 'animal', priceIndex = 2.60, targetStock =  100, label = 'ワニ肉'},  -- ワニ肉
    boaskin                      = { category = 'animal', priceIndex = 5.50, targetStock =   70, label = 'ボア・スネークの革'},  -- ボア・スネークの革
    coyote_pelt                  = { category = 'animal', priceIndex = 4.50, targetStock =   70, label = 'コヨーテの毛皮', desc = 'コヨーテの毛皮(coyotepeltと同一個体、価格を揃えてある)'},  -- コヨーテの毛皮(coyotepeltと同一個体、価格を揃えてある)
    deer_pelt                    = { category = 'animal', priceIndex = 6.00, targetStock =   70, label = '鹿の毛皮', desc = '鹿の毛皮(deerpeltと同一個体、価格を揃えてある)'},  -- 鹿の毛皮(deerpeltと同一個体、価格を揃えてある)
    deerskin                     = { category = 'animal', priceIndex = 4.00, targetStock =   70, label = '鹿革', desc = '鹿革(プライムペルトより下位)'},  -- 鹿革(プライムペルトより下位)
    foxskin                      = { category = 'animal', priceIndex = 5.00, targetStock =   70, label = 'キツネの皮'},  -- キツネの皮
    Gamey_Meat                   = { category = 'animal', priceIndex = 2.20, targetStock =  180, label = '狩猟肉'},  -- 狩猟肉
    goats                        = { category = 'animal', priceIndex = 3.00, targetStock =   90, label = 'ヤギの毛皮'},  -- ヤギの毛皮
    SnakeSkin                    = { category = 'animal', priceIndex = 4.50, targetStock =   70, label = 'ヘビの皮'},  -- ヘビの皮
    wsnakeskin                   = { category = 'animal', priceIndex = 5.00, targetStock =   70, label = 'ウォータースネークの皮'},  -- ウォータースネークの皮

    -- luxury（伝説級）
    legfoxskin                   = { category = 'luxury', priceIndex = 28.00, targetStock =   12, label = '伝説のフォックス スキン'},  -- 伝説のフォックス スキン
    legwolfpelt                  = { category = 'luxury', priceIndex = 28.00, targetStock =   12, label = '伝説のオオカミの皮'},  -- 伝説のオオカミの皮

    -- misc
    goathead                     = { category = 'misc', priceIndex = 1.20, targetStock =  120, label = 'ヤギの頭'},  -- ヤギの頭

    -- crop（農作物・野草・キノコと種）
    Agarita                      = { category = 'crop', priceIndex = 1.10, targetStock =  220, label = 'アガリータ'},  -- アガリータ
    Agarita_Seed                 = { category = 'crop', priceIndex = 0.39, targetStock =  150, label = 'アガリータの種'},  -- アガリータの種
    Alaskan_Ginseng              = { category = 'crop', priceIndex = 3.20, targetStock =  220, label = 'アラスカニンジン'},  -- アラスカニンジン
    Alaskan_Ginseng_Seed         = { category = 'crop', priceIndex = 1.12, targetStock =  150, label = 'アラスカニンジンの種'},  -- アラスカニンジンの種
    American_Ginseng             = { category = 'crop', priceIndex = 3.20, targetStock =  220, label = 'アメリカニンジン'},  -- アメリカニンジン
    American_Ginseng_Seed        = { category = 'crop', priceIndex = 1.12, targetStock =  150, label = 'アメリカニンジンの種'},  -- アメリカニンジンの種
    Apple_Seed                   = { category = 'crop', priceIndex = 0.39, targetStock =  150, label = 'リンゴの種'},  -- リンゴの種
    banana                       = { category = 'crop', priceIndex = 0.70, targetStock =  250, label = 'バナナ'},  -- バナナ
    Bay_Bolete                   = { category = 'crop', priceIndex = 2.20, targetStock =  220, label = 'ニセイロガワリ'},  -- ニセイロガワリ
    Bay_Bolete_Seed              = { category = 'crop', priceIndex = 0.77, targetStock =  150, label = 'ニセイロガワリの種'},  -- ニセイロガワリの種
    Bitter_Weed                  = { category = 'crop', priceIndex = 0.90, targetStock =  220, label = 'ビターウィード'},  -- ビターウィード
    Bitter_Weed_Seed             = { category = 'crop', priceIndex = 0.32, targetStock =  150, label = 'ビターウィードの種'},  -- ビターウィードの種
    Black_Berry                  = { category = 'crop', priceIndex = 1.00, targetStock =  220, label = 'ブラックベリー'},  -- ブラックベリー
    Black_Berry_Seed             = { category = 'crop', priceIndex = 0.35, targetStock =  150, label = 'ブラックベリーの種'},  -- ブラックベリーの種
    Black_Currant                = { category = 'crop', priceIndex = 1.00, targetStock =  220, label = 'ブラックカラント'},  -- ブラックカラント
    Black_Currant_Seed           = { category = 'crop', priceIndex = 0.35, targetStock =  150, label = 'ブラックカラントの種'},  -- ブラックカラントの種
    Blood_Flower                 = { category = 'crop', priceIndex = 0.90, targetStock =  220, label = 'ブラッドフラワー'},  -- ブラッドフラワー
    Blood_Flower_Seed            = { category = 'crop', priceIndex = 0.32, targetStock =  150, label = 'ブラッドフラワーの種'},  -- ブラッドフラワーの種
    Bulrush                      = { category = 'crop', priceIndex = 0.90, targetStock =  220, label = 'ガマ'},  -- ガマ
    Bulrush_Seed                 = { category = 'crop', priceIndex = 0.32, targetStock =  150, label = 'ガマの種'},  -- ガマの種
    Burdock_Root                 = { category = 'crop', priceIndex = 0.90, targetStock =  220, label = 'ゴボウ'},  -- ゴボウ
    Burdock_Root_Seed            = { category = 'crop', priceIndex = 0.32, targetStock =  150, label = 'ゴボウの種'},  -- ゴボウの種
    Cardinal_Flower               = { category = 'crop', priceIndex = 0.90, targetStock =  220, label = 'ベニバナサワギキョウ'},  -- ベニバナサワギキョウ
    Cardinal_Flower_Seed         = { category = 'crop', priceIndex = 0.32, targetStock =  150, label = 'ベニバナサワギキョウの種'},  -- ベニバナサワギキョウの種
    carrots                      = { category = 'crop', priceIndex = 0.90, targetStock =  250, label = 'ニンジン'},  -- ニンジン
    Chanterelles                 = { category = 'crop', priceIndex = 2.20, targetStock =  220, label = 'アンズタケ'},  -- アンズタケ
    Chanterelles_Seed            = { category = 'crop', priceIndex = 0.77, targetStock =  150, label = 'アンズタケの種'},  -- アンズタケの種
    Choc_Daisy                   = { category = 'crop', priceIndex = 1.10, targetStock =  220, label = 'チョコレートデイジー'},  -- チョコレートデイジー
    Choc_Daisy_Seed              = { category = 'crop', priceIndex = 0.39, targetStock =  150, label = 'チョコレートデイジーの種'},  -- チョコレートデイジーの種
    coffeebeans                  = { category = 'crop', priceIndex = 2.00, targetStock =  250, label = 'コーヒー豆'},  -- コーヒー豆
    cornseed                     = { category = 'crop', priceIndex = 0.39, targetStock =  150, label = 'トウモロコシの種'},  -- トウモロコシの種
    Creeking_Thyme                = { category = 'crop', priceIndex = 0.90, targetStock =  220, label = 'クリーピングタイム'},  -- クリーピングタイム
    Creeking_Thyme_Seed          = { category = 'crop', priceIndex = 0.32, targetStock =  150, label = 'クリーピングタイムの種'},  -- クリーピングタイムの種
    Creekplum                    = { category = 'crop', priceIndex = 1.10, targetStock =  220, label = 'クリークプラム'},  -- クリークプラム
    Creekplum_Seed               = { category = 'crop', priceIndex = 0.39, targetStock =  150, label = 'クリークプラムの種'},  -- クリークプラムの種
    Crows_Garlic                  = { category = 'crop', priceIndex = 0.90, targetStock =  220, label = 'ワイルドガーリック'},  -- ワイルドガーリック
    Crows_Garlic_Seed            = { category = 'crop', priceIndex = 0.32, targetStock =  150, label = 'ワイルドガーリックの種'},  -- ワイルドガーリックの種
    Desert_Sage                  = { category = 'crop', priceIndex = 0.90, targetStock =  220, label = 'デザートセージ'},  -- デザートセージ
    Desert_Sage_Seed             = { category = 'crop', priceIndex = 0.32, targetStock =  150, label = 'デザートセージの種'},  -- デザートセージの種
    English_Mace                 = { category = 'crop', priceIndex = 0.90, targetStock =  220, label = 'イングリッシュメース'},  -- イングリッシュメース
    English_Mace_Seed            = { category = 'crop', priceIndex = 0.32, targetStock =  150, label = 'イングリッシュメースの種'},  -- イングリッシュメースの種
    Evergreen_Huckleberry        = { category = 'crop', priceIndex = 1.00, targetStock =  220, label = 'エバーグリーンハックルベリー'},  -- エバーグリーンハックルベリー
    Evergreen_Huckleberry_Seed   = { category = 'crop', priceIndex = 0.35, targetStock =  150, label = 'エバーグリーンハックルベリーの種'},  -- エバーグリーンハックルベリーの種
    Golden_Currant                = { category = 'crop', priceIndex = 1.00, targetStock =  220, label = 'ゴールデンカラント'},  -- ゴールデンカラント
    Golden_Currant_Seed          = { category = 'crop', priceIndex = 0.35, targetStock =  150, label = 'ゴールデンカラントの種'},  -- ゴールデンカラントの種
    grapes                       = { category = 'crop', priceIndex = 1.10, targetStock =  250, label = 'ブドウ'},  -- ブドウ
    hemp                          = { category = 'crop', priceIndex = 1.10, targetStock =  220, label = '大麻'},  -- 大麻
    hemp_seed                    = { category = 'crop', priceIndex = 0.39, targetStock =  150, label = '大麻の種'},  -- 大麻の種
    hop_seed                     = { category = 'crop', priceIndex = 0.39, targetStock =  150, label = 'ホップの種'},  -- ホップの種
    Hummingbird_Sage              = { category = 'crop', priceIndex = 0.90, targetStock =  220, label = 'ハミングバードセージ'},  -- ハミングバードセージ
    Hummingbird_Sage_Seed        = { category = 'crop', priceIndex = 0.32, targetStock =  150, label = 'ハミングバードセージの種'},  -- ハミングバードセージの種
    Indian_Tobbaco                = { category = 'crop', priceIndex = 2.50, targetStock =  220, label = 'インディアンタバコ'},  -- インディアンタバコ
    Indian_Tobbaco_Seed          = { category = 'crop', priceIndex = 0.88, targetStock =  150, label = 'インディアンタバコの種'},  -- インディアンタバコの種
    Milk_Weed                    = { category = 'crop', priceIndex = 0.90, targetStock =  220, label = 'オオトウワタ'},  -- オオトウワタ
    Milk_Weed_Seed               = { category = 'crop', priceIndex = 0.32, targetStock =  150, label = 'オオトウワタの種'},  -- オオトウワタの種
    Oleander_Sage                 = { category = 'crop', priceIndex = 0.90, targetStock =  220, label = 'オレアンダーセージ'},  -- オレアンダーセージ
    Oleander_Sage_Seed           = { category = 'crop', priceIndex = 0.32, targetStock =  150, label = 'オレアンダーセージの種'},  -- オレアンダーセージの種
    Oregano                      = { category = 'crop', priceIndex = 1.10, targetStock =  220, label = 'オレガノ'},  -- オレガノ
    Oregano_Seed                 = { category = 'crop', priceIndex = 0.39, targetStock =  150, label = 'オレガノの種'},  -- オレガノの種
    Parasol_Mushroom              = { category = 'crop', priceIndex = 2.20, targetStock =  220, label = 'カラカサタケ'},  -- カラカサタケ
    Parasol_Mushroom_Seed        = { category = 'crop', priceIndex = 0.77, targetStock =  150, label = 'カラカサタケの種'},  -- カラカサタケの種
    potatoseed                   = { category = 'crop', priceIndex = 0.39, targetStock =  150, label = 'ポテトの種'},  -- ポテトの種
    Prairie_Poppy                 = { category = 'crop', priceIndex = 0.90, targetStock =  220, label = 'プレーリーポピー'},  -- プレーリーポピー
    Prairie_Poppy_Seed           = { category = 'crop', priceIndex = 0.32, targetStock =  150, label = 'プレーリーポピーの種'},  -- プレーリーポピーの種
    Rams_Head                    = { category = 'crop', priceIndex = 2.20, targetStock =  220, label = 'マイタケ'},  -- マイタケ
    Rams_Head_Seed               = { category = 'crop', priceIndex = 0.77, targetStock =  150, label = 'マイタケの種'},  -- マイタケの種
    Red_Raspberry                 = { category = 'crop', priceIndex = 1.00, targetStock =  220, label = 'レッドラズベリー'},  -- レッドラズベリー
    Red_Raspberry_Seed           = { category = 'crop', priceIndex = 0.35, targetStock =  150, label = 'レッドラズベリーの種'},  -- レッドラズベリーの種
    Red_Sage                     = { category = 'crop', priceIndex = 0.90, targetStock =  220, label = 'レッドセージ'},  -- レッドセージ
    Red_Sage_Seed                = { category = 'crop', priceIndex = 0.32, targetStock =  150, label = 'レッドセージの種'},  -- レッドセージの種
    Saltbush                     = { category = 'crop', priceIndex = 1.10, targetStock =  220, label = 'ソルトブッシュ'},  -- ソルトブッシュ
    Saltbush_Seed                = { category = 'crop', priceIndex = 0.39, targetStock =  150, label = 'ソルトブッシュの種'},  -- ソルトブッシュの種
    sugarcaneseed                = { category = 'crop', priceIndex = 0.39, targetStock =  150, label = 'サトウキビの種'},  -- サトウキビの種
    Texas_Bonnet                  = { category = 'crop', priceIndex = 0.90, targetStock =  220, label = 'テキサス・ブルーボネット'},  -- テキサス・ブルーボネット
    Texas_Bonnet_Seed            = { category = 'crop', priceIndex = 0.32, targetStock =  150, label = 'テキサス・ブルーボネットの種'},  -- テキサス・ブルーボネットの種
    Violet_Snowdrop               = { category = 'crop', priceIndex = 0.90, targetStock =  220, label = 'ヴァイオレットスノードロップ'},  -- ヴァイオレットスノードロップ
    Violet_Snowdrop_Seed         = { category = 'crop', priceIndex = 0.32, targetStock =  150, label = 'ヴァイオレットスノードロップの種'},  -- ヴァイオレットスノードロップの種
    wheatseed                    = { category = 'crop', priceIndex = 0.39, targetStock =  150, label = '小麦の種'},  -- 小麦の種
    Wild_Carrot                   = { category = 'crop', priceIndex = 1.10, targetStock =  220, label = 'ワイルドキャロット'},  -- ワイルドキャロット
    Wild_Carrot_Seed             = { category = 'crop', priceIndex = 0.39, targetStock =  150, label = 'ワイルドキャロットの種'},  -- ワイルドキャロットの種
    Wild_Feverfew                 = { category = 'crop', priceIndex = 1.10, targetStock =  220, label = 'ワイルドフィーバーフュー'},  -- ワイルドフィーバーフュー
    Wild_Feverfew_Seed           = { category = 'crop', priceIndex = 0.39, targetStock =  150, label = 'ワイルドフィーバーフューの種'},  -- ワイルドフィーバーフューの種
    Wild_Mint                     = { category = 'crop', priceIndex = 1.10, targetStock =  220, label = 'ワイルドミント'},  -- ワイルドミント
    Wild_Mint_Seed               = { category = 'crop', priceIndex = 0.39, targetStock =  150, label = 'ワイルドミントの種'},  -- ワイルドミントの種
    Wild_Rhubarb                  = { category = 'crop', priceIndex = 0.90, targetStock =  220, label = 'ワイルドルバーブ'},  -- ワイルドルバーブ
    Wild_Rhubarb_Seed            = { category = 'crop', priceIndex = 0.32, targetStock =  150, label = 'ワイルドルバーブの種'},  -- ワイルドルバーブの種
    Wintergreen_Berry              = { category = 'crop', priceIndex = 1.00, targetStock =  220, label = 'ウィンターグリーンベリー'},  -- ウィンターグリーンベリー
    Wintergreen_Berry_Seed       = { category = 'crop', priceIndex = 0.35, targetStock =  150, label = 'ウィンターグリーンベリーの種'},  -- ウィンターグリーンベリーの種
    Wisteria                      = { category = 'crop', priceIndex = 0.90, targetStock =  220, label = '藤の花'},  -- 藤の花
    Wisteria_Seed                = { category = 'crop', priceIndex = 0.32, targetStock =  150, label = '藤の花の種'},  -- 藤の花の種
    Yarrow                        = { category = 'crop', priceIndex = 0.90, targetStock =  220, label = 'ノコギリソウ'},  -- ノコギリソウ
    Yarrow_Seed                  = { category = 'crop', priceIndex = 0.32, targetStock =  150, label = 'ノコギリソウの種'},  -- ノコギリソウの種

    -- crafted（加工品・飲食品）
    bacon                         = { category = 'crafted', priceIndex = 2.50, targetStock =  100, label = 'ベーコン'},  -- ベーコン
    beefjerky                    = { category = 'crafted', priceIndex = 2.00, targetStock =  120, label = 'ビーフジャーキー'},  -- ビーフジャーキー
    beer                          = { category = 'crafted', priceIndex = 1.00, targetStock =  150, label = 'ビール'},  -- ビール
    boiledegg                    = { category = 'crafted', priceIndex = 0.80, targetStock =  150, label = 'ゆで卵'},  -- ゆで卵
    cheesecake                   = { category = 'crafted', priceIndex = 3.00, targetStock =   40, label = 'チーズケーキ'},  -- チーズケーキ
    crabbutter                   = { category = 'crafted', priceIndex = 1.50, targetStock =   90, label = 'クラブバター'},  -- クラブバター
    honey                         = { category = 'crafted', priceIndex = 2.00, targetStock =   90, label = 'ハチミツ'},  -- ハチミツ
    moonshine                    = { category = 'crafted', priceIndex = 3.50, targetStock =   50, label = 'ムーンシャイン'},  -- ムーンシャイン
    raw_bacon                    = { category = 'crafted', priceIndex = 1.50, targetStock =  100, label = '生のベーコン'},  -- 生のベーコン
    salt                          = { category = 'crafted', priceIndex = 0.50, targetStock =  300, label = '塩'},  -- 塩
    sugar                         = { category = 'crafted', priceIndex = 0.60, targetStock =  250, label = '砂糖'},  -- 砂糖
    sugarcube                    = { category = 'crafted', priceIndex = 0.30, targetStock =  200, label = '角砂糖'},  -- 角砂糖
    tropicalPunchMoonshine       = { category = 'crafted', priceIndex = 4.00, targetStock =   40, label = '高麗人参のムーンシャイン'},  -- 高麗人参のムーンシャイン
    wildCiderMash                = { category = 'crafted', priceIndex = 1.00, targetStock =   80, label = 'ブラックベリーのマッシュ'},  -- ブラックベリーのマッシュ
    wildCiderMoonshine           = { category = 'crafted', priceIndex = 4.00, targetStock =   40, label = 'ブラックベリー ムーンシャイン'},  -- ブラックベリー ムーンシャイン
    wine                          = { category = 'crafted', priceIndex = 2.50, targetStock =   90, label = 'ワイン'},  -- ワイン
}
