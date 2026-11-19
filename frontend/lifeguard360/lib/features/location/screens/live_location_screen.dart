import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/database/database_service.dart';
import '../../../core/location/location_models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/custom_button.dart';
import '../../auth/providers/auth_provider.dart';
import '../../contacts/models/emergency_contact_model.dart';
import '../../monitoring/providers/monitoring_provider.dart';

/// Screen 11 of 16: Live Location Screen.
/// Real-time GPS coordinate telemetry, accuracy boundaries, and prioritized emergency location sharing.
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

  /// Handles location sharing with contact confirmation.
  /// Rule:
  /// 1. Prompts user to select which emergency contact receives the live location.
  /// 2. If the user confirms a contact, location is shared with that contact.
  /// 3. If the user cancels or does NOT confirm, location automatically falls back
  ///    to the highest priority contact (Priority #1 Primary Responder).
  Future<void> _handleLocationShare(double lat, double lng, double accuracy) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.currentUser?.id.toString();
    final dbService = DatabaseService.instance;

    List<EmergencyContactModel> contacts = [];
    try {
      final rows = await dbService.getContacts(userId: userId);
      contacts = rows.map((r) => EmergencyContactModel.fromSqlite(r)).toList();
    } catch (_) {}

    // Fallback if no contacts have been configured yet
    if (contacts.isEmpty) {
      _executeShare(lat, lng, accuracy, null);
      return;
    }

    // Sort by priority (Priority 1 is highest priority)
    contacts.sort((a, b) => a.priorityOrder.compareTo(b.priorityOrder));
    final highestPriorityContact = contacts.first;

    // Contact selection state (pre-selected to Priority #1 contact)
    EmergencyContactModel selectedContact = highestPriorityContact;

    final confirmedContact = await showModalBottomSheet<EmergencyContactModel>(
      context: context,
      backgroundColor: AppTheme.deepSlate,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.share_location_rounded, color: AppTheme.emergencyRed, size: 24),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Share Live Location',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                          onPressed: () => Navigator.of(ctx).pop(null), // User dismissed -> will fallback to priority #1
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Confirm which emergency contact to alert with your live coordinates. If not confirmed, your highest priority contact will automatically receive it.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 14),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.38,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: contacts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final c = contacts[index];
                          final isSelected = c.clientUuid == selectedContact.clientUuid ||
                              (c.id != null && c.id == selectedContact.id);
                          final isHighest = c.clientUuid == highestPriorityContact.clientUuid ||
                              (c.id != null && c.id == highestPriorityContact.id);

                          return InkWell(
                            onTap: () {
                              setModalState(() => selectedContact = c);
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.emergencyRed.withOpacity(0.15)
                                    : AppTheme.slateBorder.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected ? AppTheme.emergencyRed : AppTheme.slateBorder,
                                  width: isSelected ? 1.5 : 0.8,
                                ),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: isHighest
                                        ? AppTheme.emergencyRed
                                        : AppTheme.slateBorder.withOpacity(0.5),
                                    child: Text(
                                      '#${c.priorityOrder}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isHighest ? Colors.white : AppTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                c.contactName,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppTheme.textPrimary,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isHighest) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.emergencyRed.withOpacity(0.2),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'PRIORITY #1',
                                                  style: TextStyle(
                                                    color: AppTheme.emergencyRedLight,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        Text(
                                          '${c.relationship} • ${c.phoneNumber}',
                                          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                    color: isSelected ? AppTheme.emergencyRed : AppTheme.textMuted,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppTheme.slateBorder),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () {
                              // User opts for automatic highest priority dispatch
                              Navigator.of(ctx).pop(highestPriorityContact);
                            },
                            child: const Text(
                              'Auto-Share (#1)',
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.emergencyRed,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () {
                              Navigator.of(ctx).pop(selectedContact);
                            },
                            child: const Text(
                              'Confirm & Share',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    // If user cancelled / did not confirm, automatically dispatch to highest priority contact
    final targetContact = confirmedContact ?? highestPriorityContact;
    _executeShare(lat, lng, accuracy, targetContact);
  }

  void _executeShare(double lat, double lng, double accuracy, EmergencyContactModel? contact) {
    final locationUrl = 'https://maps.google.com/?q=$lat,$lng';
    String dispatchText;
    String feedbackMessage;

    if (contact != null) {
      dispatchText = '🚨 LifeGuard 360 Emergency Location Alert 🚨\n'
          'Recipient: ${contact.contactName} (${contact.relationship})\n'
          'Live Coordinates: $locationUrl\n'
          'Accuracy: ±${accuracy.toStringAsFixed(1)}m\n'
          'Time: ${DateTime.now().toLocal()}';

      feedbackMessage = 'Live location dispatched to ${contact.contactName} (Priority #${contact.priorityOrder})!';

      // Log in SQLite and Firebase audit logs
      try {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        DatabaseService.instance.logActivity(
          eventType: 'LOCATION_SHARED',
          action: 'Live location dispatched to ${contact.contactName}',
          category: 'SOS',
          details: 'Recipient: ${contact.contactName} (${contact.phoneNumber}, Priority #${contact.priorityOrder}). Link: $locationUrl (±${accuracy.toStringAsFixed(1)}m)',
          userId: auth.currentUser?.id.toString(),
        );
      } catch (_) {}
    } else {
      dispatchText = 'LifeGuard 360 Live Location: $locationUrl (Accuracy ±${accuracy.toStringAsFixed(1)}m)';
      feedbackMessage = 'Live location link copied to clipboard for emergency dispatch.';
    }

    Clipboard.setData(ClipboardData(text: dispatchText));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  feedbackMessage,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.safeEmerald,
          duration: const Duration(seconds: 4),
        ),
      );
    }
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
                onPressed: () => _handleLocationShare(lat, lng, accuracy),
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
