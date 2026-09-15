-- dyn_treasury — 国庫の出納帳（設計ドキュメント §9.6）
-- 注意: 起動時の自動マイグレーションはコメントを落としてからセミコロンで文を分割する。

CREATE TABLE IF NOT EXISTS dyn_treasury_ledger (
  id            BIGINT AUTO_INCREMENT PRIMARY KEY,
  created_at    DATETIME      NOT NULL,
  direction     ENUM('in','out') NOT NULL,
  source        VARCHAR(32)   NOT NULL,
  amount        DECIMAL(14,2) NOT NULL,
  balance_after DECIMAL(16,2) NOT NULL,
  ref_type      VARCHAR(32)   NULL,
  ref_id        BIGINT        NULL,
  note          VARCHAR(255)  NULL,
  INDEX idx_time (created_at),
  INDEX idx_source_time (source, created_at),
  INDEX idx_ref (ref_type, ref_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- RedM は州ごとに分かれているので、税を一つの国庫に丸めず州別・週別に追える
-- ようにする（ユーザー要望）。state は店舗の所在州（未設定・不明な取引は
-- 'unassigned'）、period は TreasuryMath.weekLabel() が作る 'YYYY-Www' 形式。
-- 組合補助金（dyn_guild）の週次予算はこの2列を軸に集計する。
ALTER TABLE dyn_treasury_ledger ADD COLUMN IF NOT EXISTS state  VARCHAR(32) NOT NULL DEFAULT 'unassigned';
ALTER TABLE dyn_treasury_ledger ADD COLUMN IF NOT EXISTS period VARCHAR(8)  NOT NULL DEFAULT '';
ALTER TABLE dyn_treasury_ledger ADD INDEX IF NOT EXISTS idx_state_period (state, period);
