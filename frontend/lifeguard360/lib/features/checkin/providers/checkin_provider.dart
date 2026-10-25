import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/local_checkin_store.dart';
import '../models/checkin_model.dart';

/// Provider orchestrating Smart Check-In lifecycle, countdown ticker, and PIN verification.
class CheckInProvider extends ChangeNotifier {
  final ApiClient _apiClient;
  final ILocalCheckInStore _checkInStore;

  CheckInModel? _activeCheckIn;
  List<CheckInModel> _history = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _statusMessage;
  bool _isCancellationPendingSync = false;
  bool _isExtensionPendingSync = false;
  Timer? _tickerTimer;

  CheckInProvider({
    required ApiClient apiClient,
    ILocalCheckInStore? checkInStore,
  })  : _apiClient = apiClient,
        _checkInStore = checkInStore ?? LocalCheckInStore() {
    _startTicker();
    checkPendingOperations();
  }

  CheckInModel? get activeCheckIn => _activeCheckIn;
  set activeCheckIn(CheckInModel? val) {
    _activeCheckIn = val;
    notifyListeners();
  }
  List<CheckInModel> get history => _history;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get statusMessage => _statusMessage;
  bool get isCancellationPendingSync => _isCancellationPendingSync;
  bool get isExtensionPendingSync => _isExtensionPendingSync;
  bool get hasActiveCheckIn =>
      _activeCheckIn != null &&
      !_activeCheckIn!.isSafeCompleted &&
      !_activeCheckIn!.isCancelled;

  void _startTicker() {
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_activeCheckIn != null && hasActiveCheckIn) {
        final evaluated = _activeCheckIn!.evaluateState();
        if (evaluated != _activeCheckIn!.status) {
          _activeCheckIn = _activeCheckIn!.copyWith(status: evaluated);
        }
        notifyListeners();
      }
    });
  }

  /// Fetches active scheduled check-in from backend
  Future<void> loadActiveCheckIn() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiClient.get(ApiConstants.checkInActive);
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data['data'] as Map<String, dynamic>? ?? response.data;
        if (data['has_active'] == true && data['checkin'] != null) {
          _activeCheckIn = CheckInModel.fromJson(data['checkin'] as Map<String, dynamic>);
        } else {
          _activeCheckIn = null;
        }
      }
    } catch (e) {
      _errorMessage = 'Failed to load active check-in: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Schedules a new Smart Check-In
  Future<bool> scheduleCheckIn({
    required String title,
    required DateTime scheduledFor,
    int gracePeriodMinutes = 10,
    int preAlertSeconds = 20,
    String? destinationNote,
    String? pin,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    _statusMessage = null;
    notifyListeners();

    try {
      final payload = {
        'title': title,
        'scheduled_for': scheduledFor.toUtc().toIso8601String(),
        'grace_period_minutes': gracePeriodMinutes,
        'pre_alert_seconds': preAlertSeconds,
        if (destinationNote != null && destinationNote.isNotEmpty) 'destination_note': destinationNote,
        if (pin != null && pin.isNotEmpty) 'safety_pin': pin,
      };

      final response = await _apiClient.post(
        ApiConstants.checkInSchedule,
        data: payload,
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = response.data['data'] as Map<String, dynamic>? ?? response.data;
        final checkinData = data['checkin'] as Map<String, dynamic>? ?? data;
        _activeCheckIn = CheckInModel.fromJson(checkinData);
        _statusMessage = 'Check-in scheduled successfully.';
        notifyListeners();
        return true;
      }
    } catch (e) {
      _errorMessage = 'Failed to schedule check-in: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  /// Confirms that user is SAFE (with PIN challenge if configured)
  Future<bool> confirmSafe({String? pin}) async {
    if (_activeCheckIn == null || _activeCheckIn!.id == null) return false;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final payload = <String, dynamic>{};
      if (pin != null && pin.isNotEmpty) {
        payload['safety_pin'] = pin;
      }

      final response = await _apiClient.post(
        ApiConstants.checkInConfirm(_activeCheckIn!.id!),
        data: payload,
      );

      if (response.statusCode == 200) {
        final data = response.data['data'] as Map<String, dynamic>? ?? response.data;
        final checkinData = data['checkin'] as Map<String, dynamic>? ?? data;
        _activeCheckIn = CheckInModel.fromJson(checkinData);
        _statusMessage = 'Check-in confirmed: You are marked SAFE.';
        notifyListeners();
        return true;
      }
    } catch (e) {
      _errorMessage = 'Incorrect PIN or confirmation failed: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  /// Checks whether local offline operations exist in the persistent store
  Future<void> checkPendingOperations() async {
    try {
      final ops = await _checkInStore.getPendingOperations();
      if (_activeCheckIn != null && _activeCheckIn!.id != null) {
        _isCancellationPendingSync = ops.any(
          (op) => op['checkin_id'] == _activeCheckIn!.id && op['action'] == 'CANCEL',
        );
        _isExtensionPendingSync = ops.any(
          (op) => op['checkin_id'] == _activeCheckIn!.id && op['action'] == 'EXTEND',
        );
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Cancels an active scheduled check-in on the backend with PIN authentication.
  /// TRUTHFUL OFFLINE BEHAVIOR:
  /// If offline, the cancellation is queued in LocalCheckInStore and marked pending sync.
  /// The local UI DOES NOT claim the check-in is cancelled on the server, and explicitly
  /// warns the user that server monitoring continues until connectivity is restored.
  Future<bool> cancelActiveCheckIn({String? pin, String? reason}) async {
    if (_activeCheckIn == null || _activeCheckIn!.id == null) return false;

    // If check-in has PIN challenge configured, require PIN to prevent accidental cancellation
    if (_activeCheckIn!.hasPin && (pin == null || pin.isEmpty)) {
      _errorMessage = 'PIN required to cancel this scheduled check-in.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final payload = <String, dynamic>{};
      if (pin != null && pin.isNotEmpty) {
        payload['safety_pin'] = pin;
      }

      final response = await _apiClient.post(
        ApiConstants.checkInCancel(_activeCheckIn!.id!),
        data: payload,
      );

      if (response.statusCode == 200) {
        await _checkInStore.removeOperation(checkinId: _activeCheckIn!.id!, action: 'CANCEL');
        _isCancellationPendingSync = false;
        final data = response.data['data'] as Map<String, dynamic>? ?? response.data;
        final checkinData = data['checkin'] as Map<String, dynamic>? ?? data;
        _activeCheckIn = CheckInModel.fromJson(checkinData);
        _statusMessage = 'Scheduled check-in cancelled.';
        notifyListeners();
        return true;
      }
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      // If server returned a business rejection (e.g. already escalated to emergency incident)
      if (errStr.contains('already escalated') || errStr.contains('emergency incident')) {
        _errorMessage = 'Cannot cancel check-in: Server has already escalated to an emergency incident. Please cancel via the SOS screen.';
        _isCancellationPendingSync = false;
        await _checkInStore.removeOperation(checkinId: _activeCheckIn!.id!, action: 'CANCEL');
        _activeCheckIn = _activeCheckIn!.copyWith(status: 'OVERDUE_ESCALATED');
        notifyListeners();
        return false;
      }

      if (errStr.contains('incorrect safety pin') || errStr.contains('locked for security')) {
        _errorMessage = e.toString();
        notifyListeners();
        return false;
      }

      // True offline / network failure: enqueue persistently without claiming server-side confirmation
      await _checkInStore.enqueueOperation(
        action: 'CANCEL',
        checkinId: _activeCheckIn!.id!,
        pin: pin,
      );
      _isCancellationPendingSync = true;
      _statusMessage = 'Cancellation queued locally. Device is OFFLINE. WARNING: LifeGuard 360 server continues monitoring and will escalate if connection is not restored before deadline.';
      notifyListeners();
      return true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  /// Extends active check-in scheduled time before or during grace period
  Future<bool> extendActiveCheckIn({required int additionalMinutes, String? pin}) async {
    if (_activeCheckIn == null || _activeCheckIn!.id == null) return false;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final payload = <String, dynamic>{
        'additional_minutes': additionalMinutes,
        if (pin != null && pin.isNotEmpty) 'safety_pin': pin,
      };

      final response = await _apiClient.post(
        ApiConstants.checkInExtend(_activeCheckIn!.id!),
        data: payload,
      );

      if (response.statusCode == 200) {
        await _checkInStore.removeOperation(checkinId: _activeCheckIn!.id!, action: 'EXTEND');
        _isExtensionPendingSync = false;
        final data = response.data['data'] as Map<String, dynamic>? ?? response.data;
        final checkinData = data['checkin'] as Map<String, dynamic>? ?? data;
        _activeCheckIn = CheckInModel.fromJson(checkinData);
        _statusMessage = 'Check-in extended by $additionalMinutes minutes.';
        notifyListeners();
        return true;
      }
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('already escalated')) {
        _errorMessage = 'Cannot extend check-in: It has already escalated to an emergency incident.';
        _isExtensionPendingSync = false;
        await _checkInStore.removeOperation(checkinId: _activeCheckIn!.id!, action: 'EXTEND');
        notifyListeners();
        return false;
      }

      // Offline fallback: enqueue persistently
      await _checkInStore.enqueueOperation(
        action: 'EXTEND',
        checkinId: _activeCheckIn!.id!,
        pin: pin,
        additionalMinutes: additionalMinutes,
      );
      _isExtensionPendingSync = true;
      _statusMessage = 'Extension queued locally. Reconnect to sync with server.';
      notifyListeners();
      return true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  /// Synchronizes any locally queued check-in operations once network is restored
  Future<void> syncPendingCheckInOperations() async {
    final pending = await _checkInStore.getPendingOperations();
    if (pending.isEmpty) return;

    for (final op in pending) {
      final action = op['action'] as String?;
      final checkinId = op['checkin_id'] as int?;
      final pin = op['pin'] as String?;
      final additionalMinutes = op['additional_minutes'] as int?;

      if (checkinId == null) continue;

      try {
        if (action == 'CANCEL') {
          final payload = <String, dynamic>{'safety_pin': ?pin};
          final res = await _apiClient.post(ApiConstants.checkInCancel(checkinId), data: payload);
          if (res.statusCode == 200) {
            await _checkInStore.removeOperation(checkinId: checkinId, action: 'CANCEL');
            _isCancellationPendingSync = false;
            final data = res.data['data'] as Map<String, dynamic>? ?? res.data;
            if (data['checkin'] != null) {
              _activeCheckIn = CheckInModel.fromJson(data['checkin'] as Map<String, dynamic>);
            }
            _statusMessage = 'Offline cancellation synchronized with server.';
          }
        } else if (action == 'EXTEND' && additionalMinutes != null) {
          final payload = <String, dynamic>{
            'additional_minutes': additionalMinutes,
            'safety_pin': ?pin,
          };
          final res = await _apiClient.post(ApiConstants.checkInExtend(checkinId), data: payload);
          if (res.statusCode == 200) {
            await _checkInStore.removeOperation(checkinId: checkinId, action: 'EXTEND');
            _isExtensionPendingSync = false;
            final data = res.data['data'] as Map<String, dynamic>? ?? res.data;
            if (data['checkin'] != null) {
              _activeCheckIn = CheckInModel.fromJson(data['checkin'] as Map<String, dynamic>);
            }
            _statusMessage = 'Offline extension synchronized with server.';
          }
        }
      } catch (e) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('already escalated')) {
          await _checkInStore.removeOperation(checkinId: checkinId, action: action ?? '');
          _isCancellationPendingSync = false;
          _isExtensionPendingSync = false;
          _errorMessage = 'Sync result: Check-in already escalated to emergency incident on server.';
          _activeCheckIn = _activeCheckIn?.copyWith(status: 'OVERDUE_ESCALATED');
        }
      }
    }
    notifyListeners();
  }

  /// Recovers a locked-out check-in using the user's primary account password
  Future<bool> recoverLockoutWithPassword(String accountPassword) async {
    if (_activeCheckIn == null || _activeCheckIn!.id == null) return false;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiClient.post(
        ApiConstants.checkInRecoverLockout(_activeCheckIn!.id!),
        data: {'account_password': accountPassword},
      );

      if (response.statusCode == 200) {
        final data = response.data['data'] as Map<String, dynamic>? ?? response.data;
        final checkinData = data['checkin'] as Map<String, dynamic>? ?? data;
        _activeCheckIn = CheckInModel.fromJson(checkinData);
        _statusMessage = 'PIN lockout cleared successfully using account password.';
        notifyListeners();
        return true;
      }
    } catch (e) {
      _errorMessage = 'Password recovery failed: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    super.dispose();
  }
}
