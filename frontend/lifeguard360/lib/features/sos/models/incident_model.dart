/// Incident Model representing an emergency distress event.
class IncidentModel {
  final int? id;
  final String clientIncidentUuid;
  final String triggerSource; // MANUAL_BUTTON, CHECKIN_TIMEOUT, IMPACT_FALL, etc.
  final String status; // ACTIVE, RESOLVED, FALSE_ALARM, CANCELLED, QUEUED_OFFLINE
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final double? riskScoreAtTrigger;
  final String? localNotes;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final List<dynamic>? dispatches;

  IncidentModel({
    this.id,
    required this.clientIncidentUuid,
    required this.triggerSource,
    required this.status,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.riskScoreAtTrigger,
    this.localNotes,
    required this.createdAt,
    this.resolvedAt,
    this.dispatches,
  });

  factory IncidentModel.fromJson(Map<String, dynamic> json) {
    return IncidentModel(
      id: json['id'] as int?,
      clientIncidentUuid: json['client_incident_uuid'] as String? ?? '',
      triggerSource: json['trigger_source'] as String? ?? 'MANUAL_BUTTON',
      status: json['status'] as String? ?? 'ACTIVE',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      accuracyMeters: (json['accuracy_meters'] as num?)?.toDouble(),
      riskScoreAtTrigger: (json['risk_score_at_trigger'] as num?)?.toDouble(),
      localNotes: json['local_notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      resolvedAt: json['resolved_at'] != null
          ? DateTime.tryParse(json['resolved_at'].toString())
          : null,
      dispatches: json['dispatches'] as List<dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'client_incident_uuid': clientIncidentUuid,
      'trigger_source': triggerSource,
      'status': status,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
      if (riskScoreAtTrigger != null) 'risk_score_at_trigger': riskScoreAtTrigger,
      if (localNotes != null) 'local_notes': localNotes,
      'created_at': createdAt.toIso8601String(),
      if (resolvedAt != null) 'resolved_at': resolvedAt?.toIso8601String(),
    };
  }

  IncidentModel copyWith({
    int? id,
    String? clientIncidentUuid,
    String? triggerSource,
    String? status,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    double? riskScoreAtTrigger,
    String? localNotes,
    DateTime? createdAt,
    DateTime? resolvedAt,
    List<dynamic>? dispatches,
  }) {
    return IncidentModel(
      id: id ?? this.id,
      clientIncidentUuid: clientIncidentUuid ?? this.clientIncidentUuid,
      triggerSource: triggerSource ?? this.triggerSource,
      status: status ?? this.status,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      riskScoreAtTrigger: riskScoreAtTrigger ?? this.riskScoreAtTrigger,
      localNotes: localNotes ?? this.localNotes,
      createdAt: createdAt ?? this.createdAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      dispatches: dispatches ?? this.dispatches,
    );
  }

  bool get isLocallyQueued => status == 'QUEUED_OFFLINE';
  bool get isServerAccepted => id != null && (status == 'ACTIVE' || status == 'RESOLVED' || status == 'FALSE_ALARM' || status == 'CANCELLED');
  bool get isGatewayAccepted =>
      dispatches != null &&
      dispatches!.any((d) => d is Map && (d['status'] == 'SENT' || d['status'] == 'DELIVERED' || d['status'] == 'VIEWED' || d['status'] == 'ACKNOWLEDGED'));
  bool get isDelivered =>
      dispatches != null &&
      dispatches!.any((d) => d is Map && (d['status'] == 'DELIVERED' || d['status'] == 'VIEWED' || d['status'] == 'ACKNOWLEDGED'));
  bool get isViewed =>
      dispatches != null &&
      dispatches!.any((d) => d is Map && (d['status'] == 'VIEWED' || d['status'] == 'ACKNOWLEDGED'));
  bool get isAcknowledged =>
      dispatches != null &&
      dispatches!.any((d) => d is Map && d['status'] == 'ACKNOWLEDGED');
}
