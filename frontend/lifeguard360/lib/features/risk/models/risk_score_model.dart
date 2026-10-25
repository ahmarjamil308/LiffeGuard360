/// Explainable Risk Score and Factor Breakdown Model.
class RiskFactorDetail {
  final String name;
  final double score; // 0 - 100
  final double weight; // e.g. 0.40, 0.35, 0.15, 0.10
  final double contribution; // score * weight
  final String status; // NORMAL, WARNING, CRITICAL, DEGRADED, UNKNOWN
  final String description;

  RiskFactorDetail({
    required this.name,
    required this.score,
    required this.weight,
    required this.contribution,
    required this.status,
    required this.description,
  });

  factory RiskFactorDetail.fromJson(Map<String, dynamic> json) {
    return RiskFactorDetail(
      name: json['name'] as String? ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      weight: (json['weight'] as num?)?.toDouble() ?? 0.0,
      contribution: (json['contribution'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'NORMAL',
      description: json['description'] as String? ?? '',
    );
  }
}

class RiskScoreModel {
  final double score; // 0.0 - 100.0
  final String riskLevel; // LOW, MODERATE, HIGH, CRITICAL
  final bool isDegraded;
  final String explanation;
  final DateTime calculatedAt;
  final Map<String, RiskFactorDetail> factors;

  RiskScoreModel({
    required this.score,
    required this.riskLevel,
    this.isDegraded = false,
    required this.explanation,
    required this.calculatedAt,
    required this.factors,
  });

  factory RiskScoreModel.fromJson(Map<String, dynamic> json) {
    final factorsMap = <String, RiskFactorDetail>{};
    if (json['factors'] is Map<String, dynamic>) {
      (json['factors'] as Map<String, dynamic>).forEach((key, val) {
        if (val is Map<String, dynamic>) {
          factorsMap[key] = RiskFactorDetail.fromJson(val);
        }
      });
    }

    return RiskScoreModel(
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      riskLevel: json['risk_level'] as String? ?? 'LOW',
      isDegraded: json['is_degraded'] as bool? ?? false,
      explanation: json['explanation'] as String? ?? 'Safety parameters nominal.',
      calculatedAt: json['calculated_at'] != null
          ? DateTime.tryParse(json['calculated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      factors: factorsMap,
    );
  }
}
