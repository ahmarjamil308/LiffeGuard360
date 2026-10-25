import 'package:flutter_test/flutter_test.dart';
import 'package:lifeguard360/core/network/api_client.dart';
import 'package:lifeguard360/core/storage/local_checkin_store.dart';
import 'package:lifeguard360/core/storage/secure_storage_service.dart';
import 'package:lifeguard360/features/checkin/models/checkin_model.dart';
import 'package:lifeguard360/features/checkin/providers/checkin_provider.dart';

class MockCheckInStore implements ILocalCheckInStore {
  final List<Map<String, dynamic>> ops = [];

  @override
  Future<void> enqueueOperation({
    required String action,
    required int checkinId,
    String? pin,
    int? additionalMinutes,
  }) async {
    ops.removeWhere((item) => item['checkin_id'] == checkinId && item['action'] == action);
    ops.add({
      'action': action,
      'checkin_id': checkinId,
      'pin': ?pin,
      'additional_minutes': ?additionalMinutes,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> getPendingOperations() async => List.from(ops);

  @override
  Future<void> removeOperation({required int checkinId, required String action}) async {
    ops.removeWhere((item) => item['checkin_id'] == checkinId && item['action'] == action);
  }

  @override
  Future<void> clearOperations() async => ops.clear();
}

void main() {
  group('CheckInModel State Machine & Duration Calculations', () {
    test('calculateCurrentState deterministically transitions through all 4 time zones', () {
      final checkin = CheckInModel(
        id: 1,
        title: 'Walk in Park',
        scheduledFor: DateTime.utc(2026, 10, 24, 12, 30, 0), // scheduled in 30 mins
        gracePeriodMinutes: 10,
        preAlertSeconds: 20,
      );

      // Time 1: 12:15 -> Before scheduled time -> SCHEDULED
      expect(checkin.evaluateState(DateTime.utc(2026, 10, 24, 12, 15, 0)), equals('SCHEDULED'));
      expect(checkin.secondsToScheduled(DateTime.utc(2026, 10, 24, 12, 15, 0)), equals(900));

      // Time 2: 12:35 -> 5 mins past scheduled -> IN_GRACE_PERIOD
      expect(checkin.evaluateState(DateTime.utc(2026, 10, 24, 12, 35, 0)), equals('IN_GRACE_PERIOD'));
      expect(checkin.secondsRemainingInGrace(DateTime.utc(2026, 10, 24, 12, 35, 0)), equals(300)); // 5 mins left

      // Time 3: 12:40:10 -> Grace expired, 10s into 20s pre-alert -> OVERDUE_PRE_ALERT
      expect(checkin.evaluateState(DateTime.utc(2026, 10, 24, 12, 40, 10)), equals('OVERDUE_PRE_ALERT'));
      expect(checkin.secondsRemainingInPreAlert(DateTime.utc(2026, 10, 24, 12, 40, 10)), equals(10)); // 10s left

      // Time 4: 12:40:25 -> Pre-alert expired -> OVERDUE_ESCALATED
      expect(checkin.evaluateState(DateTime.utc(2026, 10, 24, 12, 40, 25)), equals('OVERDUE_ESCALATED'));
    });

    test('Completed or cancelled check-in preserves terminal status', () {
      final completed = CheckInModel(
        id: 2,
        title: 'Meeting',
        scheduledFor: DateTime.utc(2026, 10, 24, 10, 0, 0),
        status: 'SAFE_COMPLETED',
      );
      expect(completed.evaluateState(DateTime.utc(2026, 10, 24, 13, 0, 0)), equals('SAFE_COMPLETED'));
      expect(completed.isSafeCompleted, isTrue);

      final cancelled = CheckInModel(
        id: 3,
        title: 'Meeting',
        scheduledFor: DateTime.utc(2026, 10, 24, 10, 0, 0),
        status: 'CANCELLED',
      );
      expect(cancelled.evaluateState(DateTime.utc(2026, 10, 24, 13, 0, 0)), equals('CANCELLED'));
      expect(cancelled.isCancelled, isTrue);
    });
  });

  group('CheckInProvider Lifecycle & PIN Challenges', () {
    late CheckInProvider provider;
    late MockSecureStorageService storage;
    late MockCheckInStore checkInStore;
    late ApiClient apiClient;

    setUp(() {
      storage = MockSecureStorageService();
      checkInStore = MockCheckInStore();
      apiClient = ApiClient(secureStorage: storage);
      provider = CheckInProvider(apiClient: apiClient, checkInStore: checkInStore);
    });

    tearDown(() {
      provider.dispose();
    });

    test('Initial provider state has no active check-in', () {
      expect(provider.activeCheckIn, isNull);
      expect(provider.hasActiveCheckIn, isFalse);
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
      expect(provider.isCancellationPendingSync, isFalse);
      expect(provider.isExtensionPendingSync, isFalse);
    });

    test('Active check-in evaluates state dynamically', () {
      final now = DateTime.now().toUtc();
      provider.activeCheckIn = CheckInModel(
        id: 10,
        title: 'Transit',
        scheduledFor: now.add(const Duration(minutes: 15)),
        gracePeriodMinutes: 5,
        preAlertSeconds: 15,
        hasPin: true,
      );

      expect(provider.hasActiveCheckIn, isTrue);
      expect(provider.activeCheckIn!.isScheduled, isTrue);
      expect(provider.activeCheckIn!.hasPin, isTrue);
    });

    test('Cancelling active check-in with PIN requirement enforces PIN verification and queues offline when disconnected', () async {
      provider.activeCheckIn = CheckInModel(
        id: 11,
        title: 'Safe Walk',
        scheduledFor: DateTime.now().toUtc().add(const Duration(minutes: 20)),
        hasPin: true,
      );

      // 1. Attempt cancellation without PIN
      final cancelledWithoutPin = await provider.cancelActiveCheckIn(pin: null);
      expect(cancelledWithoutPin, isFalse);
      expect(provider.errorMessage, contains('PIN required'));
      expect(provider.isCancellationPendingSync, isFalse);

      // 2. Attempt cancellation with valid PIN while offline
      // Note: Without an active HTTP server in unit tests, client throws network exception
      final queuedOffline = await provider.cancelActiveCheckIn(pin: '1234');
      expect(queuedOffline, isTrue);
      // TRUTHFUL BEHAVIOR: Provider marks cancellation as pending server sync, not falsely cancelled!
      expect(provider.isCancellationPendingSync, isTrue);
      expect(provider.statusMessage, contains('Cancellation queued locally'));
      expect(provider.statusMessage, contains('LifeGuard 360 server continues monitoring'));

      // Check persistence in store
      final pendingOps = await checkInStore.getPendingOperations();
      expect(pendingOps.length, equals(1));
      expect(pendingOps.first['action'], equals('CANCEL'));
      expect(pendingOps.first['checkin_id'], equals(11));
      expect(pendingOps.first['pin'], equals('1234'));
    });

    test('Extending active check-in offline enqueues operation and marks isExtensionPendingSync', () async {
      provider.activeCheckIn = CheckInModel(
        id: 12,
        title: 'Late Meeting',
        scheduledFor: DateTime.now().toUtc().add(const Duration(minutes: 10)),
      );

      final extended = await provider.extendActiveCheckIn(additionalMinutes: 15);
      expect(extended, isTrue);
      expect(provider.isExtensionPendingSync, isTrue);
      expect(provider.statusMessage, contains('Extension queued locally'));

      final pendingOps = await checkInStore.getPendingOperations();
      expect(pendingOps.any((op) => op['action'] == 'EXTEND' && op['checkin_id'] == 12), isTrue);
    });

    test('Confirming safe transitions check-in to completed state', () async {
      provider.activeCheckIn = CheckInModel(
        id: 13,
        title: 'Coffee meetup',
        scheduledFor: DateTime.now().toUtc().add(const Duration(minutes: 10)),
        status: 'SCHEDULED',
      );

      // Simulate local completed update
      provider.activeCheckIn = provider.activeCheckIn!.copyWith(
        status: 'SAFE_COMPLETED',
        checkedInAt: DateTime.now().toUtc(),
      );

      expect(provider.activeCheckIn!.isSafeCompleted, isTrue);
      expect(provider.hasActiveCheckIn, isFalse);
    });

    test('Check-in model correctly reflects lockout state from backend', () {
      final lockedCheckIn = CheckInModel(
        id: 14,
        title: 'Locked Commute',
        scheduledFor: DateTime.now().toUtc().add(const Duration(minutes: 15)),
        failedPinAttempts: 5,
        isLocked: true,
        lockedUntil: DateTime.now().toUtc().add(const Duration(minutes: 15)),
      );

      expect(lockedCheckIn.isLocked, isTrue);
      expect(lockedCheckIn.failedPinAttempts, equals(5));
      expect(lockedCheckIn.lockedUntil, isNotNull);
    });
  });
}
