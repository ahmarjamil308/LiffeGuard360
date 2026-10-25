import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

/// Contract for persisting offline check-in operations (cancellation, extension)
/// so that offline requests are never lost and are synchronized idempotently upon reconnection.
abstract class ILocalCheckInStore {
  Future<void> enqueueOperation({
    required String action, // 'CANCEL' or 'EXTEND'
    required int checkinId,
    String? pin,
    int? additionalMinutes,
  });
  Future<List<Map<String, dynamic>>> getPendingOperations();
  Future<void> removeOperation({required int checkinId, required String action});
  Future<void> clearOperations();
}

/// SharedPreferences-backed persistence for offline check-in requests.
class LocalCheckInStore implements ILocalCheckInStore {
  final SharedPreferences? _prefs;

  LocalCheckInStore({SharedPreferences? prefs}) : _prefs = prefs;

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ?? await SharedPreferences.getInstance();
  }

  @override
  Future<void> enqueueOperation({
    required String action,
    required int checkinId,
    String? pin,
    int? additionalMinutes,
  }) async {
    final prefs = await _getPrefs();
    final list = await getPendingOperations();

    // Deduplicate: replace existing pending op for same checkinId and action
    list.removeWhere((item) => item['checkin_id'] == checkinId && item['action'] == action);

    final op = {
      'action': action,
      'checkin_id': checkinId,
      'pin': ?pin,
      'additional_minutes': ?additionalMinutes,
      'enqueued_at': DateTime.now().toUtc().toIso8601String(),
    };

    list.add(op);
    final rawList = list.map((e) => jsonEncode(e)).toList();
    await prefs.setStringList(AppConstants.keyPendingCheckInOps, rawList);
  }

  @override
  Future<List<Map<String, dynamic>>> getPendingOperations() async {
    final prefs = await _getPrefs();
    final rawList = prefs.getStringList(AppConstants.keyPendingCheckInOps) ?? [];
    return rawList
        .map((str) {
          try {
            return jsonDecode(str) as Map<String, dynamic>;
          } catch (_) {
            return <String, dynamic>{};
          }
        })
        .where((m) => m.isNotEmpty)
        .toList();
  }

  @override
  Future<void> removeOperation({required int checkinId, required String action}) async {
    final prefs = await _getPrefs();
    final list = await getPendingOperations();
    list.removeWhere((item) => item['checkin_id'] == checkinId && item['action'] == action);
    final rawList = list.map((e) => jsonEncode(e)).toList();
    await prefs.setStringList(AppConstants.keyPendingCheckInOps, rawList);
  }

  @override
  Future<void> clearOperations() async {
    final prefs = await _getPrefs();
    await prefs.remove(AppConstants.keyPendingCheckInOps);
  }
}
