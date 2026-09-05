-- 002_blueprints.sql — 図面の保存
--
-- 適用: mariadb -u <user> -p <database> < fivem/sql/migrations/002_blueprints.sql
-- 冪等。
--
-- CAD で描いた図面を保存する。data は JSON で、壁の芯線・開口・部屋を持つ。
-- 形式は fivem/tools/plan_model.py と揃える（同じデータを Python 側でも扱えるように）。

CREATE TABLE IF NOT EXISTS `gain_blueprints` (
    `id`         BIGINT       NOT NULL AUTO_INCREMENT,
    `citizenid`  VARCHAR(16)  NOT NULL,
    `name`       VARCHAR(64)  NOT NULL DEFAULT '無題',
    `system`     VARCHAR(16)  NOT NULL DEFAULT '木造軸組',
    `data`       LONGTEXT     NOT NULL,
    `area`       DECIMAL(8,2) NOT NULL DEFAULT 0,
    `props`      INT          NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_blueprints_owner` (`citizenid`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
