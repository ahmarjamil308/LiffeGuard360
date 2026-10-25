import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/location/location_models.dart';
import '../../../core/location/location_service.dart';
import '../../../core/platform/android_service_bridge.dart';
import '../../../core/sensors/sensor_models.dart';
import '../../../core/sensors/sensor_monitoring_service.dart';

/// Provider managing active sensor monitoring, location telemetry, and Android foreground service lifecycle.
class MonitoringProvider extends ChangeNotifier {
  final ISensorMonitoringService _sensorService;
  final ILocationService _locationService;
  final IAndroidServiceBridge _androidBridge;

  StreamSubscription<MotionTelemetry>? _motionSub;
  StreamSubscription<BatteryTelemetry>? _batterySub;
  StreamSubscription<TransitTelemetry>? _transitSub;
  StreamSubscription<CompositeMonitoringHealth>? _healthSub;
  StreamSubscription<LocationTelemetry>? _locationSub;

  bool _isMonitoringActive = false;
  MotionTelemetry? _latestMotion;
  BatteryTelemetry? _latestBattery;
  TransitTelemetry? _latestTransit;
  LocationTelemetry? _latestLocation;
  LocationPermissionState _locationPermission = LocationPermissionState.denied;
  bool _isBatteryOptimizationIgnored = true;

  MonitoringProvider({
    required ISensorMonitoringService sensorService,
    required ILocationService locationService,
    required IAndroidServiceBridge androidBridge,
  })  : _sensorService = sensorService,
        _locationService = locationService,
        _androidBridge = androidBridge;

  bool get isMonitoringActive => _isMonitoringActive;
  bool get isDegraded => _sensorService.currentHealth.isDegraded;
  MotionTelemetry? get latestMotion => _latestMotion;
  BatteryTelemetry? get latestBattery => _latestBattery;
  TransitTelemetry? get latestTransit => _latestTransit;
  LocationTelemetry? get latestLocation => _latestLocation;
  LocationPermissionState get locationPermission => _locationPermission;
  bool get isBatteryOptimizationIgnored => _isBatteryOptimizationIgnored;
  CompositeMonitoringHealth get compositeHealth => _sensorService.currentHealth;

  Future<void> initialize() async {
    await _sensorService.initialize();
    _locationPermission = await _locationService.checkPermission();
    _isBatteryOptimizationIgnored = await _androidBridge.isBatteryOptimizationIgnored();

    // Check if foreground service is already running on boot or warm restart
    final isServiceRunning = await _androidBridge.isForegroundServiceRunning();
    if (isServiceRunning) {
      await startMonitoring();
    } else {
      _latestMotion = _sensorService.lastMotion;
      _latestBattery = _sensorService.lastBattery;
      _latestTransit = _sensorService.lastTransit;
      notifyListeners();
    }
  }

  Future<bool> startMonitoring() async {
    // 1. Request location permission if not already granted
    _locationPermission = await _locationService.requestPermission();
    if (_locationPermission != LocationPermissionState.granted &&
        _locationPermission != LocationPermissionState.approximateOnly) {
      _isMonitoringActive = false;
      notifyListeners();
      return false;
    }

    // 2. Start native Android foreground service with location type
    final serviceStarted = await _androidBridge.startForegroundService();

    // 3. Start sensor stream and debouncing
    final sensorsStarted = await _sensorService.startMonitoring();

    if (serviceStarted && sensorsStarted) {
      _isMonitoringActive = true;
      _subscribeStreams();
      // Fetch initial fresh GPS location
      _latestLocation = await _locationService.getCurrentLocation();
      notifyListeners();
      return true;
    } else {
      _isMonitoringActive = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> stopMonitoring() async {
    _isMonitoringActive = false;
    await _sensorService.stopMonitoring();
    await _locationService.stopTracking();
    await _androidBridge.stopForegroundService();
    await _unsubscribeStreams();
    notifyListeners();
  }

  Future<void> refreshLocation() async {
    _latestLocation = await _locationService.getCurrentLocation(forceFresh: true);
    notifyListeners();
  }

  Future<void> requestBatteryOptimization() async {
    await _androidBridge.requestBatteryOptimizationExemption();
    _isBatteryOptimizationIgnored = await _androidBridge.isBatteryOptimizationIgnored();
    notifyListeners();
  }

  void _subscribeStreams() {
    _motionSub?.cancel();
    _motionSub = _sensorService.motionStream.listen((m) {
      _latestMotion = m;
      notifyListeners();
    });

    _batterySub?.cancel();
    _batterySub = _sensorService.batteryStream.listen((b) {
      _latestBattery = b;
      notifyListeners();
    });

    _transitSub?.cancel();
    _transitSub = _sensorService.transitStream.listen((t) {
      _latestTransit = t;
      notifyListeners();
    });

    _healthSub?.cancel();
    _healthSub = _sensorService.healthStream.listen((_) {
      notifyListeners();
    });

    _locationSub?.cancel();
    _locationSub = _locationService.locationStream.listen((loc) {
      _latestLocation = loc;
      notifyListeners();
    });
  }

  Future<void> _unsubscribeStreams() async {
    await _motionSub?.cancel();
    await _batterySub?.cancel();
    await _transitSub?.cancel();
    await _healthSub?.cancel();
    await _locationSub?.cancel();
    _motionSub = null;
    _batterySub = null;
    _transitSub = null;
    _healthSub = null;
    _locationSub = null;
  }

  @override
  void dispose() {
    _unsubscribeStreams();
    super.dispose();
  }
}
