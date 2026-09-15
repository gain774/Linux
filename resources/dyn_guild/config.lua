--[[
  組合・補助金（設計ドキュメント §9.3〜9.5）。

  NPC は置かない。プレイヤーが自己申告で申請し、運営が /guild approve で
  承認して初めて補助金の対象になる。自動承認は無い（多重申請対策の核）。

  州ごと・週ごとに税収を分ける（ユーザー要望）。組合は 1 つの州に所属し、
  その州のその週の純税収 × weeklyBudgetRatio が組合への補助金予算になる。
  dyn_treasury が州別週次の記帳を持っているので、ここはその集計を読むだけ。
]]
GuildConfig = {
    enabled = false,   -- ★既定 OFF（§9.8）。切っている間は申請も補助も一切動かない

    categories   = { 'farming', 'mining', 'hunting', 'crafting', 'ranching' },
    -- RedM の実在の州。組合は 1 つの州に所属し、その州の週次税収から補助を受ける
    states       = { 'new_hanover', 'west_elizabeth', 'new_austin', 'ambarino', 'lemoyne' },
    minFounders  = 3,        -- 承認に必要な最低人数（申請後に /guild join で集める運用）

    joinWaitDays    = 7,     -- 加入から補助対象になるまでの待機
    inactivityDays  = 90,    -- この日数、記帳(出荷)が無ければ自動失効

    subsidy = {
        mode              = 'accrual',   -- 'accrual'（実績払い・既定・推奨） | 'instant'（購入時割引）
        weeklyBudgetRatio = 0.40,        -- その州・その週の純税収の何割を補助金予算にするか

        -- 1 人1日あたりの補助上限。nil なら dyn_economy のアンカー価格 ×
        -- anchorMultiplier から導出する（§9.5: 目標曲線が無ければバスケット1個分の簡略版）
        perPersonDailyCap  = nil,
        anchorMultiplier   = 20,
        fallbackDailyCap   = 10,   -- dyn_economy が無い場合の最後の保険

        -- instant モード（購入時割引）を使う場合の濫用対策。
        -- 既定は accrual なので普段は関係ない
        instantSubsidizedNoResell = true,
    },

    label = '$',

    -- 起動時に sql/schema.sql を流す
    autoMigrate = true,
}
