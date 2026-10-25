-- ==============================================================================
-- LifeGuard 360 Relational Database Schema (MySQL 8.0+)
-- Authoritative schema definition with relational integrity, indexes, and constraints.
-- ==============================================================================

CREATE DATABASE IF NOT EXISTS `lifeguard360` 
  CHARACTER SET utf8mb4 
  COLLATE utf8mb4_unicode_ci;

USE `lifeguard360`;

-- 1. Users Table
CREATE TABLE IF NOT EXISTS `users` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `uuid` VARCHAR(36) NOT NULL UNIQUE,
    `full_name` VARCHAR(120) NOT NULL,
    `email` VARCHAR(191) NOT NULL UNIQUE,
    `phone` VARCHAR(30) NOT NULL UNIQUE,
    `password_hash` VARCHAR(255) NOT NULL,
    `blood_group` VARCHAR(10) NULL,
    `allergies` TEXT NULL,
    `medical_notes` TEXT NULL,
    `emergency_notes` TEXT NULL,
    `default_emergency_number` VARCHAR(20) NOT NULL DEFAULT '911',
    `checkin_grace_period_minutes` INT NOT NULL DEFAULT 10,
    `pre_alert_countdown_seconds` INT NOT NULL DEFAULT 20,
    `is_active` BOOLEAN NOT NULL DEFAULT TRUE,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_users_email` (`email`),
    INDEX `idx_users_phone` (`phone`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. Emergency Contacts Table (Priority-Tiered)
CREATE TABLE IF NOT EXISTS `emergency_contacts` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `user_id` BIGINT UNSIGNED NOT NULL,
    `name` VARCHAR(120) NOT NULL,
    `phone` VARCHAR(30) NOT NULL,
    `email` VARCHAR(191) NULL,
    `relationship` VARCHAR(50) NOT NULL DEFAULT 'Friend',
    `priority_tier` TINYINT NOT NULL DEFAULT 1 COMMENT '1=Primary, 2=Secondary, 3=Guardian/Medical',
    `notify_sms` BOOLEAN NOT NULL DEFAULT TRUE,
    `notify_push` BOOLEAN NOT NULL DEFAULT TRUE,
    `notify_call` BOOLEAN NOT NULL DEFAULT FALSE,
    `is_active` BOOLEAN NOT NULL DEFAULT TRUE,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT `fk_contacts_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
    INDEX `idx_contacts_user_tier` (`user_id`, `priority_tier`, `is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. Smart Scheduled Check-Ins Table
CREATE TABLE IF NOT EXISTS `check_ins` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `user_id` BIGINT UNSIGNED NOT NULL,
    `title` VARCHAR(150) NOT NULL DEFAULT 'Routine Check-In',
    `destination_note` VARCHAR(255) NULL,
    `scheduled_for` DATETIME NOT NULL,
    `grace_period_minutes` INT NOT NULL DEFAULT 10,
    `pre_alert_seconds` INT NOT NULL DEFAULT 20,
    `status` ENUM('SCHEDULED', 'SAFE_COMPLETED', 'IN_GRACE_PERIOD', 'OVERDUE_PRE_ALERT', 'OVERDUE_ESCALATED', 'CANCELLED') NOT NULL DEFAULT 'SCHEDULED',
    `safety_pin_hash` VARCHAR(255) NULL,
    `checked_in_at` DATETIME NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT `fk_checkins_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
    INDEX `idx_checkins_user_status` (`user_id`, `status`),
    INDEX `idx_checkins_schedule` (`scheduled_for`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. Emergency Incidents Table (Idempotent client_incident_uuid)
CREATE TABLE IF NOT EXISTS `incidents` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `client_incident_uuid` VARCHAR(36) NOT NULL UNIQUE COMMENT 'Client-generated UUID for idempotent offline sync',
    `user_id` BIGINT UNSIGNED NOT NULL,
    `trigger_source` ENUM('MANUAL', 'AUTOMATED_RISK', 'OVERDUE_CHECKIN', 'SEVERE_FALL') NOT NULL,
    `risk_score_at_trigger` DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    `status` ENUM('QUEUED_OFFLINE', 'ACTIVE', 'CANCELLED_FALSE_ALARM', 'RESOLVED') NOT NULL DEFAULT 'ACTIVE',
    `trigger_latitude` DOUBLE NULL,
    `trigger_longitude` DOUBLE NULL,
    `location_accuracy` FLOAT NULL,
    `false_alarm_reason` VARCHAR(255) NULL,
    `triggered_at` DATETIME NOT NULL,
    `resolved_at` DATETIME NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT `fk_incidents_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
    INDEX `idx_incidents_user_status` (`user_id`, `status`),
    INDEX `idx_incidents_triggered_at` (`triggered_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. Incident Dispatches Table (Multi-Tier Delivery Tracking)
CREATE TABLE IF NOT EXISTS `incident_dispatches` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `incident_id` BIGINT UNSIGNED NOT NULL,
    `contact_id` BIGINT UNSIGNED NULL,
    `tier` TINYINT NOT NULL DEFAULT 1,
    `channel` ENUM('PUSH', 'SMS', 'TELEPHONY') NOT NULL DEFAULT 'PUSH',
    `dispatch_status` ENUM('QUEUED_OFFLINE', 'QUEUED', 'SENT', 'DELIVERED', 'ACKNOWLEDGED', 'FAILED') NOT NULL DEFAULT 'QUEUED',
    `message_body` TEXT NOT NULL,
    `gateway_message_id` VARCHAR(100) NULL,
    `sent_at` DATETIME NULL,
    `acknowledged_at` DATETIME NULL,
    `failure_reason` VARCHAR(255) NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_dispatches_incident` FOREIGN KEY (`incident_id`) REFERENCES `incidents` (`id`) ON DELETE CASCADE,
    CONSTRAINT `fk_dispatches_contact` FOREIGN KEY (`contact_id`) REFERENCES `emergency_contacts` (`id`) ON DELETE SET NULL,
    INDEX `idx_dispatches_incident_tier` (`incident_id`, `tier`, `dispatch_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 6. Sensor & Location Telemetry Table
CREATE TABLE IF NOT EXISTS `sensor_telemetry` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `user_id` BIGINT UNSIGNED NOT NULL,
    `incident_id` BIGINT UNSIGNED NULL,
    `latitude` DOUBLE NULL,
    `longitude` DOUBLE NULL,
    `speed` FLOAT NULL,
    `altitude` FLOAT NULL,
    `accuracy` FLOAT NULL,
    `accel_rms` FLOAT NULL,
    `motion_variance` FLOAT NULL,
    `battery_percentage` INT NULL,
    `is_charging` BOOLEAN NULL,
    `telemetry_status` ENUM('NORMAL', 'STALE', 'DEGRADED', 'OFFLINE') NOT NULL DEFAULT 'NORMAL',
    `recorded_at` DATETIME NOT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_telemetry_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
    CONSTRAINT `fk_telemetry_incident` FOREIGN KEY (`incident_id`) REFERENCES `incidents` (`id`) ON DELETE SET NULL,
    INDEX `idx_telemetry_user_time` (`user_id`, `recorded_at`),
    INDEX `idx_telemetry_incident` (`incident_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 7. Risk Assessments Log Table (Formula Verification & Transparency)
CREATE TABLE IF NOT EXISTS `risk_assessments` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `user_id` BIGINT UNSIGNED NOT NULL,
    `composite_score` INT NOT NULL,
    `risk_level` ENUM('SAFE', 'CAUTION', 'CRITICAL') NOT NULL,
    `checkin_score` INT NOT NULL,
    `impact_score` INT NOT NULL,
    `battery_score` INT NOT NULL,
    `transit_score` INT NOT NULL,
    `factors_json` JSON NOT NULL,
    `explanation_text` TEXT NOT NULL,
    `disclaimer` TEXT NOT NULL,
    `evaluated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_risk_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
    INDEX `idx_risk_user_time` (`user_id`, `evaluated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 8. Immutable Audit Logs Table
CREATE TABLE IF NOT EXISTS `audit_logs` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `user_id` BIGINT UNSIGNED NULL,
    `event_type` VARCHAR(80) NOT NULL,
    `action_description` VARCHAR(255) NOT NULL,
    `ip_address` VARCHAR(45) NULL,
    `user_agent` VARCHAR(255) NULL,
    `event_metadata_json` JSON NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_audit_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
    INDEX `idx_audit_user_type` (`user_id`, `event_type`),
    INDEX `idx_audit_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
