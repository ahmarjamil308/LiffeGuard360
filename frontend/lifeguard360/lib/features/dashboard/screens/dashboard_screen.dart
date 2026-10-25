import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/network_banner.dart';
import '../../auth/providers/auth_provider.dart';
import '../../monitoring/providers/monitoring_provider.dart';
import '../../sos/providers/sos_provider.dart';

/// Screen 4 of 16: Home Dashboard Screen.
/// Central safety command center with immediate SOS trigger, risk glance, and feature navigation.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SOSProvider>(context, listen: false).loadQueuedIncidents();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final sos = Provider.of<SOSProvider>(context);
    final monitoring = Provider.of<MonitoringProvider>(context);
    final isMonitoringActive = monitoring.isMonitoringActive;
    final userName = auth.currentUser?.fullName ?? 'User';

    return Scaffold(
      backgroundColor: AppTheme.darkNavy,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_rounded, color: AppTheme.emergencyRed, size: 22),
            const SizedBox(width: 8),
            Text(
              AppConstants.appName.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Alerts & Notifications',
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.alertsNotifications),
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Profile',
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.profile),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (sos.queuedIncidents.any((e) => e.status == AppConstants.statusQueuedOffline))
              NetworkUnavailableBanner(
                pendingCount: sos.queuedIncidents
                    .where((e) => e.status == AppConstants.statusQueuedOffline)
                    .length,
                isSyncing: sos.isSyncing,
                onSyncNow: () => sos.syncPendingIncidents(),
              ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Welcome & Monitoring Status Header Card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isMonitoringActive
                                    ? AppTheme.safeEmerald
                                    : AppTheme.cautionAmber,
                                boxShadow: [
                                  BoxShadow(
                                    color: (isMonitoringActive
                                            ? AppTheme.safeEmerald
                                            : AppTheme.cautionAmber)
                                        .withOpacity(0.5),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Hello, $userName',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isMonitoringActive
                                        ? 'Background Safety Active (Android Service ON)'
                                        : 'Monitoring Paused',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isMonitoringActive
                                          ? AppTheme.safeEmeraldLight
                                          : AppTheme.cautionAmberLight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.tune_rounded, color: AppTheme.textSecondary),
                              tooltip: 'Monitoring Status Details',
                              onPressed: () => Navigator.of(context)
                                  .pushNamed(AppRoutes.monitoringStatus),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // GIANT QUICK SOS TRIGGER BUTTON
                    InkWell(
                      key: const Key('dashboard_sos_button'),
                      onTap: () {
                        Navigator.of(context).pushNamed(AppRoutes.sosEmergency);
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppTheme.emergencyRedDark, AppTheme.emergencyRed],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.emergencyRed.withOpacity(0.4),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.warning_amber_rounded,
                                color: AppTheme.emergencyRedDark,
                                size: 36,
                              ),
                            ),
                            const SizedBox(width: 18),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'MANUAL SOS DISTRESS',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Instant dispatch • Bypasses automated risk scoring',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Risk Score & Check-In Glance Grid
                    Row(
                      children: [
                        // Risk Score Card
                        Expanded(
                          child: InkWell(
                            onTap: () => Navigator.of(context).pushNamed(AppRoutes.riskAnalysis),
                            borderRadius: BorderRadius.circular(14),
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Risk Index',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: AppTheme.textSecondary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Icon(Icons.analytics_outlined,
                                            size: 18, color: AppTheme.safeEmerald),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    const Row(
                                      crossAxisAlignment: CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text(
                                          '0',
                                          style: TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.safeEmerald,
                                          ),
                                        ),
                                        Text(
                                          ' / 100',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: AppTheme.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppTheme.safeEmerald.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'LOW RISK',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.safeEmerald,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Smart Check-In Card
                        Expanded(
                          child: InkWell(
                            onTap: () => Navigator.of(context).pushNamed(AppRoutes.smartCheckIn),
                            borderRadius: BorderRadius.circular(14),
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Check-In',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: AppTheme.textSecondary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Icon(Icons.timer_outlined,
                                            size: 18, color: AppTheme.cautionAmber),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    const Text(
                                      'Active',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppTheme.deepSlate,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: AppTheme.slateBorder),
                                      ),
                                      child: const Text(
                                        'Grace: 10m',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Quick Navigation Grid
                    const Text(
                      'SAFETY & MONITORING SERVICES',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 10),

                    GridView.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 1.45,
                      children: [
                        _buildNavTile(
                          context,
                          title: 'Emergency Contacts',
                          subtitle: 'Ranked priority list',
                          icon: Icons.contacts_rounded,
                          route: AppRoutes.emergencyContacts,
                        ),
                        _buildNavTile(
                          context,
                          title: 'Live Location',
                          subtitle: 'GPS coordinates',
                          icon: Icons.my_location_rounded,
                          route: AppRoutes.liveLocation,
                        ),
                        _buildNavTile(
                          context,
                          title: 'Monitoring Status',
                          subtitle: 'Sensors & Android service',
                          icon: Icons.sensors_rounded,
                          route: AppRoutes.monitoringStatus,
                        ),
                        _buildNavTile(
                          context,
                          title: 'Activity Logs',
                          subtitle: 'Audit trail of events',
                          icon: Icons.history_rounded,
                          route: AppRoutes.activityLogs,
                        ),
                        _buildNavTile(
                          context,
                          title: 'Emergency Details',
                          subtitle: 'Active incident response',
                          icon: Icons.emergency_rounded,
                          route: AppRoutes.emergencyResponseDetails,
                        ),
                        _buildNavTile(
                          context,
                          title: 'Settings',
                          subtitle: 'Grace timers & safety PIN',
                          icon: Icons.settings_rounded,
                          route: AppRoutes.settings,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required String route,
  }) {
    return Card(
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed(route),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppTheme.emergencyRed, size: 24),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
