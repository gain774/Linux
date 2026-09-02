-- gain framework スキーマ
-- 適用: mysql -u <user> -p <database> < fivem/sql/schema.sql
--
-- 文字コードは日本語のキャラ名を通すため utf8mb4 で統一する。

CREATE TABLE IF NOT EXISTS `gain_users` (
    `license`     VARCHAR(64)  NOT NULL,
    `name`        VARCHAR(64)  NOT NULL DEFAULT '',
    `permission`  VARCHAR(16)  NOT NULL DEFAULT 'user',
    `created_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_seen`   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`license`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `gain_characters` (
    `citizenid`   VARCHAR(16)  NOT NULL,
    `license`     VARCHAR(64)  NOT NULL,
    `firstname`   VARCHAR(32)  NOT NULL DEFAULT '',
    `lastname`    VARCHAR(32)  NOT NULL DEFAULT '',
    `cash`        BIGINT       NOT NULL DEFAULT 0,
    `bank`        BIGINT       NOT NULL DEFAULT 0,
    `job`         VARCHAR(32)  NOT NULL DEFAULT 'unemployed',
    `job_grade`   INT          NOT NULL DEFAULT 0,
    `job_duty`    TINYINT(1)   NOT NULL DEFAULT 0,
    `position`    TEXT         DEFAULT NULL,
    `metadata`    LONGTEXT     DEFAULT NULL,
    `created_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`citizenid`),
    KEY `idx_characters_license` (`license`),
    CONSTRAINT `fk_characters_user`
        FOREIGN KEY (`license`) REFERENCES `gain_users` (`license`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- expires_at が NULL なら無期限 BAN
CREATE TABLE IF NOT EXISTS `gain_bans` (
    `id`          INT          NOT NULL AUTO_INCREMENT,
    `license`     VARCHAR(64)  NOT NULL,
    `name`        VARCHAR(64)  NOT NULL DEFAULT '',
    `reason`      VARCHAR(255) NOT NULL DEFAULT '',
    `banned_by`   VARCHAR(64)  NOT NULL DEFAULT 'system',
    `created_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `expires_at`  TIMESTAMP    NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_bans_license` (`license`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `gain_logs` (
    `id`          BIGINT       NOT NULL AUTO_INCREMENT,
    `category`    VARCHAR(16)  NOT NULL DEFAULT 'info',
    `message`     VARCHAR(255) NOT NULL DEFAULT '',
    `meta`        LONGTEXT     DEFAULT NULL,
    `created_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_logs_category` (`category`),
    KEY `idx_logs_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
