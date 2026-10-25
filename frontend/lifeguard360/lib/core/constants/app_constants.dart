/// LifeGuard 360 Application Constants, Configuration Bounds & Safety Parameters.
class AppConstants {
  AppConstants._();

  static const String appName = 'LifeGuard 360';
  static const String appVersion = '1.0.0+1';

  // Configurable Timer Ranges
  static const int minGracePeriodMinutes = 1;
  static const int maxGracePeriodMinutes = 60;
  static const int defaultGracePeriodMinutes = 10;

  static const int minPreAlertSeconds = 10;
  static const int maxPreAlertSeconds = 45;
  static const int defaultPreAlertSeconds = 20;

  // Escalation & Outbox Bounds
  static const int maxOutboxRetries = 3;

  // Explainable Risk Engine Weights (Sum = 1.00)
  static const double weightCheckIn = 0.40;
  static const double weightImpact = 0.35;
  static const double weightBattery = 0.15;
  static const double weightTransit = 0.10;

  // Storage Keys
  static const String keyJwtToken = 'lg360_jwt_token';
  static const String keyUserData = 'lg360_user_data';
  static const String keyEmergencyPin = 'lg360_emergency_pin';
  static const String keyGracePeriodMinutes = 'lg360_grace_period_mins';
  static const String keyPreAlertSeconds = 'lg360_pre_alert_secs';
  static const String keyMonitoringActive = 'lg360_monitoring_active';
  static const String keyOfflineIncidents = 'lg360_offline_incidents_queue';
  static const String keyPendingCheckInOps = 'lg360_pending_checkin_ops';

  // Incident & Dispatch Statuses
  static const String statusQueuedOffline = 'QUEUED_OFFLINE';
  static const String statusQueued = 'QUEUED';
  static const String statusSent = 'SENT';
  static const String statusDelivered = 'DELIVERED';
  static const String statusAcknowledged = 'ACKNOWLEDGED';
  static const String statusFailed = 'FAILED';

  // Incident Lifecycle States
  static const String incidentActive = 'ACTIVE';
  static const String incidentResolved = 'RESOLVED';
  static const String incidentFalseAlarm = 'FALSE_ALARM';
  static const String incidentCancelled = 'CANCELLED';
}
