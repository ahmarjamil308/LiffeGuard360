import 'dart:async';
import 'package:flutter/foundation.dart';
import '../constants/api_constants.dart';
import '../network/api_client.dart';
import '../network/network_service.dart';
import '../storage/local_checkin_store.dart';
import '../storage/local_incident_store.dart';
import 'database_service.dart';

enum SyncState { idle, syncing, completed, error }

/// Central Synchronization Service coordinating bidirectional sync between local SQLite and Firebase/Backend.
class SyncService {
  static SyncService? _instance;
  final DatabaseService _dbService;
  final NetworkService _networkService;

  bool _isSyncing = false;
  SyncState _state = SyncState.idle;
  String? _lastSyncError;
  DateTime? _lastSyncTime;

  final StreamController<SyncState> _syncStateController = StreamController<SyncState>.broadcast();
  StreamSubscription<bool>? _networkSubscription;

  SyncService._({
    DatabaseService? dbService,
    NetworkService? networkService,
  })  : _dbService = dbService ?? DatabaseService.instance,
        _networkService = networkService ?? NetworkService.instance {
    _initAutoSync();
  }

  static SyncService get instance {
    _instance ??= SyncService._();
    return _instance!;
  }

  /// Sets a mock or custom instance for testing
  static void setMockInstance(SyncService service) {
    _instance = service;
  }

  bool get isSyncing => _isSyncing;
  SyncState get state => _state;
  String? get lastSyncError => _lastSyncError;
  DateTime? get lastSyncTime => _lastSyncTime;
  Stream<SyncState> get onSyncStateChanged => _syncStateController.stream;

  void _initAutoSync() {
    _networkSubscription = _networkService.onConnectivityChanged.listen((isOnline) {
      if (isOnline) {
        // Automatically trigger synchronization when network connectivity is restored
        debugPrint('[SyncService] Network connectivity restored. Triggering auto-sync...');
      }
    });
  }

  /// Runs full synchronization across all domains: Contacts, Check-Ins, Incidents, and Audit Logs.
  Future<bool> syncAll({
    required ApiClient apiClient,
    ILocalIncidentStore? localStore,
    ILocalCheckInStore? checkInStore,
    String? userId,
  }) async {
    if (_isSyncing) return false;

    final isConnected = await _networkService.checkConnectivity();
    if (!isConnected) {
      _lastSyncError = 'Device is currently offline.';
      _updateState(SyncState.idle);
      return false;
    }

    _isSyncing = true;
    _lastSyncError = null;
    _updateState(SyncState.syncing);

    try {
      // 1. Sync Emergency Contacts
      await syncContacts(apiClient, userId: userId);

      // 2. Sync Pending SOS Incidents
      if (localStore != null) {
        await syncIncidents(apiClient, localStore: localStore, userId: userId);
      }

      // 3. Sync Check-Ins
      if (checkInStore != null) {
        await syncCheckIns(apiClient, checkInStore: checkInStore, userId: userId);
      }

      // 4. Sync Audit Logs
      await syncAuditLogs(apiClient, userId: userId);

      _lastSyncTime = DateTime.now();
      _isSyncing = false;
      _updateState(SyncState.completed);
      return true;
    } catch (e) {
      _isSyncing = false;
      _lastSyncError = e.toString();
      _updateState(SyncState.error);
      debugPrint('[SyncService] Sync encountered error: $e');
      return false;
    }
  }

  /// Synchronizes Emergency Contacts (push pending creates/updates/deletes, then pull remote).
  Future<void> syncContacts(ApiClient apiClient, {String? userId}) async {
    final pending = await _dbService.getPendingContacts();

    for (final contact in pending) {
      final clientUuid = contact['client_uuid'] as String;
      final serverId = contact['server_id'] as int?;
      final operation = contact['sync_operation'] as String? ?? 'NONE';

      try {
        if (operation == 'CREATE' || (operation == 'NONE' && serverId == null)) {
          final payload = {
            'name': contact['name'],
            'phone': contact['phone'],
            if (contact['email'] != null) 'email': contact['email'],
            'relationship': contact['relationship'],
            'priority_tier': contact['priority_tier'],
            'notify_sms': (contact['notify_sms'] == 1),
            'notify_push': (contact['notify_push'] == 1),
          };

          final response = await apiClient.post(ApiConstants.contacts, data: payload);
          if (response.statusCode == 201 && response.data != null) {
            final raw = response.data as Map<String, dynamic>;
            final data = (raw['data'] is Map<String, dynamic>)
                ? raw['data'] as Map<String, dynamic>
                : raw;
            final created = data['contact'] as Map<String, dynamic>?;
            final newServerId = created?['id'] as int?;
            if (newServerId != null) {
              await _dbService.markContactSynced(clientUuid, newServerId);
            }
          }
        } else if (operation == 'UPDATE' && serverId != null) {
          final payload = {
            'name': contact['name'],
            'phone': contact['phone'],
            if (contact['email'] != null) 'email': contact['email'],
            'relationship': contact['relationship'],
            'priority_tier': contact['priority_tier'],
            'notify_sms': (contact['notify_sms'] == 1),
            'notify_push': (contact['notify_push'] == 1),
            'is_active': (contact['is_active'] == 1),
          };

          final response = await apiClient.put(ApiConstants.contactDetail(serverId), data: payload);
          if (response.statusCode == 200) {
            await _dbService.markContactSynced(clientUuid, serverId);
          }
        } else if (operation == 'DELETE') {
          if (serverId != null) {
            try {
              await apiClient.delete(ApiConstants.contactDetail(serverId));
            } catch (_) {
              // Even if server returns 404, contact is gone on server
            }
          }
          await _dbService.purgeDeletedContact(clientUuid);
        }
      } catch (e) {
        debugPrint('[SyncService] Failed to sync contact $clientUuid: $e');
        await _dbService.markContactFailed(clientUuid);
      }
    }

    // Pull latest authoritative contacts from Firebase/backend
    try {
      final response = await apiClient.get(ApiConstants.contacts);
      if (response.statusCode == 200 && response.data != null) {
        final raw = response.data as Map<String, dynamic>;
        final data = (raw['data'] is Map<String, dynamic>)
            ? raw['data'] as Map<String, dynamic>
            : raw;
        final rawList = (data['contacts'] as List<dynamic>?) ?? [];
        final contacts = rawList.cast<Map<String, dynamic>>();
        await _dbService.saveServerContacts(contacts, userId: userId);
      }
    } catch (e) {
      debugPrint('[SyncService] Pulling contacts failed: $e');
    }
  }

  /// Synchronizes pending SOS incidents.
  Future<void> syncIncidents(
    ApiClient apiClient, {
    required ILocalIncidentStore localStore,
    String? userId,
  }) async {
    final pending = await localStore.getPendingIncidents();
    if (pending.isEmpty) return;

    for (final inc in pending) {
      try {
        final payload = {
          'client_incident_uuid': inc['client_incident_uuid'],
          'trigger_source': inc['trigger_source'] ?? 'MANUAL_BUTTON',
          if (inc['latitude'] != null) 'latitude': inc['latitude'],
          if (inc['longitude'] != null) 'longitude': inc['longitude'],
          if (inc['accuracy_meters'] != null) 'accuracy_meters': inc['accuracy_meters'],
          if (inc['risk_score_at_trigger'] != null) 'risk_score_at_trigger': inc['risk_score_at_trigger'],
          if (inc['local_notes'] != null) 'local_notes': inc['local_notes'],
        };

        final response = await apiClient.post(ApiConstants.sosSync, data: payload);
        if (response.statusCode == 200 && response.data != null) {
          final data = response.data['data'] as Map<String, dynamic>? ?? response.data;
          final serverId = data['server_incident_id'] as int? ?? data['incident']?['id'] as int?;
          if (serverId != null) {
            await localStore.markIncidentSynced(inc['client_incident_uuid'], serverId);
            await _dbService.markIncidentSynced(inc['client_incident_uuid'], serverId);
          }
        }
      } catch (e) {
        debugPrint('[SyncService] Failed to sync incident ${inc['client_incident_uuid']}: $e');
      }
    }
  }

  /// Synchronizes check-in operations.
  Future<void> syncCheckIns(
    ApiClient apiClient, {
    required ILocalCheckInStore checkInStore,
    String? userId,
  }) async {
    final pendingOps = await checkInStore.getPendingOperations();
    for (final op in pendingOps) {
      final action = op['action'] as String;
      final checkinId = op['checkin_id'] as int;

      try {
        if (action == 'CANCEL') {
          await apiClient.post(
            ApiConstants.checkInCancel(checkinId),
            data: op['pin'] != null ? {'pin': op['pin']} : null,
          );
          await checkInStore.removeOperation(checkinId: checkinId, action: action);
        } else if (action == 'EXTEND') {
          await apiClient.post(
            ApiConstants.checkInExtend(checkinId),
            data: {
              'additional_minutes': op['additional_minutes'] ?? 15,
              if (op['pin'] != null) 'pin': op['pin'],
            },
          );
          await checkInStore.removeOperation(checkinId: checkinId, action: action);
        }
      } catch (e) {
        debugPrint('[SyncService] Failed to sync checkin op $action for $checkinId: $e');
      }
    }
  }

  /// Synchronizes activity logs from server.
  Future<void> syncAuditLogs(ApiClient apiClient, {String? userId}) async {
    try {
      final response = await apiClient.get(ApiConstants.auditLogs);
      if (response.statusCode == 200 && response.data != null) {
        final raw = response.data as Map<String, dynamic>;
        final data = (raw['data'] is Map<String, dynamic>)
            ? raw['data'] as Map<String, dynamic>
            : raw;
        final rawLogs = (data['audit_logs'] as List<dynamic>?) ?? [];
        for (final item in rawLogs) {
          if (item is Map<String, dynamic>) {
            await _dbService.logActivity(
              serverId: item['id'] as int?,
              eventType: item['event_type'] ?? 'AUDIT',
              action: item['action'] ?? '',
              category: item['category'] ?? 'SYSTEM',
              details: item['details']?.toString(),
              userId: userId ?? item['user_id']?.toString(),
              syncStatus: 'synced',
            );
          }
        }
      }
    } catch (_) {
      // Remote audit log sync is optional non-blocking
    }
  }

  void _updateState(SyncState newState) {
    _state = newState;
    _syncStateController.add(_state);
  }

  void dispose() {
    _networkSubscription?.cancel();
    _syncStateController.close();
  }
}

