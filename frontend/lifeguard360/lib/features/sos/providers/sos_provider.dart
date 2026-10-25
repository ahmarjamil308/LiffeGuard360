import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/location/location_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/local_incident_store.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../models/incident_model.dart';

/// Provider managing emergency SOS distress lifecycle, offline resilience, and outbox synchronization.
class SOSProvider extends ChangeNotifier {
  final ApiClient _apiClient;
  final ILocalIncidentStore _localStore;
  final ISecureStorage _secureStorage;
  final ILocationService? _locationService;
  final Uuid _uuid = const Uuid();

  IncidentModel? _activeIncident;
  List<IncidentModel> _queuedIncidents = [];
  bool _isAlarmActive = false;
  bool _isSyncing = false;
  String? _lastError;

  SOSProvider({
    required ApiClient apiClient,
    required ILocalIncidentStore localStore,
    required ISecureStorage secureStorage,
    ILocationService? locationService,
  })  : _apiClient = apiClient,
        _localStore = localStore,
        _secureStorage = secureStorage,
        _locationService = locationService;

  ISecureStorage get secureStorage => _secureStorage;
  ILocationService? get locationService => _locationService;
  IncidentModel? get activeIncident => _activeIncident;
  set activeIncident(IncidentModel? val) {
    _activeIncident = val;
    notifyListeners();
  }
  List<IncidentModel> get queuedIncidents => _queuedIncidents;
  bool get isAlarmActive => _isAlarmActive;
  bool get isSyncing => _isSyncing;
  String? get lastError => _lastError;
  bool get hasActiveEmergency => _activeIncident != null && _activeIncident!.status == AppConstants.incidentActive;

  bool _isPersistedLocally = false;
  String? _storageError;

  bool get isPersistedLocally => _isPersistedLocally;
  String? get storageError => _storageError;

  void toggleAlarm() {
    _isAlarmActive = !_isAlarmActive;
    notifyListeners();
  }

  void silenceAlarm() {
    _isAlarmActive = false;
    notifyListeners();
  }

  /// Initialize local store and load pending offline incidents
  Future<void> loadQueuedIncidents() async {
    try {
      final rawList = await _localStore.getAllIncidents();
      _queuedIncidents = rawList.map((m) => IncidentModel.fromJson(m)).toList();
      notifyListeners();
    } catch (_) {}
  }

  /// Manually retry persisting active incident to local disk
  Future<bool> retryLocalPersistence() async {
    if (_activeIncident == null) return false;
    try {
      await _localStore.enqueueIncident(_activeIncident!.toJson());
      _isPersistedLocally = true;
      _storageError = null;
      await loadQueuedIncidents();
      notifyListeners();
      return true;
    } catch (e) {
      _isPersistedLocally = false;
      _storageError = 'Durable local storage failed: $e. Incident active in memory only.';
      notifyListeners();
      return false;
    }
  }

  /// Trigger Manual Emergency SOS.
  /// SAFETY CRITICAL: Executed immediately without artificial countdowns or pre-risk delays.
  Future<IncidentModel> triggerManualSOS({
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    String? localNotes,
  }) async {
    _lastError = null;
    _storageError = null;
    _isPersistedLocally = false;
    final clientUuid = _uuid.v4();
    final now = DateTime.now().toUtc();

    // 1. Synchronous instantaneous location check:
    // If explicit coordinates not passed, inspect lastKnownLocation without ANY blocking delay.
    final locService = _locationService;
    double? lat = latitude ?? locService?.lastKnownLocation?.latitude;
    double? lng = longitude ?? locService?.lastKnownLocation?.longitude;
    double? acc = accuracyMeters ?? locService?.lastKnownLocation?.accuracyMeters;

    // 2. Local-first immediate distress state (t = 0 ms invariant)
    // NEVER wait for GPS, sensors, network, or risk scoring before activating alarm & persisting!
    final localIncident = IncidentModel(
      clientIncidentUuid: clientUuid,
      triggerSource: 'MANUAL_BUTTON',
      status: AppConstants.statusQueuedOffline,
      latitude: lat,
      longitude: lng,
      accuracyMeters: acc,
      localNotes: localNotes,
      createdAt: now,
    );

    _activeIncident = localIncident;
    _isAlarmActive = true;
    notifyListeners(); // UI updates immediately at t = 0 ms!

    // 3. Persist locally to survive app crash or power cutoff
    try {
      await _localStore.enqueueIncident(localIncident.toJson());
      _isPersistedLocally = true;
      _storageError = null;
      await loadQueuedIncidents();
    } catch (e) {
      _isPersistedLocally = false;
      _storageError = 'Durable local storage failed: $e. Incident active in memory only.';
    }
    notifyListeners();

    // 4. Non-blocking fresh GPS lookup for backend dispatch payload (if coordinates were absent)
    if (lat == null && locService != null) {
      try {
        final loc = await locService.getCurrentLocation(timeout: const Duration(seconds: 2));
        if (loc != null && loc.hasValidFix) {
          lat = loc.latitude;
          lng = loc.longitude;
          acc = loc.accuracyMeters;
          // Guard: Only enrich if active incident clientIncidentUuid still matches this incident
          if (_activeIncident?.clientIncidentUuid == clientUuid) {
            _activeIncident = _activeIncident?.copyWith(
              latitude: lat,
              longitude: lng,
              accuracyMeters: acc,
            );
            if (_isPersistedLocally) {
              await _localStore.enqueueIncident(_activeIncident!.toJson());
            }
          }
        }
      } catch (_) {
        // Fallback: Dispatch proceeds immediately with null location
      }
    }

    // 5. Attempt immediate dispatch to backend
    try {
      final payload = {
        'client_incident_uuid': clientUuid,
        'trigger_source': 'MANUAL_BUTTON',
        'latitude': lat,
        'longitude': lng,
        'accuracy_meters': acc,
        'local_notes': localNotes,
      };

      final response = await _apiClient.post(
        ApiConstants.sosTrigger,
        data: payload,
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final raw = response.data as Map<String, dynamic>;
        final data = (raw['data'] is Map<String, dynamic>)
            ? raw['data'] as Map<String, dynamic>
            : raw;
        final incidentData = (data['incident'] is Map<String, dynamic>)
            ? data['incident'] as Map<String, dynamic>
            : data;
        final serverIncidentId = incidentData['id'] as int? ?? 0;

        if (_isPersistedLocally) {
          await _localStore.markIncidentSynced(clientUuid, serverIncidentId);
        }
        if (_activeIncident?.clientIncidentUuid == clientUuid) {
          _activeIncident = IncidentModel.fromJson(incidentData);
        }
        await loadQueuedIncidents();
      }
    } catch (e) {
      // Network failure: incident safely remains QUEUED_OFFLINE
      _lastError = 'Offline mode: Incident saved locally. Dispatch will sync automatically.';
    }

    notifyListeners();
    return _activeIncident!;
  }

  /// Refresh active incident status and latest carrier dispatches from backend
  Future<void> fetchIncidentDetails(int incidentId) async {
    try {
      final response = await _apiClient.get(ApiConstants.incidentDetail(incidentId));
      if (response.statusCode == 200 && response.data != null) {
        final raw = response.data as Map<String, dynamic>;
        final data = (raw['data'] is Map<String, dynamic>)
            ? raw['data'] as Map<String, dynamic>
            : raw;
        final incidentData = (data['incident'] is Map<String, dynamic>)
            ? data['incident'] as Map<String, dynamic>
            : data;
        _activeIncident = IncidentModel.fromJson(incidentData);
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Synchronize all offline incidents queued during connectivity loss
  Future<void> syncPendingIncidents() async {
    final pending = await _localStore.getPendingIncidents();
    if (pending.isEmpty) return;

    _isSyncing = true;
    notifyListeners();

    try {
      final response = await _apiClient.post(
        ApiConstants.sosSync,
        data: {'incidents': pending},
      );

      if (response.statusCode == 200 && response.data != null) {
        final raw = response.data as Map<String, dynamic>;
        final data = (raw['data'] is Map<String, dynamic>)
            ? raw['data'] as Map<String, dynamic>
            : raw;
        final syncedList = ((data['synced'] ?? data['synced_incidents']) as List<dynamic>?) ?? [];
        for (var item in syncedList) {
          if (item is Map<String, dynamic>) {
            final uuid = item['client_incident_uuid'] as String?;
            final id = item['server_incident_id'] as int? ?? item['id'] as int?;
            if (uuid != null && id != null) {
              await _localStore.markIncidentSynced(uuid, id);
            }
          }
        }
      }
    } catch (e) {
      _lastError = 'Sync failed. Will retry on next connection: ${e.toString()}';
    } finally {
      _isSyncing = false;
      await loadQueuedIncidents();
      notifyListeners();
    }
  }

  /// Cancel an active incident with PIN verification
  Future<bool> cancelIncident({
    required int incidentId,
    required String pin,
    String? reason,
  }) async {
    try {
      final response = await _apiClient.post(
        ApiConstants.sosCancel,
        data: {
          'incident_id': incidentId,
          'pin': pin,
          'reason': reason ?? 'Resolved by user',
        },
      );

      if (response.statusCode == 200) {
        _isAlarmActive = false;
        if (_activeIncident?.id == incidentId) {
          _activeIncident = _activeIncident?.copyWith(
            status: AppConstants.incidentCancelled,
            resolvedAt: DateTime.now().toUtc(),
          );
        }
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _lastError = 'Failed to cancel incident: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }
}
