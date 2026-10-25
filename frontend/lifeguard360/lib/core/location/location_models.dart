/// Granular permission states for location access.
enum LocationPermissionState {
  granted,
  denied,
  permanentlyDenied,
  revoked,
  approximateOnly,
}

/// Structured location telemetry with accuracy verification and privacy controls.
class LocationTelemetry {
  final double latitude;
  final double longitude;
  final double? altitude;
  final double accuracyMeters;
  final DateTime timestamp;
  final bool isStale;
  final LocationPermissionState permissionState;
  final String provider; // gps, fused, network, mock

  LocationTelemetry({
    required this.latitude,
    required this.longitude,
    this.altitude,
    required this.accuracyMeters,
    required this.timestamp,
    required this.isStale,
    required this.permissionState,
    required this.provider,
  });

  factory LocationTelemetry.valid({
    required double latitude,
    required double longitude,
    double? altitude,
    required double accuracy,
    DateTime? timestamp,
    String provider = 'fused',
  }) {
    final now = timestamp ?? DateTime.now().toUtc();
    final isOld = DateTime.now().toUtc().difference(now).inSeconds > 60;
    return LocationTelemetry(
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      accuracyMeters: accuracy,
      timestamp: now,
      isStale: isOld,
      permissionState: LocationPermissionState.granted,
      provider: provider,
    );
  }

  factory LocationTelemetry.stale({
    required double latitude,
    required double longitude,
    required double accuracy,
    required DateTime timestamp,
  }) {
    return LocationTelemetry(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracy,
      timestamp: timestamp,
      isStale: true,
      permissionState: LocationPermissionState.granted,
      provider: 'cached',
    );
  }

  factory LocationTelemetry.unavailable({
    LocationPermissionState permission = LocationPermissionState.denied,
    String reason = 'Location unavailable or permission denied',
  }) {
    return LocationTelemetry(
      latitude: 0.0,
      longitude: 0.0,
      accuracyMeters: -1,
      timestamp: DateTime.now().toUtc(),
      isStale: true,
      permissionState: permission,
      provider: 'none',
    );
  }

  bool get hasValidFix =>
      permissionState == LocationPermissionState.granted &&
      accuracyMeters > 0 &&
      accuracyMeters <= 50;

  bool get isHighAccuracy => hasValidFix && accuracyMeters <= 15;
}
