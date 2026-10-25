import 'package:flutter_test/flutter_test.dart';
import 'package:lifeguard360/core/location/location_models.dart';
import 'package:lifeguard360/core/location/location_service.dart';

void main() {
  group('LocationModels - LocationTelemetry Tests', () {
    test('Valid telemetry initializes properly and evaluates accuracy flags', () {
      final loc = LocationTelemetry.valid(
        latitude: 37.7749,
        longitude: -122.4194,
        altitude: 15.2,
        accuracy: 8.5,
      );

      expect(loc.latitude, equals(37.7749));
      expect(loc.longitude, equals(-122.4194));
      expect(loc.altitude, equals(15.2));
      expect(loc.accuracyMeters, equals(8.5));
      expect(loc.isStale, isFalse);
      expect(loc.permissionState, equals(LocationPermissionState.granted));
      expect(loc.hasValidFix, isTrue);
      expect(loc.isHighAccuracy, isTrue); // <= 15m
    });

    test('Medium accuracy fix is valid but not high accuracy', () {
      final loc = LocationTelemetry.valid(
        latitude: 37.7749,
        longitude: -122.4194,
        accuracy: 35.0, // <= 50m but > 15m
      );

      expect(loc.hasValidFix, isTrue);
      expect(loc.isHighAccuracy, isFalse);
    });

    test('Poor accuracy fix (> 50m) is not considered a valid fix', () {
      final loc = LocationTelemetry.valid(
        latitude: 37.7749,
        longitude: -122.4194,
        accuracy: 85.0, // > 50m
      );

      expect(loc.hasValidFix, isFalse);
      expect(loc.isHighAccuracy, isFalse);
    });

    test('Stale telemetry is marked as stale with cached provider', () {
      final pastTime = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
      final stale = LocationTelemetry.stale(
        latitude: 37.7749,
        longitude: -122.4194,
        accuracy: 10.0,
        timestamp: pastTime,
      );

      expect(stale.isStale, isTrue);
      expect(stale.provider, equals('cached'));
      expect(stale.timestamp, equals(pastTime));
    });

    test('Unavailable telemetry safely defaults and reports negative accuracy', () {
      final unavail = LocationTelemetry.unavailable(
        permission: LocationPermissionState.denied,
        reason: 'User denied permission',
      );

      expect(unavail.latitude, equals(0.0));
      expect(unavail.longitude, equals(0.0));
      expect(unavail.accuracyMeters, equals(-1));
      expect(unavail.hasValidFix, isFalse);
      expect(unavail.isStale, isTrue);
      expect(unavail.permissionState, equals(LocationPermissionState.denied));
    });
  });

  group('MockLocationService Tests', () {
    late MockLocationService service;

    setUp(() {
      service = MockLocationService();
    });

    test('Default permission is granted and returns valid fix', () async {
      final perm = await service.checkPermission();
      expect(perm, equals(LocationPermissionState.granted));

      final fix = await service.getCurrentLocation();
      expect(fix, isNotNull);
      expect(fix!.hasValidFix, isTrue);
      expect(fix.latitude, equals(37.7749));
      expect(fix.longitude, equals(-122.4194));
    });

    test('Denied permission returns unavailable telemetry without crashing', () async {
      service.setPermissionState(LocationPermissionState.denied);

      final perm = await service.checkPermission();
      expect(perm, equals(LocationPermissionState.denied));

      final fix = await service.getCurrentLocation();
      expect(fix, isNotNull);
      expect(fix!.hasValidFix, isFalse);
      expect(fix.permissionState, equals(LocationPermissionState.denied));
    });

    test('Permanently denied permission returns unavailable telemetry', () async {
      service.setPermissionState(LocationPermissionState.permanentlyDenied);

      final fix = await service.getCurrentLocation();
      expect(fix, isNotNull);
      expect(fix!.hasValidFix, isFalse);
      expect(fix.permissionState, equals(LocationPermissionState.permanentlyDenied));
    });

    test('Simulated timeout returns unavailable telemetry without crashing', () async {
      service.setSimulateTimeout(true);

      final fix = await service.getCurrentLocation();
      expect(fix, isNotNull);
      expect(fix!.hasValidFix, isFalse);
      expect(fix.provider, equals('none'));
    });

    test('Simulated custom location and staleness', () async {
      service.setSimulatedLocation(40.7128, -74.0060, accuracy: 5.0, isStale: true);

      final fix = await service.getCurrentLocation();
      expect(fix, isNotNull);
      expect(fix!.latitude, equals(40.7128));
      expect(fix.longitude, equals(-74.0060));
      expect(fix.isStale, isTrue);
    });

    test('Continuous tracking stream emits updates and toggles isTracking', () async {
      expect(service.isTracking, isFalse);

      service.setSimulatedLocation(51.5074, -0.1278);

      final streamExpectation = expectLater(
        service.locationStream,
        emits(predicate<LocationTelemetry>((loc) => loc.latitude == 51.5074)),
      );

      await service.startTracking();
      expect(service.isTracking, isTrue);

      await streamExpectation;

      await service.stopTracking();
      expect(service.isTracking, isFalse);
    });
  });
}
