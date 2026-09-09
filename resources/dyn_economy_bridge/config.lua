BridgeConfig = {
    -- 使用するフレームワーク。現在は 'vorp' のみ実装している。
    framework = 'vorp',

    -- VORP の通貨種別: 0 = ドル / 1 = ゴールド / 2 = ROL
    -- 動的価格が扱うのはこの 1 種類だけ。金塊などを第二通貨として使う場合、
    -- そちらは別の店舗ロジックで扱うこと（価格エンジンは単一通貨を前提にしている）。
    currency = 0,

    -- 売買が成立したときにプレイヤーへ通知を出すか
    notify = true,

    -- 通知の表示時間（ミリ秒）
    notifyDuration = 4000,

    -- 通貨記号。通知の文面に使う
    currencyLabel = '$',

    -- 他リソースとの互換（server/compat.lua）
    compat = {
        -- 起動時に dyn_economy の品目を vorp_inventory の登録内容と突き合わせる。
        -- 登録が無い品目は自動で無効化する。これをしないと売買のたびに
        -- vorp_inventory が「does not exist in DB」をコンソールに出し続け、
        -- canCarryItem も常に false を返す。
        validateItems = true,

        -- 劣化アイテム（maxDegradation > 0）を扱うか。
        -- 既定は false。価格エンジンは個体の劣化度を見ないので、
        -- 許可すると状態の悪い品を満額で売れてしまう（vorp_stores は
        -- percentage/100 を価格に掛けている）。
        allowDegradable = false,

        -- vorp_stores の RandomPrices / DynamicStore が有効なままだと、
        -- 価格と在庫を二重に制御することになる。起動時に検出して警告する。
        warnStoreConflicts = true,
    },
}
