/// LifeGuard 360 - Smart Check-In Model
/// Conforms strictly to backend schema and state machine.
class CheckInModel {
  final int? id;
  final int? userId;
  final String title;
  final String? destinationNote;
  final DateTime scheduledFor;
  final int gracePeriodMinutes;
  final int preAlertSeconds;
  final String status; // SCHEDULED, SAFE_COMPLETED, IN_GRACE_PERIOD, OVERDUE_PRE_ALERT, OVERDUE_ESCALATED, CANCELLED
  final bool hasPin;
  final int failedPinAttempts;
  final DateTime? lockedUntil;
  final bool isLocked;
  final DateTime? checkedInAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  CheckInModel({
    this.id,
    this.userId,
    required this.title,
    this.destinationNote,
    required this.scheduledFor,
    this.gracePeriodMinutes = 10,
    this.preAlertSeconds = 20,
    this.status = 'SCHEDULED',
    this.hasPin = false,
    this.failedPinAttempts = 0,
    this.lockedUntil,
    this.isLocked = false,
    this.checkedInAt,
    this.createdAt,
    this.updatedAt,
  });

  factory CheckInModel.fromJson(Map<String, dynamic> json) {
    return CheckInModel(
      id: json['id'] as int?,
      userId: json['user_id'] as int?,
      title: json['title'] as String? ?? 'Routine Check-In',
      destinationNote: json['destination_note'] as String?,
      scheduledFor: json['scheduled_for'] != null
          ? DateTime.tryParse(json['scheduled_for'].toString())?.toUtc() ?? DateTime.now().toUtc()
          : DateTime.now().toUtc(),
      gracePeriodMinutes: json['grace_period_minutes'] as int? ?? 10,
      preAlertSeconds: json['pre_alert_seconds'] as int? ?? 20,
      status: json['status'] as String? ?? 'SCHEDULED',
      hasPin: json['has_pin'] as bool? ?? false,
      failedPinAttempts: json['failed_pin_attempts'] as int? ?? 0,
      lockedUntil: json['locked_until'] != null
          ? DateTime.tryParse(json['locked_until'].toString())?.toUtc()
          : null,
      isLocked: json['is_locked'] as bool? ?? false,
      checkedInAt: json['checked_in_at'] != null
          ? DateTime.tryParse(json['checked_in_at'].toString())?.toUtc()
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())?.toUtc()
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())?.toUtc()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      'title': title,
      if (destinationNote != null) 'destination_note': destinationNote,
      'scheduled_for': scheduledFor.toIso8601String(),
      'grace_period_minutes': gracePeriodMinutes,
      'pre_alert_seconds': preAlertSeconds,
      'status': status,
      'has_pin': hasPin,
      'failed_pin_attempts': failedPinAttempts,
      if (lockedUntil != null) 'locked_until': lockedUntil?.toIso8601String(),
      'is_locked': isLocked,
      if (checkedInAt != null) 'checked_in_at': checkedInAt?.toIso8601String(),
      if (createdAt != null) 'created_at': createdAt?.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt?.toIso8601String(),
    };
  }

  CheckInModel copyWith({
    int? id,
    int? userId,
    String? title,
    String? destinationNote,
    DateTime? scheduledFor,
    int? gracePeriodMinutes,
    int? preAlertSeconds,
    String? status,
    bool? hasPin,
    int? failedPinAttempts,
    DateTime? lockedUntil,
    bool? isLocked,
    DateTime? checkedInAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CheckInModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      destinationNote: destinationNote ?? this.destinationNote,
      scheduledFor: scheduledFor ?? this.scheduledFor,
      gracePeriodMinutes: gracePeriodMinutes ?? this.gracePeriodMinutes,
      preAlertSeconds: preAlertSeconds ?? this.preAlertSeconds,
      status: status ?? this.status,
      hasPin: hasPin ?? this.hasPin,
      failedPinAttempts: failedPinAttempts ?? this.failedPinAttempts,
      lockedUntil: lockedUntil ?? this.lockedUntil,
      isLocked: isLocked ?? this.isLocked,
      checkedInAt: checkedInAt ?? this.checkedInAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Lifecycle boundary timestamps
  DateTime get graceExpiryTime => scheduledFor.add(Duration(minutes: gracePeriodMinutes));
  DateTime get preAlertExpiryTime => graceExpiryTime.add(Duration(seconds: preAlertSeconds));

  // State evaluation
  bool get isScheduled => status == 'SCHEDULED';
  bool get isInGracePeriod => status == 'IN_GRACE_PERIOD';
  bool get isPreAlert => status == 'OVERDUE_PRE_ALERT';
  bool get isOverdueEscalated => status == 'OVERDUE_ESCALATED';
  bool get isSafeCompleted => status == 'SAFE_COMPLETED';
  bool get isCancelled => status == 'CANCELLED';

  /// Deterministically evaluates current state matching backend state machine
  String evaluateState([DateTime? now]) {
    if (isSafeCompleted || isCancelled || isOverdueEscalated) {
      return status;
    }
    final current = now ?? DateTime.now().toUtc();
    if (current.isBefore(scheduledFor)) {
      return 'SCHEDULED';
    }
    if (current.isBefore(graceExpiryTime)) {
      return 'IN_GRACE_PERIOD';
    }
    if (current.isBefore(preAlertExpiryTime)) {
      return 'OVERDUE_PRE_ALERT';
    }
    return 'OVERDUE_ESCALATED';
  }

  /// Calculates seconds remaining until scheduled time (or zero if reached)
  int secondsToScheduled([DateTime? now]) {
    final current = now ?? DateTime.now().toUtc();
    return scheduledFor.difference(current).inSeconds;
  }

  /// Calculates seconds remaining in grace period (or zero if expired)
  int secondsRemainingInGrace([DateTime? now]) {
    final current = now ?? DateTime.now().toUtc();
    return graceExpiryTime.difference(current).inSeconds;
  }

  /// Calculates seconds remaining in pre-alert countdown (or zero if expired)
  int secondsRemainingInPreAlert([DateTime? now]) {
    final current = now ?? DateTime.now().toUtc();
    return preAlertExpiryTime.difference(current).inSeconds;
  }
}
