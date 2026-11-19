/// Emergency Contact Model matching backend schema and supporting local SQLite offline storage.
class EmergencyContactModel {
  final int? id;
  final String? clientUuid;
  final String contactName;
  final String phoneNumber;
  final String relationship;
  final int priorityOrder;
  final String? email;
  final bool isActive;
  final bool notifySms;
  final bool notifyPush;
  final String syncStatus; // 'synced', 'pending', 'failed'
  final String syncOperation; // 'NONE', 'CREATE', 'UPDATE', 'DELETE'
  final DateTime? updatedAt;

  EmergencyContactModel({
    this.id,
    this.clientUuid,
    required this.contactName,
    required this.phoneNumber,
    this.relationship = 'Family',
    this.priorityOrder = 1,
    this.email,
    this.isActive = true,
    this.notifySms = true,
    this.notifyPush = true,
    this.syncStatus = 'synced',
    this.syncOperation = 'NONE',
    this.updatedAt,
  });

  bool get isPendingSync => syncStatus == 'pending';
  bool get isSyncFailed => syncStatus == 'failed';
  bool get isSynced => syncStatus == 'synced';

  factory EmergencyContactModel.fromJson(Map<String, dynamic> json) {
    return EmergencyContactModel(
      id: json['id'] as int?,
      clientUuid: json['client_uuid'] as String?,
      contactName: (json['name'] ?? json['contact_name']) as String? ?? '',
      phoneNumber: (json['phone'] ?? json['phone_number']) as String? ?? '',
      relationship: json['relationship'] as String? ?? 'Family',
      priorityOrder: (json['priority_tier'] ?? json['priority_order']) as int? ?? 1,
      email: json['email'] as String?,
      isActive: (json['is_active'] == true || json['is_active'] == 1),
      notifySms: (json['notify_sms'] == true || json['notify_sms'] == 1),
      notifyPush: (json['notify_push'] == true || json['notify_push'] == 1),
      syncStatus: json['sync_status'] as String? ?? 'synced',
      syncOperation: json['sync_operation'] as String? ?? 'NONE',
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (clientUuid != null) 'client_uuid': clientUuid,
      'name': contactName,
      'contact_name': contactName,
      'phone': phoneNumber,
      'phone_number': phoneNumber,
      'relationship': relationship,
      'priority_tier': priorityOrder,
      'priority_order': priorityOrder,
      if (email != null) 'email': email,
      'is_active': isActive,
      'notify_sms': notifySms,
      'notify_push': notifyPush,
    };
  }

  /// Converts model to SQLite table row representation
  Map<String, dynamic> toSqliteMap({String? userId}) {
    return {
      if (id != null) 'server_id': id,
      'client_uuid': clientUuid ?? 'client_${DateTime.now().millisecondsSinceEpoch}_$contactName',
      if (userId != null) 'user_id': userId,
      'name': contactName,
      'phone': phoneNumber,
      'email': email,
      'relationship': relationship,
      'priority_tier': priorityOrder,
      'notify_sms': notifySms ? 1 : 0,
      'notify_push': notifyPush ? 1 : 0,
      'notify_call': 0,
      'is_active': isActive ? 1 : 0,
      'sync_status': syncStatus,
      'sync_operation': syncOperation,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
    };
  }

  /// Reconstitutes model from SQLite table row
  factory EmergencyContactModel.fromSqlite(Map<String, dynamic> row) {
    return EmergencyContactModel(
      id: row['server_id'] as int?,
      clientUuid: row['client_uuid'] as String?,
      contactName: row['name'] as String? ?? '',
      phoneNumber: row['phone'] as String? ?? '',
      relationship: row['relationship'] as String? ?? 'Family',
      priorityOrder: row['priority_tier'] as int? ?? 1,
      email: row['email'] as String?,
      isActive: (row['is_active'] == 1 || row['is_active'] == true),
      notifySms: (row['notify_sms'] == 1 || row['notify_sms'] == true),
      notifyPush: (row['notify_push'] == 1 || row['notify_push'] == true),
      syncStatus: row['sync_status'] as String? ?? 'synced',
      syncOperation: row['sync_operation'] as String? ?? 'NONE',
      updatedAt: row['updated_at'] != null ? DateTime.tryParse(row['updated_at'].toString()) : null,
    );
  }

  EmergencyContactModel copyWith({
    int? id,
    String? clientUuid,
    String? contactName,
    String? phoneNumber,
    String? relationship,
    int? priorityOrder,
    String? email,
    bool? isActive,
    bool? notifySms,
    bool? notifyPush,
    String? syncStatus,
    String? syncOperation,
    DateTime? updatedAt,
  }) {
    return EmergencyContactModel(
      id: id ?? this.id,
      clientUuid: clientUuid ?? this.clientUuid,
      contactName: contactName ?? this.contactName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      relationship: relationship ?? this.relationship,
      priorityOrder: priorityOrder ?? this.priorityOrder,
      email: email ?? this.email,
      isActive: isActive ?? this.isActive,
      notifySms: notifySms ?? this.notifySms,
      notifyPush: notifyPush ?? this.notifyPush,
      syncStatus: syncStatus ?? this.syncStatus,
      syncOperation: syncOperation ?? this.syncOperation,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
