-- 001_ledger.sql — 取引履歴を「残高が再現できる台帳」にする
--
-- 適用: mariadb -u <user> -p <database> < fivem/sql/migrations/001_ledger.sql
-- 冪等。何度実行しても同じ状態になる（MariaDB 10.2+ / 10.6 で確認）。
--
-- 背景:
--   設計仕様は「残高の変更は必ず取引履歴を伴い、残高は履歴から再現できる」と
--   定めているが、当初のスキーマには口座の別（cash / bank）も符号も無く、
--   deposit の1行から「cash が減って bank が増えた」ことを復元できなかった。
--   つまり不変条件がそもそも表現できていなかった。
--
-- 不変条件（この migration 以降）:
--   SUM(delta) WHERE citizenid = ? AND account = ?  ==  gain_characters.<account>

ALTER TABLE `gain_transactions`
    ADD COLUMN IF NOT EXISTS `account` VARCHAR(8) NOT NULL DEFAULT '' AFTER `citizenid`,
    ADD COLUMN IF NOT EXISTS `delta`   BIGINT     NOT NULL DEFAULT 0  AFTER `amount`,
    ADD COLUMN IF NOT EXISTS `balance` BIGINT     NOT NULL DEFAULT 0  AFTER `delta`;

-- 照合クエリ（citizenid + account で SUM）用
ALTER TABLE `gain_transactions`
    ADD KEY IF NOT EXISTS `idx_transactions_recon` (`citizenid`, `account`, `id`);

-- 既存行は account を復元できないため account='' のまま残し、delta=0 で照合対象から外す。
-- 代わりに移行時点の残高を opening として1本ずつ計上し、そこを起点に再現できるようにする。
INSERT INTO `gain_transactions` (`citizenid`, `account`, `kind`, `amount`, `delta`, `balance`, `reason`)
SELECT `citizenid`, 'cash', 'opening', `cash`, `cash`, `cash`, '移行時点の残高'
FROM `gain_characters`
WHERE NOT EXISTS (
    SELECT 1 FROM `gain_transactions` t
    WHERE t.`citizenid` = `gain_characters`.`citizenid` AND t.`account` = 'cash' AND t.`kind` = 'opening'
);

INSERT INTO `gain_transactions` (`citizenid`, `account`, `kind`, `amount`, `delta`, `balance`, `reason`)
SELECT `citizenid`, 'bank', 'opening', `bank`, `bank`, `bank`, '移行時点の残高'
FROM `gain_characters`
WHERE NOT EXISTS (
    SELECT 1 FROM `gain_transactions` t
    WHERE t.`citizenid` = `gain_characters`.`citizenid` AND t.`account` = 'bank' AND t.`kind` = 'opening'
);
