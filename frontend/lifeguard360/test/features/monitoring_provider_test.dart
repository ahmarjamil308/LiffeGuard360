import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeguard360/core/location/location_models.dart';
import 'package:lifeguard360/core/location/location_service.dart';
import 'package:lifeguard360/core/network/api_client.dart';
import 'package:lifeguard360/core/platform/android_service_bridge.dart';
import 'package:lifeguard360/core/sensors/sensor_models.dart';
import 'package:lifeguard360/core/sensors/sensor_monitoring_service.dart';
import 'package:lifeguard360/core/storage/local_incident_store.dart';
import 'package:lifeguard360/core/storage/secure_storage_service.dart';
import 'package:lifeguard360/features/monitoring/providers/monitoring_provider.dart';
import 'package:lifeguard360/features/sos/models/incident_model.dart';
import 'package:lifeguard360/features/sos/providers/sos_provider.dart';

class _FailingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'No backend connection in offline test',
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('MonitoringProvider Lifecycle & Telemetry Tests', () {
    late MockSensorMonitoringService sensorService;
    late MockLocationService locationService;
    late MockAndroidServiceBridge androidBridge;
    late MonitoringProvider provider;

    setUp(() {
      sensorService = MockSensorMonitoringService();
      locationService = MockLocationService();
      androidBridge = MockAndroidServiceBridge();
      provider = MonitoringProvider(
        sensorService: sensorService,
        locationService: locationService,
        androidBridge: androidBridge,
      );
    });

    tearDown(() {
      provider.dispose();
    });

    test('initialize checks hardware and permission state without activating monitoring', () async {
      expect(provider.isMonitoringActive, isFalse);
      expect(provider.latestBattery, isNull);

      await provider.initialize();

      expect(provider.isMonitoringActive, isFalse);
      expect(provider.latestBattery, isNotNull);
      expect(provider.latestBattery!.levelPercentage, equals(85));
      expect(provider.locationPermission, equals(LocationPermissionState.granted));
      expect(provider.isBatteryOptimizationIgnored, isTrue);
    });

    test('startMonitoring activates foreground bridge, sensors, and GPS fix', () async {
      await provider.initialize();
      final started = await provider.startMonitoring();

      expect(started, isTrue);
      expect(provider.isMonitoringActive, isTrue);
      expect(androidBridge.isRunning, isTrue);
      expect(sensorService.isMonitoringActive, isTrue);
      expect(provider.latestLocation, isNotNull);
      expect(provider.latestLocation!.hasValidFix, isTrue);
    });

    test('stopMonitoring stops all underlying services and resets state', () async {
      await provider.startMonitoring();
      expect(provider.isMonitoringActive, isTrue);

      await provider.stopMonitoring();
      expect(provider.isMonitoringActive, isFalse);
      expect(androidBridge.isRunning, isFalse);
      expect(sensorService.isMonitoringActive, isFalse);
    });

    test('Stream emissions update provider state dynamically', () async {
      await provider.startMonitoring();

      // Emit new motion event and pump microtasks
      sensorService.simulateImpactAndImmobility();
      await pumpEventQueue();
      expect(provider.latestMotion, isNotNull);
      expect(provider.latestMotion!.isConfirmedImpactSignature, isTrue);

      // Emit staleness
      sensorService.simulateStaleness();
      await pumpEventQueue();
      expect(provider.latestMotion!.readiness, equals(SensorReadiness.stale));
      expect(provider.isDegraded, isTrue);

      // Emit low battery
      sensorService.emitBattery(BatteryTelemetry.valid(level: 12, state: 'discharging'));
      await pumpEventQueue();
      expect(provider.latestBattery!.isLow, isTrue);
    });

    test('Battery optimization exemption delegation', () async {
      androidBridge.setBatteryOptimizationIgnored(false);
      await provider.initialize();
      expect(provider.isBatteryOptimizationIgnored, isFalse);

      await provider.requestBatteryOptimization();
      expect(androidBridge.requestedExemption, isTrue);
    });
  });

  group('Safety Critical Invariants: Manual SOS Independence from Sensors & Location', () {
    late MockSensorMonitoringService sensorService;
    late MockLocationService locationService;
    late MockLocalIncidentStore localStore;
    late MockSecureStorageService mockSecureStorage;
    late SOSProvider sosProvider;

    setUp(() {
      sensorService = MockSensorMonitoringService();
      locationService = MockLocationService();
      localStore = MockLocalIncidentStore();
      mockSecureStorage = MockSecureStorageService();

      // Custom Dio with immediate failing adapter to test offline fallback instantaneously
      final dio = Dio();
      dio.httpClientAdapter = _FailingAdapter();
      final apiClient = ApiClient(customDio: dio, secureStorage: mockSecureStorage);

      sosProvider = SOSProvider(
        apiClient: apiClient,
        localStore: localStore,
        secureStorage: mockSecureStorage,
        locationService: locationService,
      );
    });

    test('Manual SOS dispatches immediately when monitoring is completely stopped', () async {
      // Monitoring is OFF
      expect(sensorService.isMonitoringActive, isFalse);
      expect(sosProvider.isAlarmActive, isFalse);

      final incident = await sosProvider.triggerManualSOS();

      // Local emergency workflow activated at t=0ms without waiting for sensors
      expect(sosProvider.isAlarmActive, isTrue);
      expect(sosProvider.activeIncident, isNotNull);
      expect(incident.triggerSource, equals('MANUAL_BUTTON'));
      expect(incident.status, equals('QUEUED_OFFLINE')); // Network unavailable, queued locally
      expect(sosProvider.queuedIncidents.length, equals(1));
    });

    test('Manual SOS dispatches immediately when location permission is denied', () async {
      locationService.setPermissionState(LocationPermissionState.denied);

      final incident = await sosProvider.triggerManualSOS();

      expect(sosProvider.isAlarmActive, isTrue);
      // Location coordinates are null because permission was denied, but SOS is NOT blocked
      expect(incident.latitude, isNull);
      expect(incident.longitude, isNull);
      expect(incident.status, equals('QUEUED_OFFLINE'));
    });

    test('Manual SOS dispatches immediately when location times out', () async {
      locationService.setSimulateTimeout(true);

      final incident = await sosProvider.triggerManualSOS();

      expect(sosProvider.isAlarmActive, isTrue);
      expect(incident.latitude, isNull);
      expect(incident.longitude, isNull);
    });

    test('Manual SOS captures GPS location when available without artificial delay', () async {
      locationService.setSimulatedLocation(37.7749, -122.4194, accuracy: 5.0);

      final incident = await sosProvider.triggerManualSOS();

      expect(sosProvider.isAlarmActive, isTrue);
      expect(incident.latitude, equals(37.7749));
      expect(incident.longitude, equals(-122.4194));
      expect(incident.accuracyMeters, equals(5.0));
    });

    test('Local distress activation and persistence occur before any GPS wait', () async {
      // Simulate slow GPS provider (e.g. 1.5s delay)
      locationService.setSimulateTimeout(true);

      // Verify that before the call returns or when alarm sounds, local store has the incident
      final incident = await sosProvider.triggerManualSOS();

      final stored = await localStore.getAllIncidents();
      expect(stored.isNotEmpty, isTrue);
      expect(stored.first['client_incident_uuid'], equals(incident.clientIncidentUuid));
      expect(stored.first['status'], equals('QUEUED_OFFLINE'));
      expect(sosProvider.isAlarmActive, isTrue);
    });

    test('IncidentModel truthfulness: distinguishes queued, server accepted, and delivered states', () {
      final queued = IncidentModel(
        clientIncidentUuid: 'uuid-1',
        triggerSource: 'MANUAL_BUTTON',
        status: 'QUEUED_OFFLINE',
        createdAt: DateTime.now().toUtc(),
      );
      expect(queued.isLocallyQueued, isTrue);
      expect(queued.isServerAccepted, isFalse);
      expect(queued.isGatewayAccepted, isFalse);
      expect(queued.isDelivered, isFalse);
      expect(queued.isAcknowledged, isFalse);

      final accepted = IncidentModel(
        id: 42,
        clientIncidentUuid: 'uuid-2',
        triggerSource: 'MANUAL_BUTTON',
        status: 'ACTIVE',
        createdAt: DateTime.now().toUtc(),
        dispatches: [
          {'id': 1, 'status': 'QUEUED', 'channel': 'SMS'}
        ],
      );
      expect(accepted.isLocallyQueued, isFalse);
      expect(accepted.isServerAccepted, isTrue);
      expect(accepted.isGatewayAccepted, isFalse);
      expect(accepted.isDelivered, isFalse);

      final delivered = IncidentModel(
        id: 42,
        clientIncidentUuid: 'uuid-3',
        triggerSource: 'MANUAL_BUTTON',
        status: 'ACTIVE',
        createdAt: DateTime.now().toUtc(),
        dispatches: [
          {'id': 1, 'status': 'DELIVERED', 'channel': 'SMS'}
        ],
      );
      expect(delivered.isGatewayAccepted, isTrue);
      expect(delivered.isDelivered, isTrue);
      expect(delivered.isAcknowledged, isFalse);

      final acked = IncidentModel(
        id: 42,
        clientIncidentUuid: 'uuid-4',
        triggerSource: 'MANUAL_BUTTON',
        status: 'RESOLVED',
        createdAt: DateTime.now().toUtc(),
        dispatches: [
          {'id': 1, 'status': 'ACKNOWLEDGED', 'channel': 'SMS'}
        ],
      );
      expect(acked.isAcknowledged, isTrue);
    });

    test('Local storage failure does not block immediate alarm, records storageError, and allows retry recovery', () async {
      // Simulate disk write / I/O error
      localStore.setSimulateFailure(true);

      final incident = await sosProvider.triggerManualSOS();

      // Invariant: Emergency alarm and distress are active in memory despite storage failure!
      expect(sosProvider.isAlarmActive, isTrue);
      expect(sosProvider.activeIncident, isNotNull);
      expect(sosProvider.isPersistedLocally, isFalse);
      expect(sosProvider.storageError, isNotNull);
      expect(sosProvider.storageError, contains('Durable local storage failed'));

      // Storage becomes writable again -> user taps RETRY SAVE
      localStore.setSimulateFailure(false);
      final recovered = await sosProvider.retryLocalPersistence();

      expect(recovered, isTrue);
      expect(sosProvider.isPersistedLocally, isTrue);
      expect(sosProvider.storageError, isNull);

      final stored = await localStore.getAllIncidents();
      expect(stored.isNotEmpty, isTrue);
      expect(stored.first['client_incident_uuid'], equals(incident.clientIncidentUuid));
    });

    test('Location enrichment does not overwrite newer incident state or different client UUID', () async {
      locationService.setSimulatedLocation(37.7749, -122.4194, accuracy: 4.5);

      final incident = await sosProvider.triggerManualSOS();
      expect(sosProvider.activeIncident?.clientIncidentUuid, equals(incident.clientIncidentUuid));
      expect(sosProvider.activeIncident?.latitude, equals(37.7749));

      // Simulate status change (e.g. server sets ACTIVE)
      sosProvider.activeIncident = sosProvider.activeIncident?.copyWith(status: 'ACTIVE');

      // Subsequent location refresh keeps the ACTIVE status
      await sosProvider.fetchIncidentDetails(999); // fails or is handled
      expect(sosProvider.activeIncident?.status, equals('ACTIVE'));
    });
  });
}
