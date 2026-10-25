import 'dart:async';
import 'dart:math';
import 'package:battery_plus/battery_plus.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'sensor_models.dart';

/// Contract for hardware sensor monitoring, debounce windows, and readiness tracking.
abstract class ISensorMonitoringService {
  Future<bool> initialize();
  Future<bool> startMonitoring();
  Future<void> stopMonitoring();

  Stream<MotionTelemetry> get motionStream;
  Stream<BatteryTelemetry> get batteryStream;
  Stream<TransitTelemetry> get transitStream;
  Stream<CompositeMonitoringHealth> get healthStream;

  CompositeMonitoringHealth get currentHealth;
  bool get isMonitoringActive;
  MotionTelemetry? get lastMotion;
  BatteryTelemetry? get lastBattery;
  TransitTelemetry? get lastTransit;
}

/// Production Android hardware sensor monitoring service.
class SensorMonitoringService implements ISensorMonitoringService {
  final Battery _battery;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  Timer? _stalenessTimer;
  Timer? _immobilityTimer;

  final _motionController = StreamController<MotionTelemetry>.broadcast();
  final _batteryController = StreamController<BatteryTelemetry>.broadcast();
  final _transitController = StreamController<TransitTelemetry>.broadcast();
  final _healthController = StreamController<CompositeMonitoringHealth>.broadcast();

  bool _isMonitoringActive = false;
  MotionTelemetry? _lastMotion;
  BatteryTelemetry? _lastBattery;
  TransitTelemetry? _lastTransit;

  // Impact evaluation state
  double? _qualifyingImpactPeakG;
  DateTime? _qualifyingImpactTimestamp;
  bool _isAwaitingImmobility = false;
  int _immobilitySampleCount = 0;

  SensorMonitoringService({Battery? battery}) : _battery = battery ?? Battery();

  @override
  Stream<MotionTelemetry> get motionStream => _motionController.stream;
  @override
  Stream<BatteryTelemetry> get batteryStream => _batteryController.stream;
  @override
  Stream<TransitTelemetry> get transitStream => _transitController.stream;
  @override
  Stream<CompositeMonitoringHealth> get healthStream => _healthController.stream;

  @override
  bool get isMonitoringActive => _isMonitoringActive;
  @override
  MotionTelemetry? get lastMotion => _lastMotion;
  @override
  BatteryTelemetry? get lastBattery => _lastBattery;
  @override
  TransitTelemetry? get lastTransit => _lastTransit;

  @override
  CompositeMonitoringHealth get currentHealth {
    final status = !_isMonitoringActive
        ? MonitoringLifecycleStatus.stopped
        : (_lastMotion?.readiness == SensorReadiness.valid
            ? MonitoringLifecycleStatus.active
            : MonitoringLifecycleStatus.degraded);

    return CompositeMonitoringHealth(
      status: status,
      isForegroundServiceRunning: _isMonitoringActive,
      isBatteryOptimizationIgnored: true,
      motionHealth: _lastMotion?.readiness ?? SensorReadiness.unavailable,
      batteryHealth: _lastBattery?.readiness ?? SensorReadiness.unavailable,
      transitHealth: _lastTransit?.readiness ?? SensorReadiness.unavailable,
      locationHealth: SensorReadiness.valid,
      summaryText: status == MonitoringLifecycleStatus.active
          ? 'All hardware sensors active & nominal'
          : (status == MonitoringLifecycleStatus.stopped
              ? 'Monitoring stopped by user'
              : 'Sensor readings degraded or stale'),
    );
  }

  @override
  Future<bool> initialize() async {
    try {
      await _readBattery();
      _lastTransit = TransitTelemetry.valid(type: 'stationary');
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> startMonitoring() async {
    if (_isMonitoringActive) return true;

    try {
      _isMonitoringActive = true;
      _startStalenessWatchdog();

      // Subscribe to accelerometer stream (20Hz standard sampling)
      _accelSub = accelerometerEventStream().listen(
        _processAccelerometerEvent,
        onError: (err) {
          _isAwaitingImmobility = false;
          _qualifyingImpactPeakG = null;
          _qualifyingImpactTimestamp = null;
          _immobilityTimer?.cancel();
          _immobilityTimer = null;
          final unavailable = MotionTelemetry.unavailable('Sensor stream error: $err');
          _lastMotion = unavailable;
          _motionController.add(unavailable);
          _broadcastHealth();
        },
      );

      await _readBattery();
      _broadcastHealth();
      return true;
    } catch (e) {
      _isMonitoringActive = false;
      return false;
    }
  }

  @override
  Future<void> stopMonitoring() async {
    _isMonitoringActive = false;
    await _accelSub?.cancel();
    _accelSub = null;
    _stalenessTimer?.cancel();
    _immobilityTimer?.cancel();
    _immobilityTimer = null;
    _isAwaitingImmobility = false;
    _qualifyingImpactPeakG = null;
    _qualifyingImpactTimestamp = null;
    _immobilitySampleCount = 0;
    _broadcastHealth();
  }

  void _processAccelerometerEvent(AccelerometerEvent event) {
    _resetStalenessWatchdog();

    final now = DateTime.now().toUtc();
    final mag = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    final instantaneousG = mag / 9.80665;

    // 1. Check for qualifying impact spike (>= 2.8g)
    if (instantaneousG >= 2.8) {
      if (!_isAwaitingImmobility) {
        // Initial qualifying impact
        _isAwaitingImmobility = true;
        _qualifyingImpactPeakG = instantaneousG;
        _qualifyingImpactTimestamp = now;
        _immobilitySampleCount = 0;
        _startImmobilityVerification();
      } else {
        // Repeated impact during settling/verification: update peak and restart countdown
        _qualifyingImpactPeakG = max(_qualifyingImpactPeakG ?? 0.0, instantaneousG);
        _qualifyingImpactTimestamp = now;
        _immobilitySampleCount = 0;
        _startImmobilityVerification();
      }
    } else if (_isAwaitingImmobility && _qualifyingImpactTimestamp != null) {
      // 2. Evaluate subsequent motion samples for resumed voluntary movement
      final elapsed = now.difference(_qualifyingImpactTimestamp!);

      // Ignore sub-second bounce settling (first 300ms)
      if (elapsed >= const Duration(milliseconds: 300)) {
        // Distinguish stillness from ordinary noise / voluntary movement:
        // Movement threshold: instantaneous gForce > 1.6g OR deviation from stationary 1g > 0.45g
        final isMovementResumed = instantaneousG > 1.6 || (instantaneousG - 1.0).abs() > 0.45;

        if (isMovementResumed) {
          // Voluntary motion resumed -> candidate cancelled as false alarm
          _isAwaitingImmobility = false;
          _qualifyingImpactPeakG = null;
          _qualifyingImpactTimestamp = null;
          _immobilitySampleCount = 0;
          _immobilityTimer?.cancel();
          _immobilityTimer = null;
        } else {
          // Relative immobility sample confirmed
          _immobilitySampleCount++;
          if (elapsed >= const Duration(seconds: 5) && _immobilitySampleCount >= 5) {
            // Verified 5s immobility with continuous valid samples -> Candidate fall heuristic event
            final candidate = MotionTelemetry.candidateFall(
              x: event.x,
              y: event.y,
              z: event.z,
              impactPeakG: _qualifyingImpactPeakG ?? 2.8,
              impactTimestamp: _qualifyingImpactTimestamp ?? now,
              immobilityDuration: elapsed,
            );
            _lastMotion = candidate;
            _motionController.add(candidate);
            _isAwaitingImmobility = false;
            _qualifyingImpactPeakG = null;
            _qualifyingImpactTimestamp = null;
            _immobilitySampleCount = 0;
            _immobilityTimer?.cancel();
            _immobilityTimer = null;
            return;
          }
        }
      }
    }

    final telemetry = MotionTelemetry.fromRawAxes(
      x: event.x,
      y: event.y,
      z: event.z,
      timestamp: now,
      peakImpactG: _isAwaitingImmobility ? _qualifyingImpactPeakG : null,
    );

    _lastMotion = telemetry;
    _motionController.add(telemetry);
  }

  void _startImmobilityVerification() {
    _immobilityTimer?.cancel();
    _immobilityTimer = Timer(const Duration(seconds: 5), () {
      // Timer acts as a fallback timeout check; confirmation requires valid samples in _processAccelerometerEvent.
      // If no valid samples arrived or stream errored, immobility is never falsely confirmed!
      if (_immobilitySampleCount < 5) {
        _isAwaitingImmobility = false;
        _qualifyingImpactPeakG = null;
        _qualifyingImpactTimestamp = null;
      }
    });
  }

  Future<void> _readBattery() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      final telemetry = BatteryTelemetry.valid(
        level: level,
        state: state.name,
      );
      _lastBattery = telemetry;
      _batteryController.add(telemetry);
    } catch (_) {
      _lastBattery = BatteryTelemetry.unavailable();
    }
  }

  void _startStalenessWatchdog() {
    _stalenessTimer?.cancel();
    _stalenessTimer = Timer(const Duration(seconds: 30), () {
      if (_isMonitoringActive) {
        _isAwaitingImmobility = false;
        _qualifyingImpactPeakG = null;
        _qualifyingImpactTimestamp = null;
        _immobilityTimer?.cancel();
        _immobilityTimer = null;
        final stale = MotionTelemetry.stale();
        _lastMotion = stale;
        _motionController.add(stale);
        _broadcastHealth();
      }
    });
  }

  void _resetStalenessWatchdog() {
    _startStalenessWatchdog();
  }

  void _broadcastHealth() {
    _healthController.add(currentHealth);
  }
}

/// Fully deterministic in-memory mock for automated tests.
class MockSensorMonitoringService implements ISensorMonitoringService {
  final _motionController = StreamController<MotionTelemetry>.broadcast();
  final _batteryController = StreamController<BatteryTelemetry>.broadcast();
  final _transitController = StreamController<TransitTelemetry>.broadcast();
  final _healthController = StreamController<CompositeMonitoringHealth>.broadcast();

  bool _isActive = false;
  MotionTelemetry? _lastMotion;
  BatteryTelemetry? _lastBattery;
  TransitTelemetry? _lastTransit;

  @override
  Stream<MotionTelemetry> get motionStream => _motionController.stream;
  @override
  Stream<BatteryTelemetry> get batteryStream => _batteryController.stream;
  @override
  Stream<TransitTelemetry> get transitStream => _transitController.stream;
  @override
  Stream<CompositeMonitoringHealth> get healthStream => _healthController.stream;

  @override
  bool get isMonitoringActive => _isActive;
  @override
  MotionTelemetry? get lastMotion => _lastMotion;
  @override
  BatteryTelemetry? get lastBattery => _lastBattery;
  @override
  TransitTelemetry? get lastTransit => _lastTransit;

  @override
  CompositeMonitoringHealth get currentHealth {
    final status = !_isActive
        ? MonitoringLifecycleStatus.stopped
        : (_lastMotion?.readiness == SensorReadiness.valid
            ? MonitoringLifecycleStatus.active
            : MonitoringLifecycleStatus.degraded);

    return CompositeMonitoringHealth(
      status: status,
      isForegroundServiceRunning: _isActive,
      isBatteryOptimizationIgnored: true,
      motionHealth: _lastMotion?.readiness ?? SensorReadiness.unavailable,
      batteryHealth: _lastBattery?.readiness ?? SensorReadiness.unavailable,
      transitHealth: _lastTransit?.readiness ?? SensorReadiness.unavailable,
      locationHealth: SensorReadiness.valid,
      summaryText: status == MonitoringLifecycleStatus.active
          ? 'Mock sensors active & nominal'
          : 'Mock sensors stopped or degraded',
    );
  }

  @override
  Future<bool> initialize() async {
    _lastBattery = BatteryTelemetry.valid(level: 85, state: 'discharging');
    _lastTransit = TransitTelemetry.valid(type: 'stationary');
    return true;
  }

  @override
  Future<bool> startMonitoring() async {
    _isActive = true;
    _lastMotion = MotionTelemetry.fromRawAxes(x: 0, y: 0, z: 9.8);
    _motionController.add(_lastMotion!);
    _healthController.add(currentHealth);
    return true;
  }

  @override
  Future<void> stopMonitoring() async {
    _isActive = false;
    _healthController.add(currentHealth);
  }

  void emitMotion(MotionTelemetry motion) {
    _lastMotion = motion;
    _motionController.add(motion);
    _healthController.add(currentHealth);
  }

  void emitBattery(BatteryTelemetry battery) {
    _lastBattery = battery;
    _batteryController.add(battery);
  }

  void emitTransit(TransitTelemetry transit) {
    _lastTransit = transit;
    _transitController.add(transit);
  }

  void simulateStationaryPhone() {
    emitMotion(MotionTelemetry.fromRawAxes(x: 0.1, y: 0.0, z: 9.81));
  }

  void simulateWalking() {
    // Ordinary walking generates mild rhythmic acceleration ~ 1.2g - 1.4g
    emitMotion(MotionTelemetry.fromRawAxes(x: 1.2, y: 1.8, z: 12.0));
  }

  void simulateRoutineHandling() {
    // Picking up phone or turning in hand ~ 1.325g
    emitMotion(MotionTelemetry.fromRawAxes(x: 3.0, y: 4.0, z: 12.0));
  }

  void simulateImpact({double peakG = 3.2}) {
    final mag = peakG * 9.80665;
    emitMotion(
      MotionTelemetry.fromRawAxes(
        x: 1.0,
        y: 1.0,
        z: mag,
        peakImpactG: peakG,
      ),
    );
  }

  void simulateMovementSample({double gForce = 1.9}) {
    final mag = gForce * 9.80665;
    emitMotion(
      MotionTelemetry.fromRawAxes(
        x: 0.5,
        y: 0.5,
        z: mag,
      ),
    );
  }

  void simulateImpactAndImmobility({double peakG = 3.32, Duration immobility = const Duration(seconds: 5)}) {
    emitMotion(
      MotionTelemetry.candidateFall(
        x: 0.1,
        y: 0.1,
        z: 9.81,
        impactPeakG: peakG,
        impactTimestamp: DateTime.now().toUtc().subtract(immobility),
        immobilityDuration: immobility,
      ),
    );
  }

  void simulateRepeatedImpacts(List<double> peaks) {
    for (final p in peaks) {
      simulateImpact(peakG: p);
    }
  }

  void simulateStaleness() {
    emitMotion(MotionTelemetry.stale());
  }

  void simulateFailure([String reason = 'Sensor hardware error']) {
    emitMotion(MotionTelemetry.unavailable(reason));
  }
}
