import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

/// Contract for offline incident persistence and reconciliation.
abstract class ILocalIncidentStore {
  Future<void> enqueueIncident(Map<String, dynamic> incident);
  Future<List<Map<String, dynamic>>> getPendingIncidents();
  Future<List<Map<String, dynamic>>> getAllIncidents();
  Future<void> markIncidentSynced(String clientIncidentUuid, int serverIncidentId);
  Future<void> updateIncidentStatus(String clientIncidentUuid, String status);
  Future<void> clearIncidents();
}

/// SharedPreferences-backed offline incident persistence.
class LocalIncidentStore implements ILocalIncidentStore {
  final SharedPreferences? _prefs;

  LocalIncidentStore({SharedPreferences? prefs}) : _prefs = prefs;

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ?? await SharedPreferences.getInstance();
  }

  @override
  Future<void> enqueueIncident(Map<String, dynamic> incident) async {
    final prefs = await _getPrefs();
    final list = await getAllIncidents();

    // Prevent duplicate entries by client_incident_uuid
    final uuid = incident['client_incident_uuid'];
    final existingIndex = list.indexWhere((e) => e['client_incident_uuid'] == uuid);

    final updatedMap = Map<String, dynamic>.from(incident);
    updatedMap.putIfAbsent('status', () => AppConstants.statusQueuedOffline);
    updatedMap.putIfAbsent('created_at', () => DateTime.now().toUtc().toIso8601String());

    if (existingIndex >= 0) {
      list[existingIndex] = updatedMap;
    } else {
      list.insert(0, updatedMap);
    }

    final rawJsonList = list.map((item) => jsonEncode(item)).toList();
    await prefs.setStringList(AppConstants.keyOfflineIncidents, rawJsonList);
  }

  @override
  Future<List<Map<String, dynamic>>> getAllIncidents() async {
    final prefs = await _getPrefs();
    final rawList = prefs.getStringList(AppConstants.keyOfflineIncidents) ?? [];
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
  Future<List<Map<String, dynamic>>> getPendingIncidents() async {
    final all = await getAllIncidents();
    return all.where((e) => e['status'] == AppConstants.statusQueuedOffline).toList();
  }

  @override
  Future<void> markIncidentSynced(String clientIncidentUuid, int serverIncidentId) async {
    final prefs = await _getPrefs();
    final list = await getAllIncidents();

    for (var item in list) {
      if (item['client_incident_uuid'] == clientIncidentUuid) {
        item['status'] = AppConstants.statusSent;
        item['server_incident_id'] = serverIncidentId;
        item['synced_at'] = DateTime.now().toUtc().toIso8601String();
        break;
      }
    }

    final rawJsonList = list.map((item) => jsonEncode(item)).toList();
    await prefs.setStringList(AppConstants.keyOfflineIncidents, rawJsonList);
  }

  @override
  Future<void> updateIncidentStatus(String clientIncidentUuid, String status) async {
    final prefs = await _getPrefs();
    final list = await getAllIncidents();

    for (var item in list) {
      if (item['client_incident_uuid'] == clientIncidentUuid) {
        item['status'] = status;
        item['updated_at'] = DateTime.now().toUtc().toIso8601String();
        break;
      }
    }

    final rawJsonList = list.map((item) => jsonEncode(item)).toList();
    await prefs.setStringList(AppConstants.keyOfflineIncidents, rawJsonList);
  }

  @override
  Future<void> clearIncidents() async {
    final prefs = await _getPrefs();
    await prefs.remove(AppConstants.keyOfflineIncidents);
  }
}

/// In-memory implementation for unit testing without disk I/O.
class MockLocalIncidentStore implements ILocalIncidentStore {
  final List<Map<String, dynamic>> _storage = [];
  bool _shouldFail = false;

  void setSimulateFailure(bool fail) {
    _shouldFail = fail;
  }

  @override
  Future<void> enqueueIncident(Map<String, dynamic> incident) async {
    if (_shouldFail) {
      throw Exception('Simulated persistent storage disk write failure');
    }
    final uuid = incident['client_incident_uuid'];
    final existingIndex = _storage.indexWhere((e) => e['client_incident_uuid'] == uuid);

    final updated = Map<String, dynamic>.from(incident);
    updated.putIfAbsent('status', () => AppConstants.statusQueuedOffline);
    updated.putIfAbsent('created_at', () => DateTime.now().toUtc().toIso8601String());

    if (existingIndex >= 0) {
      _storage[existingIndex] = updated;
    } else {
      _storage.insert(0, updated);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getAllIncidents() async {
    return List.from(_storage);
  }

  @override
  Future<List<Map<String, dynamic>>> getPendingIncidents() async {
    return _storage.where((e) => e['status'] == AppConstants.statusQueuedOffline).toList();
  }

  @override
  Future<void> markIncidentSynced(String clientIncidentUuid, int serverIncidentId) async {
    for (var item in _storage) {
      if (item['client_incident_uuid'] == clientIncidentUuid) {
        item['status'] = AppConstants.statusSent;
        item['server_incident_id'] = serverIncidentId;
        item['synced_at'] = DateTime.now().toUtc().toIso8601String();
        break;
      }
    }
  }

  @override
  Future<void> updateIncidentStatus(String clientIncidentUuid, String status) async {
    for (var item in _storage) {
      if (item['client_incident_uuid'] == clientIncidentUuid) {
        item['status'] = status;
        item['updated_at'] = DateTime.now().toUtc().toIso8601String();
        break;
      }
    }
  }

  @override
  Future<void> clearIncidents() async {
    _storage.clear();
  }
}
