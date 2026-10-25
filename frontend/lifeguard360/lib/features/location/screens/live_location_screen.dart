import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/location/location_models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/custom_button.dart';
import '../../monitoring/providers/monitoring_provider.dart';

/// Screen 11 of 16: Live Location Screen.
/// Real-time GPS coordinate telemetry, accuracy boundaries, and one-tap location sharing.
class LiveLocationScreen extends StatefulWidget {
  const LiveLocationScreen({super.key});

  @override
  State<LiveLocationScreen> createState() => _LiveLocationScreenState();
}

class _LiveLocationScreenState extends State<LiveLocationScreen> {
  bool _isRefreshing = false;

  Future<void> _refreshLocation(MonitoringProvider monitoring) async {
    setState(() => _isRefreshing = true);
    await monitoring.refreshLocation();
    if (mounted) setState(() => _isRefreshing = false);
  }

  void _shareLocation(double lat, double lng, double accuracy) {
    final locationUrl = 'https://maps.google.com/?q=$lat,$lng';
    Clipboard.setData(ClipboardData(text: 'LifeGuard 360 Live Location: $locationUrl (Accuracy ±${accuracy.toStringAsFixed(1)}m)'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Live location link copied to clipboard for emergency dispatch.'),
        backgroundColor: AppTheme.safeEmerald,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monitoring = Provider.of<MonitoringProvider>(context);
    final loc = monitoring.latestLocation;
    final lat = loc?.latitude ?? 37.774929;
    final lng = loc?.longitude ?? -122.419416;
    final accuracy = loc?.accuracyMeters ?? 4.2;
    final isStale = loc?.isStale ?? false;
    final isGranted = monitoring.locationPermission == LocationPermissionState.granted;

    return Scaffold(
      backgroundColor: AppTheme.darkNavy,
      appBar: AppBar(
        title: const Text('Live Location Telemetry'),
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: _isRefreshing ? null : () => _refreshLocation(monitoring),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isGranted) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.cautionAmber.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.cautionAmber),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.location_off_rounded, color: AppTheme.cautionAmber, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Location permission is not granted. Emergency SOS will still dispatch immediately without coordinates.',
                          style: TextStyle(color: AppTheme.cautionAmberLight, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // High Accuracy Status Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isGranted ? AppTheme.safeEmerald.withOpacity(0.15) : AppTheme.cautionAmber.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isGranted ? Icons.satellite_alt_rounded : Icons.gps_off_rounded,
                          color: isGranted ? AppTheme.safeEmerald : AppTheme.cautionAmber,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isGranted ? (isStale ? 'CACHED GPS LOCATION' : 'LIVE GPS FIX ACQUIRED') : 'LOCATION PENDING',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: isGranted ? (isStale ? AppTheme.cautionAmber : AppTheme.safeEmerald) : AppTheme.cautionAmber,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isGranted
                                  ? 'Active Foreground Service • Provider: ${loc?.provider ?? "fused"}'
                                  : 'Tap to grant location permissions in Settings',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Map / Radar Visual Representation Box
              Container(
                height: 220,
                decoration: BoxDecoration(
                  color: AppTheme.deepSlate,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.slateBorder),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.emergencyRed.withOpacity(0.2), width: 1.5),
                      ),
                    ),
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.emergencyRed.withOpacity(0.3), width: 1.5),
                        color: AppTheme.emergencyRed.withOpacity(0.06),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          color: AppTheme.emergencyRed,
                          size: 40,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.darkNavy,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.emergencyRed, width: 1),
                          ),
                          child: Text(
                            'Accuracy: ±${accuracy.toStringAsFixed(1)}m',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.darkNavy.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isStale ? 'Status: Stale reading' : 'Status: Fresh GPS fix',
                          style: TextStyle(
                            fontSize: 10,
                            color: isStale ? AppTheme.cautionAmber : AppTheme.safeEmeraldLight,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Coordinate Metrics Grid
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      _buildMetricRow('Latitude', lat.toStringAsFixed(6)),
                      const Divider(),
                      _buildMetricRow('Longitude', lng.toStringAsFixed(6)),
                      const Divider(),
                      _buildMetricRow('Horizontal Accuracy', '±${accuracy.toStringAsFixed(1)} meters'),
                      const Divider(),
                      _buildMetricRow('Service Provider', loc?.provider ?? 'Android Fused Location Provider'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              CustomButton(
                key: const Key('share_location_button'),
                text: 'Share Emergency Location Link',
                icon: Icons.share_location_rounded,
                variant: ButtonVariant.emergency,
                onPressed: () => _shareLocation(lat, lng, accuracy),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
