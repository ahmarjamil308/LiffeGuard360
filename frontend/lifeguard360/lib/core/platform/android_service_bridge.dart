import 'dart:io';
import 'package:flutter/services.dart';

/// Contract for native Android foreground service lifecycle and battery optimization bridges.
abstract class IAndroidServiceBridge {
  Future<bool> startForegroundService();
  Future<bool> stopForegroundService();
  Future<bool> isForegroundServiceRunning();
  Future<bool> isBatteryOptimizationIgnored();
  Future<bool> requestBatteryOptimizationExemption();
}

/// Production platform channel bridge to Android MainActivity.kt.
class AndroidServiceBridge implements IAndroidServiceBridge {
  static const MethodChannel _channel = MethodChannel('com.lifeguard360/monitoring');

  bool get isAndroid {
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> startForegroundService() async {
    if (!isAndroid) return true; // Graceful fallback on non-Android hosts/tests
    try {
      final result = await _channel.invokeMethod<bool>('startForegroundService');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> stopForegroundService() async {
    if (!isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('stopForegroundService');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isForegroundServiceRunning() async {
    if (!isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('isForegroundServiceRunning');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isBatteryOptimizationIgnored() async {
    if (!isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('isBatteryOptimizationIgnored');
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<bool> requestBatteryOptimizationExemption() async {
    if (!isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('requestBatteryOptimizationExemption');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Deterministic mock for unit and widget testing without native engine channel.
class MockAndroidServiceBridge implements IAndroidServiceBridge {
  bool _isRunning = false;
  bool _isBatteryIgnored = true;
  bool _requestedExemption = false;

  bool get isRunning => _isRunning;
  bool get requestedExemption => _requestedExemption;

  void setServiceRunning(bool running) => _isRunning = running;
  void setBatteryIgnored(bool ignored) => _isBatteryIgnored = ignored;
  void setBatteryOptimizationIgnored(bool ignored) => _isBatteryIgnored = ignored;

  @override
  Future<bool> startForegroundService() async {
    _isRunning = true;
    return true;
  }

  @override
  Future<bool> stopForegroundService() async {
    _isRunning = false;
    return true;
  }

  @override
  Future<bool> isForegroundServiceRunning() async => _isRunning;

  @override
  Future<bool> isBatteryOptimizationIgnored() async => _isBatteryIgnored;

  @override
  Future<bool> requestBatteryOptimizationExemption() async {
    _requestedExemption = true;
    _isBatteryIgnored = true;
    return true;
  }
}
