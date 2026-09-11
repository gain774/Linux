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
