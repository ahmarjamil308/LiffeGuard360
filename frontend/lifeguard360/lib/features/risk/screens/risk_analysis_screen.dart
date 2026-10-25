import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Screen 7 of 16: Risk Analysis Screen.
/// Transparent breakdown of 0-100 risk index, factor contributions, formula & missing data rules.
class RiskAnalysisScreen extends StatefulWidget {
  const RiskAnalysisScreen({super.key});

  @override
  State<RiskAnalysisScreen> createState() => _RiskAnalysisScreenState();
}

class _RiskAnalysisScreenState extends State<RiskAnalysisScreen> {
  // Demo baseline state
  final double _compositeScore = 0.0;
  final String _riskLevel = 'LOW';
  final bool _isDegraded = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkNavy,
      appBar: AppBar(
        title: const Text('Risk Analysis'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Circular Gauge / Score Hero Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                  child: Column(
                    children: [
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _getRiskColor(_compositeScore),
                            width: 8,
                          ),
                          color: _getRiskColor(_compositeScore).withOpacity(0.08),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _compositeScore.toStringAsFixed(0),
                                style: TextStyle(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w900,
                                  color: _getRiskColor(_compositeScore),
                                ),
                              ),
                              const Text(
                                'OUT OF 100',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: _getRiskColor(_compositeScore).withOpacity(0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _getRiskColor(_compositeScore)),
                        ),
                        child: Text(
                          '$_riskLevel RISK LEVEL',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: _getRiskColor(_compositeScore),
                          ),
                        ),
                      ),
                      if (_isDegraded) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'Sensor feeds degraded: Some factors marked UNKNOWN',
                          style: TextStyle(fontSize: 11, color: AppTheme.cautionAmber),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Factor Contributions
              const Text(
                'FOUR FACTOR BREAKDOWN',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 10),

              _buildFactorRow(
                name: 'Smart Check-In Factor',
                weightText: '40% (0.40)',
                score: 0.0,
                contribution: 0.0,
                status: 'CONFIRMED SAFE',
                statusColor: AppTheme.safeEmerald,
                description: 'Check-in on schedule. Missed check-in escalates after grace period.',
              ),
              _buildFactorRow(
                name: 'Impact & Fall Factor',
                weightText: '35% (0.35)',
                score: 0.0,
                contribution: 0.0,
                status: 'NORMAL',
                statusColor: AppTheme.safeEmerald,
                description: 'Continuous accelerometer analysis. No sudden fall or heavy impact detected.',
              ),
              _buildFactorRow(
                name: 'Battery Level Factor',
                weightText: '15% (0.15)',
                score: 0.0,
                contribution: 0.0,
                status: 'NOMINAL',
                statusColor: AppTheme.safeEmerald,
                description: 'Battery healthy (>20%). Critical battery (<10%) increases risk factor.',
              ),
              _buildFactorRow(
                name: 'Transit & Motion Factor',
                weightText: '10% (0.10)',
                score: 0.0,
                contribution: 0.0,
                status: 'STATIONARY (SAFE)',
                statusColor: AppTheme.safeEmerald,
                description: 'Stationary resting phone contributes 0 risk points and never triggers distress.',
              ),
              const SizedBox(height: 16),

              // Explainable Formula Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.functions_rounded, color: AppTheme.textSecondary, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Mathematical Formula & Weighting',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.darkNavy,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.slateBorder),
                        ),
                        child: const Text(
                          'R = round( 0.40·Sc + 0.35·Si + 0.15·Sb + 0.10·St )\nClamped strictly to [0, 100]',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: AppTheme.safeEmeraldLight,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Transparency Disclaimer: The risk score is an assistive heuristic decision-support metric and does not provide an absolute physical safety guarantee. Manual SOS bypasses all risk calculation unconditionally.',
                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getRiskColor(double score) {
    if (score < 20) return AppTheme.safeEmerald;
    if (score < 50) return AppTheme.cautionAmber;
    if (score < 80) return Colors.orange;
    return AppTheme.emergencyRed;
  }

  Widget _buildFactorRow({
    required String name,
    required String weightText,
    required double score,
    required double contribution,
    required String status,
    required Color statusColor,
    required String description,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.slateBorder.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Weight: $weightText',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Score: ${score.toStringAsFixed(0)} • Points: +${contribution.toStringAsFixed(1)}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
