-- dyn_economy — Phase 1〜2 で必要なテーブル（設計ドキュメント §3）
-- 後続フェーズのテーブル（委託所 §8 / 国庫・組合 §9 / 成長曲線 §7）は
-- それぞれのリソース側の schema.sql で定義する。
-- 注意: 起動時の自動マイグレーションはコメントを落としてからセミコロンで文を分割する。
-- 文字列リテラルの中にコメント記号やセミコロンを含む定義はここに書かないこと。

CREATE TABLE IF NOT EXISTS dyn_items (
  item            VARCHAR(64)   NOT NULL PRIMARY KEY,
  category        VARCHAR(32)   NOT NULL DEFAULT 'misc',
  price_index     DECIMAL(12,4) NOT NULL,
  base_price      DECIMAL(12,2) NOT NULL DEFAULT 0,
  target_stock    DECIMAL(14,2) NOT NULL,
  elasticity      DECIMAL(5,3)  NOT NULL DEFAULT 0.500,
  min_mult        DECIMAL(5,3)  NOT NULL DEFAULT 0.200,
  max_mult        DECIMAL(5,3)  NOT NULL DEFAULT 3.000,
  half_life_min   INT           NOT NULL DEFAULT 720,
  npc_spread      DECIMAL(5,3)  NOT NULL DEFAULT 0.300,
  npc_sellable    TINYINT(1)    NOT NULL DEFAULT 1,
  npc_buyable     TINYINT(1)    NOT NULL DEFAULT 1,
  pinned          TINYINT(1)    NOT NULL DEFAULT 0,
  enabled         TINYINT(1)    NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dyn_item_state (
  item            VARCHAR(64)   NOT NULL PRIMARY KEY,
  virtual_stock   DECIMAL(14,4) NOT NULL,
  cached_buy      DECIMAL(12,2) NOT NULL DEFAULT 0,
  cached_sell     DECIMAL(12,2) NOT NULL DEFAULT 0,
  mat_cost        DECIMAL(12,4) NULL,
  updated_at      DATETIME      NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dyn_npc_tx (
  id              BIGINT AUTO_INCREMENT PRIMARY KEY,
  identifier      VARCHAR(64)   NOT NULL,
  item            VARCHAR(64)   NOT NULL,
  direction       ENUM('sell','buy') NOT NULL,
  qty             INT           NOT NULL,
  unit_price      DECIMAL(12,4) NOT NULL,
  total           DECIMAL(14,2) NOT NULL,
  tax_amount      DECIMAL(12,2) NOT NULL DEFAULT 0,
  stock_before    DECIMAL(14,4) NOT NULL,
  stock_after     DECIMAL(14,4) NOT NULL,
  shop            VARCHAR(64)   NULL,
  price_breakdown JSON          NULL,
  voided          TINYINT(1)    NOT NULL DEFAULT 0,
  created_at      DATETIME      NOT NULL,
  INDEX idx_item_time (item, created_at),
  INDEX idx_ident_time (identifier, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dyn_recipes (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  output_item VARCHAR(64) NOT NULL,
  output_qty  INT         NOT NULL DEFAULT 1,
  source      VARCHAR(64) NOT NULL,
  UNIQUE KEY uq_out_src (output_item, source)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dyn_recipe_inputs (
  recipe_id   INT           NOT NULL,
  item        VARCHAR(64)   NOT NULL,
  qty         DECIMAL(10,3) NOT NULL,
  PRIMARY KEY (recipe_id, item),
  CONSTRAINT fk_ri_recipe FOREIGN KEY (recipe_id) REFERENCES dyn_recipes(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dyn_price_history (
  item         VARCHAR(64)   NOT NULL,
  bucket_at    DATETIME      NOT NULL,
  npc_buy      DECIMAL(12,4) NOT NULL,
  npc_sell     DECIMAL(12,4) NOT NULL,
  player_vwap  DECIMAL(12,4) NULL,
  vol_npc_sell INT           NOT NULL DEFAULT 0,
  vol_npc_buy  INT           NOT NULL DEFAULT 0,
  vol_player   INT           NOT NULL DEFAULT 0,
  PRIMARY KEY (item, bucket_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dyn_econ_config (
  k           VARCHAR(64)   NOT NULL PRIMARY KEY,
  v           DECIMAL(18,6) NOT NULL,
  updated_at  DATETIME      NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dyn_econ_snapshot (
  snapshot_at    DATETIME      NOT NULL PRIMARY KEY,
  money_total    DECIMAL(18,2) NOT NULL,
  money_median   DECIMAL(14,2) NULL,
  money_p90      DECIMAL(14,2) NULL,
  money_p99      DECIMAL(14,2) NULL,
  characters     INT           NOT NULL DEFAULT 0,
  active_players INT           NOT NULL DEFAULT 0,
  outliers       INT           NOT NULL DEFAULT 0,
  basket_price   DECIMAL(14,4) NULL,
  currency_scale DECIMAL(14,6) NOT NULL DEFAULT 1,
  expected_total DECIMAL(18,2) NULL,
  drift          DECIMAL(10,4) NULL,
  held           TINYINT(1)    NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dyn_wealth_outlier (
  detected_at DATETIME      NOT NULL,
  identifier  VARCHAR(64)   NOT NULL,
  amount      DECIMAL(16,2) NOT NULL,
  median_ref  DECIMAL(16,2) NOT NULL,
  mad_score   DECIMAL(10,3) NOT NULL,
  reviewed    TINYINT(1)    NOT NULL DEFAULT 0,
  PRIMARY KEY (detected_at, identifier),
  INDEX idx_reviewed (reviewed, detected_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
