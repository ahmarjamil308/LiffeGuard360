import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'location_models.dart';

/// Contract for GPS location telemetry, privacy enforcement, and permission handling.
abstract class ILocationService {
  Future<LocationPermissionState> checkPermission();
  Future<LocationPermissionState> requestPermission();
  Future<LocationTelemetry?> getCurrentLocation({
    bool forceFresh = false,
    Duration timeout = const Duration(seconds: 5),
  });

  Stream<LocationTelemetry> get locationStream;
  LocationTelemetry? get lastKnownLocation;
  bool get isTracking;

  Future<void> startTracking();
  Future<void> stopTracking();
}

/// Production implementation using Geolocator plugin.
class LocationService implements ILocationService {
  final _locationController = StreamController<LocationTelemetry>.broadcast();
  StreamSubscription<Position>? _positionSub;
  LocationTelemetry? _lastLocation;
  bool _isTracking = false;

  @override
  Stream<LocationTelemetry> get locationStream => _locationController.stream;
  @override
  LocationTelemetry? get lastKnownLocation => _lastLocation;
  @override
  bool get isTracking => _isTracking;

  @override
  Future<LocationPermissionState> checkPermission() async {
    try {
      final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isServiceEnabled) return LocationPermissionState.denied;

      final perm = await Geolocator.checkPermission();
      return _mapGeolocatorPermission(perm);
    } catch (_) {
      return LocationPermissionState.denied;
    }
  }

  @override
  Future<LocationPermissionState> requestPermission() async {
    try {
      final perm = await Geolocator.requestPermission();
      return _mapGeolocatorPermission(perm);
    } catch (_) {
      return LocationPermissionState.denied;
    }
  }

  @override
  Future<LocationTelemetry?> getCurrentLocation({
    bool forceFresh = false,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // If not forced and recent cached location exists (< 30s), reuse to conserve battery
    if (!forceFresh && _lastLocation != null) {
      final age = DateTime.now().toUtc().difference(_lastLocation!.timestamp);
      if (age.inSeconds < 30) return _lastLocation;
    }

    try {
      final perm = await checkPermission();
      if (perm != LocationPermissionState.granted && perm != LocationPermissionState.approximateOnly) {
        return LocationTelemetry.unavailable(permission: perm);
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      ).timeout(timeout);

      final telemetry = LocationTelemetry.valid(
        latitude: position.latitude,
        longitude: position.longitude,
        altitude: position.altitude,
        accuracy: position.accuracy,
        timestamp: position.timestamp,
        provider: 'gps_fused',
      );

      _lastLocation = telemetry;
      _locationController.add(telemetry);
      return telemetry;
    } catch (e) {
      // If fresh fix times out or fails, fallback to last known if available
      if (_lastLocation != null) {
        final stale = LocationTelemetry.stale(
          latitude: _lastLocation!.latitude,
          longitude: _lastLocation!.longitude,
          accuracy: _lastLocation!.accuracyMeters,
          timestamp: _lastLocation!.timestamp,
        );
        return stale;
      }
      return LocationTelemetry.unavailable(reason: 'GPS fix error: $e');
    }
  }

  @override
  Future<void> startTracking() async {
    if (_isTracking) return;

    final perm = await checkPermission();
    if (perm != LocationPermissionState.granted) return;

    _isTracking = true;
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // 10 meters distance filter to avoid battery drain
      ),
    ).listen((position) {
      final telemetry = LocationTelemetry.valid(
        latitude: position.latitude,
        longitude: position.longitude,
        altitude: position.altitude,
        accuracy: position.accuracy,
        timestamp: position.timestamp,
        provider: 'gps_continuous',
      );
      _lastLocation = telemetry;
      _locationController.add(telemetry);
    }, onError: (_) {
      // Hardware location error does not crash the app
    });
  }

  @override
  Future<void> stopTracking() async {
    _isTracking = false;
    await _positionSub?.cancel();
    _positionSub = null;
  }

  LocationPermissionState _mapGeolocatorPermission(LocationPermission perm) {
    switch (perm) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionState.granted;
      case LocationPermission.denied:
        return LocationPermissionState.denied;
      case LocationPermission.deniedForever:
        return LocationPermissionState.permanentlyDenied;
      case LocationPermission.unableToDetermine:
        return LocationPermissionState.denied;
    }
  }
}

/// In-memory mock for automated unit and widget testing.
class MockLocationService implements ILocationService {
  final _locationController = StreamController<LocationTelemetry>.broadcast();
  LocationPermissionState _permissionState = LocationPermissionState.granted;
  LocationTelemetry? _lastLocation;
  bool _isTracking = false;
  bool _shouldSimulateTimeout = false;

  @override
  Stream<LocationTelemetry> get locationStream => _locationController.stream;
  @override
  LocationTelemetry? get lastKnownLocation => _lastLocation;
  @override
  bool get isTracking => _isTracking;

  void setPermissionState(LocationPermissionState state) {
    _permissionState = state;
  }

  void setSimulatedLocation(double lat, double lng, {double accuracy = 4.0, bool isStale = false}) {
    final now = isStale
        ? DateTime.now().toUtc().subtract(const Duration(minutes: 5))
        : DateTime.now().toUtc();
    _lastLocation = LocationTelemetry(
      latitude: lat,
      longitude: lng,
      accuracyMeters: accuracy,
      timestamp: now,
      isStale: isStale,
      permissionState: _permissionState,
      provider: 'mock_gps',
    );
  }

  void setSimulateTimeout(bool timeout) {
    _shouldSimulateTimeout = timeout;
  }

  @override
  Future<LocationPermissionState> checkPermission() async => _permissionState;

  @override
  Future<LocationPermissionState> requestPermission() async => _permissionState;

  @override
  Future<LocationTelemetry?> getCurrentLocation({
    bool forceFresh = false,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_shouldSimulateTimeout) {
      return LocationTelemetry.unavailable(reason: 'GPS timeout simulated');
    }

    if (_permissionState != LocationPermissionState.granted &&
        _permissionState != LocationPermissionState.approximateOnly) {
      return LocationTelemetry.unavailable(permission: _permissionState);
    }

    _lastLocation ??= LocationTelemetry.valid(
      latitude: 37.7749,
      longitude: -122.4194,
      accuracy: 4.5,
      provider: 'mock_gps',
    );

    _locationController.add(_lastLocation!);
    return _lastLocation;
  }

  @override
  Future<void> startTracking() async {
    _isTracking = true;
    if (_lastLocation != null) _locationController.add(_lastLocation!);
  }

  @override
  Future<void> stopTracking() async {
    _isTracking = false;
  }
}
