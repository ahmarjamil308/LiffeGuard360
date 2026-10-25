import 'package:flutter_test/flutter_test.dart';
import 'package:lifeguard360/core/sensors/sensor_models.dart';
import 'package:lifeguard360/core/sensors/sensor_monitoring_service.dart';

void main() {
  group('SensorModels - MotionTelemetry Tests', () {
    test('Magnitude and G-force calculation is physically accurate', () {
      // 0, 0, 9.80665 should yield magnitude ~ 9.80665 and G-force ~ 1.0
      final telemetry = MotionTelemetry.fromRawAxes(x: 0, y: 0, z: 9.80665);

      expect(telemetry.magnitude, closeTo(9.80665, 0.001));
      expect(telemetry.peakImpactG, closeTo(1.0, 0.001));
      expect(telemetry.readiness, equals(SensorReadiness.valid));
      expect(telemetry.isValid, isTrue);
    });

    test('Stationary phone on flat surface produces R = 0 state (not an emergency)', () {
      final telemetry = MotionTelemetry.fromRawAxes(x: 0.1, y: 0.0, z: 9.81);

      expect(telemetry.isStationary, isTrue);
      expect(telemetry.isConfirmedImpactSignature, isFalse);
      expect(telemetry.statusDescription, contains('Stationary Resting'));
    });

    test('Transient acceleration spike without immobility is debounced', () {
      // e.g. Phone picked up quickly or jostled in pocket: 2.3g
      final mag = 2.3 * 9.80665;
      final telemetry = MotionTelemetry.fromRawAxes(x: 0, y: 0, z: mag);

      expect(telemetry.peakImpactG, closeTo(2.3, 0.01));
      expect(telemetry.isConfirmedImpactSignature, isFalse);
      expect(telemetry.statusDescription, contains('Transient Motion Spike (Debounced'));
    });

    test('Impact above 2.8g without 5s immobility is not confirmed impact', () {
      final mag = 3.2 * 9.80665;
      final telemetry = MotionTelemetry.fromRawAxes(
        x: 0,
        y: 0,
        z: mag,
        postImpactImmobility: const Duration(seconds: 2), // only 2s immobility
      );

      expect(telemetry.peakImpactG, closeTo(3.2, 0.01));
      expect(telemetry.isConfirmedImpactSignature, isFalse);
    });

    test('Impact >= 2.8g followed by verified 5s immobility confirms impact signature', () {
      final mag = 3.5 * 9.80665;
      final telemetry = MotionTelemetry.fromRawAxes(
        x: 0,
        y: 0,
        z: mag,
        postImpactImmobility: const Duration(seconds: 5), // verified 5s immobility
      );

      expect(telemetry.peakImpactG, closeTo(3.5, 0.01));
      expect(telemetry.isConfirmedImpactSignature, isTrue);
      expect(telemetry.isCandidateFallSignature, isTrue);
      expect(telemetry.statusDescription, contains('Candidate Fall Event'));
    });

    test('Ordinary phone handling and walking produces nominal state and zero emergency', () {
      // Walking produces mild acceleration fluctuations ~ 1.25g
      final mag = 1.25 * 9.80665;
      final telemetry = MotionTelemetry.fromRawAxes(x: 1.5, y: 2.0, z: mag);

      expect(telemetry.isConfirmedImpactSignature, isFalse);
      expect(telemetry.isCandidateFallSignature, isFalse);
      expect(telemetry.statusDescription, equals('Nominal Movement'));
    });

    test('Stale sensor telemetry is marked SensorReadiness.stale and not valid', () {
      final stale = MotionTelemetry.stale();

      expect(stale.readiness, equals(SensorReadiness.stale));
      expect(stale.isValid, isFalse);
      expect(stale.isConfirmedImpactSignature, isFalse);
      expect(stale.statusDescription, contains('Stale'));
    });

    test('Unavailable sensor telemetry is marked SensorReadiness.unavailable', () {
      final unavail = MotionTelemetry.unavailable('Hardware accelerometer absent');

      expect(unavail.readiness, equals(SensorReadiness.unavailable));
      expect(unavail.isValid, isFalse);
      expect(unavail.statusDescription, equals('Hardware accelerometer absent'));
    });
  });

  group('SensorModels - Battery & Transit Telemetry Tests', () {
    test('BatteryTelemetry levels classify critical, low, and nominal accurately', () {
      final critical = BatteryTelemetry.valid(level: 8, state: 'discharging');
      expect(critical.isCritical, isTrue);
      expect(critical.isLow, isFalse);
      expect(critical.isValid, isTrue);

      final low = BatteryTelemetry.valid(level: 15, state: 'discharging');
      expect(low.isCritical, isFalse);
      expect(low.isLow, isTrue);
      expect(low.isValid, isTrue);

      final nominal = BatteryTelemetry.valid(level: 75, state: 'charging');
      expect(nominal.isCritical, isFalse);
      expect(nominal.isLow, isFalse);
      expect(nominal.isValid, isTrue);
    });

    test('BatteryTelemetry unavailable is safely marked', () {
      final unavail = BatteryTelemetry.unavailable();
      expect(unavail.readiness, equals(SensorReadiness.unavailable));
      expect(unavail.isValid, isFalse);
      expect(unavail.isCritical, isFalse);
      expect(unavail.isLow, isFalse);
    });

    test('TransitTelemetry captures activity type and validity', () {
      final transit = TransitTelemetry.valid(type: 'walking', confidence: 0.95);
      expect(transit.activityType, equals('walking'));
      expect(transit.confidence, equals(0.95));
      expect(transit.isValid, isTrue);

      final unavail = TransitTelemetry.unavailable();
      expect(unavail.readiness, equals(SensorReadiness.unavailable));
      expect(unavail.isValid, isFalse);
    });
  });

  group('CompositeMonitoringHealth Lifecycle Tests', () {
    test('Reflects active status when sensors are valid and service is running', () {
      final health = CompositeMonitoringHealth(
        status: MonitoringLifecycleStatus.active,
        isForegroundServiceRunning: true,
        isBatteryOptimizationIgnored: true,
        motionHealth: SensorReadiness.valid,
        batteryHealth: SensorReadiness.valid,
        transitHealth: SensorReadiness.valid,
        locationHealth: SensorReadiness.valid,
        summaryText: 'All hardware sensors active & nominal',
      );

      expect(health.isFullyActive, isTrue);
      expect(health.isDegraded, isFalse);
      expect(health.status, equals(MonitoringLifecycleStatus.active));
    });

    test('Reflects degraded status when motion health is stale or unavailable', () {
      final health = CompositeMonitoringHealth(
        status: MonitoringLifecycleStatus.degraded,
        isForegroundServiceRunning: true,
        isBatteryOptimizationIgnored: true,
        motionHealth: SensorReadiness.stale,
        batteryHealth: SensorReadiness.valid,
        transitHealth: SensorReadiness.valid,
        locationHealth: SensorReadiness.valid,
        summaryText: 'Sensor readings degraded or stale',
      );

      expect(health.isFullyActive, isFalse);
      expect(health.isDegraded, isTrue);
    });
  });

  group('MockSensorMonitoringService Control & Stream Tests', () {
    late MockSensorMonitoringService service;

    setUp(() {
      service = MockSensorMonitoringService();
    });

    test('initialize populates initial battery and transit telemetry', () async {
      expect(service.lastBattery, isNull);
      final ok = await service.initialize();
      expect(ok, isTrue);
      expect(service.lastBattery, isNotNull);
      expect(service.lastBattery!.levelPercentage, equals(85));
      expect(service.lastTransit, isNotNull);
      expect(service.lastTransit!.activityType, equals('stationary'));
    });

    test('startMonitoring activates service and emits initial motion and health', () async {
      final motionExpectation = expectLater(
        service.motionStream,
        emits(predicate<MotionTelemetry>((m) => m.isValid)),
      );
      final healthExpectation = expectLater(
        service.healthStream,
        emits(predicate<CompositeMonitoringHealth>((h) => h.isFullyActive)),
      );

      final ok = await service.startMonitoring();
      expect(ok, isTrue);
      expect(service.isMonitoringActive, isTrue);
      expect(service.currentHealth.status, equals(MonitoringLifecycleStatus.active));

      await motionExpectation;
      await healthExpectation;
    });

    test('stopMonitoring stops service and updates health to stopped', () async {
      await service.startMonitoring();
      expect(service.isMonitoringActive, isTrue);

      await service.stopMonitoring();
      expect(service.isMonitoringActive, isFalse);
      expect(service.currentHealth.status, equals(MonitoringLifecycleStatus.stopped));
    });

    test('simulateStationaryPhone produces stationary telemetry and safe health', () async {
      await service.startMonitoring();
      service.simulateStationaryPhone();

      expect(service.lastMotion, isNotNull);
      expect(service.lastMotion!.isStationary, isTrue);
      expect(service.lastMotion!.isConfirmedImpactSignature, isFalse);
    });

    test('1. Impact followed by continuous movement cancels candidate fall', () async {
      await service.startMonitoring();
      // Step A: Impact spike 3.2g occurs
      service.simulateImpact(peakG: 3.2);
      expect(service.lastMotion!.instantaneousG, closeTo(3.2, 0.05));

      // Step B: Resumed active movement sample 1.9g arrives
      service.simulateMovementSample(gForce: 1.9);
      expect(service.lastMotion!.instantaneousG, closeTo(1.9, 0.05));
      expect(service.lastMotion!.isCandidateFallSignature, isFalse);
      expect(service.lastMotion!.statusDescription, contains('Transient Motion Spike (Debounced'));
    });

    test('2. Impact followed by five seconds of relative immobility emits candidate fall', () async {
      await service.startMonitoring();
      // Step A: Impact spike 3.5g
      service.simulateImpact(peakG: 3.5);

      // Step B: 5 seconds of confirmed stillness
      service.simulateImpactAndImmobility(peakG: 3.5, immobility: const Duration(seconds: 5));

      expect(service.lastMotion!.isCandidateFallSignature, isTrue);
      expect(service.lastMotion!.peakImpactG, closeTo(3.5, 0.05));
      expect(service.lastMotion!.postImpactImmobility.inSeconds, greaterThanOrEqualTo(5));
      expect(service.lastMotion!.statusDescription, contains('Candidate Fall Event'));
    });

    test('3. Impact followed by unavailable or stale sensor data cancels candidate and NEVER confirms', () async {
      await service.startMonitoring();
      // Step A: Impact occurs
      service.simulateImpact(peakG: 3.4);

      // Step B: Sensor stream fails / drops
      service.simulateFailure('Bus disconnect');

      expect(service.lastMotion!.readiness, equals(SensorReadiness.unavailable));
      expect(service.lastMotion!.isCandidateFallSignature, isFalse);
      expect(service.lastMotion!.statusDescription, equals('Bus disconnect'));

      // Step C: Stale sensor feed also cancels candidate
      service.simulateStaleness();
      expect(service.lastMotion!.readiness, equals(SensorReadiness.stale));
      expect(service.lastMotion!.isCandidateFallSignature, isFalse);
    });

    test('4. Ordinary walking and routine phone handling never triggers fall candidate', () async {
      await service.startMonitoring();
      // Step A: Walking ~ 1.25g
      service.simulateWalking();
      expect(service.lastMotion!.isCandidateFallSignature, isFalse);
      expect(service.lastMotion!.statusDescription, equals('Nominal Movement'));

      // Step B: Routine handling / turning ~ 1.3g
      service.simulateRoutineHandling();
      expect(service.lastMotion!.isCandidateFallSignature, isFalse);
      expect(service.lastMotion!.statusDescription, equals('Nominal Movement'));
    });

    test('5. Stationary phone without preceding impact produces stationary state and zero emergency', () async {
      await service.startMonitoring();
      service.simulateStationaryPhone();

      expect(service.lastMotion!.isStationary, isTrue);
      expect(service.lastMotion!.isCandidateFallSignature, isFalse);
      expect(service.lastMotion!.statusDescription, contains('Stationary Resting'));
    });

    test('6. Repeated impacts update peak magnitude and restart verification countdown', () async {
      await service.startMonitoring();
      // First impact 2.9g
      service.simulateImpact(peakG: 2.9);
      expect(service.lastMotion!.instantaneousG, closeTo(2.9, 0.05));

      // Secondary bounce 3.6g occurs
      service.simulateImpact(peakG: 3.6);
      expect(service.lastMotion!.instantaneousG, closeTo(3.6, 0.05));

      // After settling, 5s immobility confirms with the highest peak (3.6g)
      service.simulateImpactAndImmobility(peakG: 3.6, immobility: const Duration(seconds: 5));
      expect(service.lastMotion!.isCandidateFallSignature, isTrue);
      expect(service.lastMotion!.peakImpactG, closeTo(3.6, 0.05));
    });

    test('simulateStaleness updates motion health to stale and degrades composite health', () async {
      await service.startMonitoring();
      service.simulateStaleness();

      expect(service.lastMotion!.readiness, equals(SensorReadiness.stale));
      expect(service.currentHealth.motionHealth, equals(SensorReadiness.stale));
      expect(service.currentHealth.isDegraded, isTrue);
    });

    test('simulateFailure updates motion health to unavailable', () async {
      await service.startMonitoring();
      service.simulateFailure('Bus I/O error');

      expect(service.lastMotion!.readiness, equals(SensorReadiness.unavailable));
      expect(service.lastMotion!.statusDescription, equals('Bus I/O error'));
    });
  });
}
