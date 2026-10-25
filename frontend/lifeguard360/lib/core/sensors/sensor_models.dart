import 'dart:math';

/// State of hardware sensor availability, permissions, and streaming health.
enum SensorReadiness {
  valid,
  stale,
  unavailable,
  permissionDenied,
  serviceFailed,
}

/// Composite overall monitoring lifecycle state.
enum MonitoringLifecycleStatus {
  active,
  degraded,
  stopped,
  permissionsRequired,
}

/// Structured motion telemetry with impact debounce and stationary recognition.
class MotionTelemetry {
  final DateTime timestamp;
  final double x;
  final double y;
  final double z;
  final double magnitude; // sqrt(x^2 + y^2 + z^2) in m/s^2
  final double instantaneousG; // Current sample magnitude in g-forces (1g ~= 9.80665 m/s^2)
  final double? qualifyingImpactG; // Peak g-force of the preceding qualifying impact (>=2.8g)
  final DateTime? qualifyingImpactTimestamp; // Timestamp of qualifying impact
  final Duration postImpactImmobility; // Duration of verified relative immobility
  final SensorReadiness readiness;
  final String statusDescription;

  MotionTelemetry({
    required this.timestamp,
    required this.x,
    required this.y,
    required this.z,
    required this.magnitude,
    required this.instantaneousG,
    this.qualifyingImpactG,
    this.qualifyingImpactTimestamp,
    this.postImpactImmobility = Duration.zero,
    required this.readiness,
    required this.statusDescription,
  });

  /// Backward-compatible getter returning qualifying impact peak if present, else instantaneous G.
  double get peakImpactG => qualifyingImpactG ?? instantaneousG;

  /// Factory from raw 3-axis accelerometer readings
  factory MotionTelemetry.fromRawAxes({
    required double x,
    required double y,
    required double z,
    DateTime? timestamp,
    double? peakImpactG,
    Duration postImpactImmobility = Duration.zero,
  }) {
    final now = timestamp ?? DateTime.now().toUtc();
    final mag = sqrt(x * x + y * y + z * z);
    final gForce = mag / 9.80665;
    final peak = peakImpactG ?? (gForce >= 2.8 ? gForce : null);

    String desc = 'Nominal Movement';
    if (gForce >= 0.88 && gForce <= 1.12) {
      desc = 'Stationary Resting (R = 0 - Not an Emergency)';
    } else if (peak != null && peak >= 2.8 && postImpactImmobility >= const Duration(seconds: 5)) {
      desc = 'Candidate Fall Event (Heuristic: Impact >= 2.8g + 5s Immobility)';
    } else if (gForce >= 2.8) {
      desc = 'Qualifying Impact Detected (>=2.8g) - Awaiting Immobility Verification';
    } else if (gForce > 1.6) {
      desc = 'Transient Motion Spike (Debounced - Not an Emergency)';
    }

    return MotionTelemetry(
      timestamp: now,
      x: x,
      y: y,
      z: z,
      magnitude: mag,
      instantaneousG: gForce,
      qualifyingImpactG: peak,
      postImpactImmobility: postImpactImmobility,
      readiness: SensorReadiness.valid,
      statusDescription: desc,
    );
  }

  /// Factory for a confirmed candidate fall heuristic event.
  factory MotionTelemetry.candidateFall({
    required double x,
    required double y,
    required double z,
    required double impactPeakG,
    required DateTime impactTimestamp,
    required Duration immobilityDuration,
  }) {
    final mag = sqrt(x * x + y * y + z * z);
    return MotionTelemetry(
      timestamp: DateTime.now().toUtc(),
      x: x,
      y: y,
      z: z,
      magnitude: mag,
      instantaneousG: mag / 9.80665,
      qualifyingImpactG: impactPeakG,
      qualifyingImpactTimestamp: impactTimestamp,
      postImpactImmobility: immobilityDuration,
      readiness: SensorReadiness.valid,
      statusDescription: 'Candidate Fall Event: Impact >= 2.8g + 5s Immobility (Heuristic)',
    );
  }

  factory MotionTelemetry.stale() {
    return MotionTelemetry(
      timestamp: DateTime.now().toUtc().subtract(const Duration(minutes: 2)),
      x: 0,
      y: 0,
      z: 0,
      magnitude: 0,
      instantaneousG: 0,
      qualifyingImpactG: null,
      readiness: SensorReadiness.stale,
      statusDescription: 'Stale Sensor Stream (>30s without event)',
    );
  }

  factory MotionTelemetry.unavailable([String reason = 'Sensor hardware absent or denied']) {
    return MotionTelemetry(
      timestamp: DateTime.now().toUtc(),
      x: 0,
      y: 0,
      z: 0,
      magnitude: 0,
      instantaneousG: 0,
      qualifyingImpactG: null,
      readiness: SensorReadiness.unavailable,
      statusDescription: reason,
    );
  }

  /// Candidate fall event detected by heuristic: peak impact >= 2.8g followed by >= 5s immobility.
  /// NOTE: This is a heuristic risk indicator, NOT medical-grade proof of an actual fall.
  bool get isConfirmedImpactSignature =>
      readiness == SensorReadiness.valid &&
      (qualifyingImpactG ?? 0.0) >= 2.8 &&
      postImpactImmobility >= const Duration(seconds: 5);

  /// Alias for isConfirmedImpactSignature emphasizing heuristic candidate status.
  bool get isCandidateFallSignature => isConfirmedImpactSignature;

  /// True if device is resting flat/still (|a| ~ 1.0g).
  /// Invariant: A stationary phone resting on a table produces R = 0.
  bool get isStationary =>
      readiness == SensorReadiness.valid &&
      (instantaneousG >= 0.88 && instantaneousG <= 1.12);

  bool get isValid => readiness == SensorReadiness.valid;
}

/// Structured battery level and charging state telemetry.
class BatteryTelemetry {
  final int levelPercentage; // 0 - 100
  final String chargingState; // charging, discharging, full, unknown
  final DateTime timestamp;
  final SensorReadiness readiness;

  BatteryTelemetry({
    required this.levelPercentage,
    required this.chargingState,
    required this.timestamp,
    required this.readiness,
  });

  factory BatteryTelemetry.valid({
    required int level,
    required String state,
  }) {
    return BatteryTelemetry(
      levelPercentage: level.clamp(0, 100),
      chargingState: state,
      timestamp: DateTime.now().toUtc(),
      readiness: SensorReadiness.valid,
    );
  }

  factory BatteryTelemetry.unavailable() {
    return BatteryTelemetry(
      levelPercentage: -1,
      chargingState: 'unknown',
      timestamp: DateTime.now().toUtc(),
      readiness: SensorReadiness.unavailable,
    );
  }

  bool get isCritical => readiness == SensorReadiness.valid && levelPercentage > 0 && levelPercentage <= 10;
  bool get isLow => readiness == SensorReadiness.valid && levelPercentage > 10 && levelPercentage <= 20;
  bool get isValid => readiness == SensorReadiness.valid && levelPercentage >= 0;
}

/// Structured transit and motion activity telemetry.
class TransitTelemetry {
  final String activityType; // stationary, walking, running, in_vehicle, unknown
  final double confidence; // 0.0 - 1.0
  final DateTime timestamp;
  final SensorReadiness readiness;

  TransitTelemetry({
    required this.activityType,
    required this.confidence,
    required this.timestamp,
    required this.readiness,
  });

  factory TransitTelemetry.valid({
    required String type,
    double confidence = 1.0,
  }) {
    return TransitTelemetry(
      activityType: type,
      confidence: confidence,
      timestamp: DateTime.now().toUtc(),
      readiness: SensorReadiness.valid,
    );
  }

  factory TransitTelemetry.unavailable() {
    return TransitTelemetry(
      activityType: 'unknown',
      confidence: 0.0,
      timestamp: DateTime.now().toUtc(),
      readiness: SensorReadiness.unavailable,
    );
  }

  bool get isValid => readiness == SensorReadiness.valid;
}

/// Composite monitoring system health across all sensors.
class CompositeMonitoringHealth {
  final MonitoringLifecycleStatus status;
  final bool isForegroundServiceRunning;
  final bool isBatteryOptimizationIgnored;
  final SensorReadiness motionHealth;
  final SensorReadiness batteryHealth;
  final SensorReadiness transitHealth;
  final SensorReadiness locationHealth;
  final String summaryText;

  CompositeMonitoringHealth({
    required this.status,
    required this.isForegroundServiceRunning,
    required this.isBatteryOptimizationIgnored,
    required this.motionHealth,
    required this.batteryHealth,
    required this.transitHealth,
    required this.locationHealth,
    required this.summaryText,
  });

  bool get isFullyActive => status == MonitoringLifecycleStatus.active;
  bool get isDegraded => status == MonitoringLifecycleStatus.degraded;
}
