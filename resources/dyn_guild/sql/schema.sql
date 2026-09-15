-- dyn_guild — 組合・補助金の台帳（設計ドキュメント §9.6）
-- 注意: 起動時の自動マイグレーションはコメントを落としてからセミコロンで文を分割する。
--       文字列リテラルの中にコメント記号やセミコロンを含む定義はここに書かないこと。

CREATE TABLE IF NOT EXISTS dyn_guilds (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  name          VARCHAR(64) NOT NULL UNIQUE,
  category      VARCHAR(32) NOT NULL,
  purpose       VARCHAR(255) NULL,
  founder       VARCHAR(64) NOT NULL,
  state         VARCHAR(32) NOT NULL,      -- どの州の週次予算から補助を受けるか
  status        ENUM('pending','approved','rejected','revoked','dissolved') NOT NULL DEFAULT 'pending',
  applied_at    DATETIME NOT NULL,
  decided_at    DATETIME NULL,
  decided_by    VARCHAR(64) NULL,
  reject_reason VARCHAR(255) NULL,
  last_active   DATETIME NULL,
  INDEX idx_status (status),
  INDEX idx_state (state)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dyn_guild_members (
  guild_id    INT NOT NULL,
  identifier  VARCHAR(64) NOT NULL,
  role        ENUM('founder','officer','member') NOT NULL DEFAULT 'member',
  joined_at   DATETIME NOT NULL,
  PRIMARY KEY (guild_id, identifier),
  UNIQUE KEY uq_one_guild (identifier),    -- 1 キャラ 1 組合
  CONSTRAINT fk_gm_guild FOREIGN KEY (guild_id) REFERENCES dyn_guilds(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dyn_guild_subsidy_rules (
  guild_id    INT NOT NULL,
  item        VARCHAR(64) NOT NULL,
  mode        ENUM('accrual','instant') NOT NULL DEFAULT 'accrual',
  rate        DECIMAL(5,3) NULL,           -- instant: 支払いの何割を国庫が負担するか
  unit_amount DECIMAL(12,2) NULL,          -- accrual: 出荷 1 個あたりの補助額
  daily_cap   DECIMAL(12,2) NULL,
  enabled     TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (guild_id, item),
  CONSTRAINT fk_gsr_guild FOREIGN KEY (guild_id) REFERENCES dyn_guilds(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dyn_subsidy_payouts (
  id          BIGINT AUTO_INCREMENT PRIMARY KEY,
  guild_id    INT NOT NULL,
  identifier  VARCHAR(64) NOT NULL,
  item        VARCHAR(64) NOT NULL,
  qty         INT NOT NULL,
  amount      DECIMAL(12,2) NOT NULL,
  mode        ENUM('accrual','instant') NOT NULL,
  period      VARCHAR(16) NULL,            -- 'YYYY-Www'
  paid_at     DATETIME NOT NULL,
  INDEX idx_guild_period (guild_id, period),
  INDEX idx_ident_time (identifier, paid_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 出荷実績の週次集計（accrual モードの原資データ）。
-- dyn_economy:committed の sell を拾って積む。組合に入っていない売却も
-- 一旦ここには積むが、補助金の計算時に組合員でない分は無視される
-- （後から組合に入っても、入る前の出荷実績は遡って補助されない）。
CREATE TABLE IF NOT EXISTS dyn_guild_shipments (
  identifier  VARCHAR(64) NOT NULL,
  item        VARCHAR(64) NOT NULL,
  period      VARCHAR(16) NOT NULL,
  qty         INT NOT NULL DEFAULT 0,
  PRIMARY KEY (identifier, item, period)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 「直近に週次補助を支払い終えた週」だけを覚えておく単一行テーブル。
-- サーバーが週をまたいで落ちていても、次の起動時に前週分を1回だけ払える
CREATE TABLE IF NOT EXISTS dyn_guild_state (
  k VARCHAR(32) NOT NULL PRIMARY KEY,
  v VARCHAR(32) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
