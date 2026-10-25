import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// LifeGuard 360 API Endpoints and Network Configuration.
class ApiConstants {
  ApiConstants._();

  /// Default API base URL:
  /// - Automatically connects to 127.0.0.1 for Web (Chrome) & Desktop
  /// - Automatically connects to 10.0.2.2 for Android Emulator
  static String get defaultBaseUrl {
    if (kIsWeb) {
      return 'http://127.0.0.1:5000/api/v1';
    }
    try {
      if (Platform.isAndroid) {
        return 'http://10.0.2.2:5000/api/v1';
      }
    } catch (_) {}
    return 'http://127.0.0.1:5000/api/v1';
  }

  /// Active base URL that can be dynamically updated in runtime/settings.
  static String baseUrl = defaultBaseUrl;

  /// Timeouts
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);
  static const Duration sendTimeout = Duration(seconds: 10);

  // Auth endpoints
  static const String authRegister = '/auth/register';
  static const String authLogin = '/auth/login';
  static const String authMe = '/auth/me';

  // Contact endpoints
  static const String contacts = '/contacts';
  static String contactDetail(int id) => '/contacts/$id';

  // Check-In endpoints
  static const String checkIn = '/checkin';
  static const String checkInSchedule = '/checkin/schedule';
  static const String checkInActive = '/checkin/active';
  static String checkInConfirm(int id) => '/checkin/confirm/$id';
  static String checkInCancel(int id) => '/checkin/cancel/$id';
  static String checkInExtend(int id) => '/checkin/extend/$id';
  static String checkInRecoverLockout(int id) => '/checkin/recover-lockout/$id';
  static const String checkInRespond = '/checkin/respond';
  static const String checkInHistory = '/checkin/history';

  // SOS & Emergency endpoints
  static const String sosTrigger = '/sos/trigger';
  static const String sosSync = '/sos/sync';
  static const String sosCancel = '/sos/cancel';
  static String incidentDetail(int id) => '/sos/incident/$id';
  static String retryDispatch(int id) => '/sos/dispatch/$id/retry';

  // Risk endpoints
  static const String riskScore = '/risk/score';
  static const String riskFactors = '/risk/factors';
  static const String sensorTelemetry = '/risk/telemetry';

  // Audit Logs
  static const String auditLogs = '/logs/audit';
}
