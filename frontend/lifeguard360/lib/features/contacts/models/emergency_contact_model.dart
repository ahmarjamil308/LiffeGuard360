/// Emergency Contact Model matching backend schema.
class EmergencyContactModel {
  final int? id;
  final String contactName;
  final String phoneNumber;
  final String relationship;
  final int priorityOrder;
  final String? email;
  final bool isActive;
  final bool notifySms;
  final bool notifyPush;

  EmergencyContactModel({
    this.id,
    required this.contactName,
    required this.phoneNumber,
    this.relationship = 'Family',
    this.priorityOrder = 1,
    this.email,
    this.isActive = true,
    this.notifySms = true,
    this.notifyPush = true,
  });

  factory EmergencyContactModel.fromJson(Map<String, dynamic> json) {
    return EmergencyContactModel(
      id: json['id'] as int?,
      contactName: (json['name'] ?? json['contact_name']) as String? ?? '',
      phoneNumber: (json['phone'] ?? json['phone_number']) as String? ?? '',
      relationship: json['relationship'] as String? ?? 'Family',
      priorityOrder: (json['priority_tier'] ?? json['priority_order']) as int? ?? 1,
      email: json['email'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      notifySms: json['notify_sms'] as bool? ?? true,
      notifyPush: json['notify_push'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
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

  EmergencyContactModel copyWith({
    int? id,
    String? contactName,
    String? phoneNumber,
    String? relationship,
    int? priorityOrder,
    String? email,
    bool? isActive,
    bool? notifySms,
    bool? notifyPush,
  }) {
    return EmergencyContactModel(
      id: id ?? this.id,
      contactName: contactName ?? this.contactName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      relationship: relationship ?? this.relationship,
      priorityOrder: priorityOrder ?? this.priorityOrder,
      email: email ?? this.email,
      isActive: isActive ?? this.isActive,
      notifySms: notifySms ?? this.notifySms,
      notifyPush: notifyPush ?? this.notifyPush,
    );
  }
}
