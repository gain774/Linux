-- dyn_trade — 個人間取引の監査ログ + 取引用アイテムの登録
-- 注意: 起動時の自動マイグレーションはコメントを落としてからセミコロンで文を分割する。
-- 文字列リテラルの中にコメント記号やセミコロンを含む定義はここに書かないこと。

CREATE TABLE IF NOT EXISTS dyn_p2p_tx (
  id           BIGINT AUTO_INCREMENT PRIMARY KEY,
  created_at   DATETIME      NOT NULL,
  char_a       VARCHAR(64)   NOT NULL,
  char_b       VARCHAR(64)   NOT NULL,
  items_a      JSON          NULL,
  items_b      JSON          NULL,
  cash_a       DECIMAL(14,2) NOT NULL DEFAULT 0,
  cash_b       DECIMAL(14,2) NOT NULL DEFAULT 0,
  fee_a        DECIMAL(12,2) NOT NULL DEFAULT 0,
  fee_b        DECIMAL(12,2) NOT NULL DEFAULT 0,
  INDEX idx_time (created_at),
  INDEX idx_char_a (char_a, created_at),
  INDEX idx_char_b (char_b, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 取引を始めるための道具。vorp_inventory の items テーブルに無いと使用登録できないので
-- ここで自動的に用意する（既にあれば usable=1 に揃えるだけで上書きしない）
INSERT INTO items (item, label, `limit`, can_remove, type, usable, useExpired, groupId, rarityId, metadata, `desc`, degradation, durability, instructions, weight)
VALUES ('trade_ledger', '個人取引台帳', 1, 1, 'item_standard', 1, 0, 1, 1, '{}', '近くの相手に個人間取引を申し込むための台帳。使用すると一番近いプレイヤーに取引を申し込む', 0, NULL, NULL, 0.10)
ON DUPLICATE KEY UPDATE usable = 1;
