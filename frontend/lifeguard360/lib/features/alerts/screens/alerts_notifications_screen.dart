import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state_widget.dart';

/// Screen 12 of 16: Alerts & Notifications Screen.
/// Notification inbox with transactional dispatch delivery status tracking.
class AlertsNotificationsScreen extends StatefulWidget {
  const AlertsNotificationsScreen({super.key});

  @override
  State<AlertsNotificationsScreen> createState() => _AlertsNotificationsScreenState();
}

class _AlertsNotificationsScreenState extends State<AlertsNotificationsScreen> {
  int _selectedFilterIndex = 0;

  final List<Map<String, dynamic>> _alerts = [
    {
      'id': 101,
      'title': 'Emergency SOS Distress Dispatched',
      'body': 'Emergency SMS dispatched to Sarah Jenkins (+14155552671)',
      'status': AppConstants.statusDelivered,
      'channel': 'SMS (Twilio)',
      'timestamp': '10 minutes ago',
      'isEmergency': true,
    },
    {
      'id': 102,
      'title': 'Emergency Push Delivered to Responder',
      'body': 'FCM high-priority alert acknowledged by Dr. Robert Jenkins',
      'status': AppConstants.statusAcknowledged,
      'channel': 'Push (FCM)',
      'timestamp': '12 minutes ago',
      'isEmergency': true,
    },
    {
      'id': 103,
      'title': 'Smart Check-In Reminder',
      'body': 'Scheduled safety check-in prompt: Please confirm status.',
      'status': AppConstants.statusSent,
      'channel': 'Local / Push',
      'timestamp': '1 hour ago',
      'isEmergency': false,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = _alerts.where((a) {
      if (_selectedFilterIndex == 1) return a['isEmergency'] == true;
      if (_selectedFilterIndex == 2) return a['isEmergency'] == false;
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.darkNavy,
      appBar: AppBar(
        title: const Text('Alerts & Notifications'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Filter Selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  _buildFilterChip('All Alerts', 0),
                  const SizedBox(width: 8),
                  _buildFilterChip('Emergencies', 1),
                  const SizedBox(width: 8),
                  _buildFilterChip('Check-Ins', 2),
                ],
              ),
            ),
            const Divider(),

            Expanded(
              child: filtered.isEmpty
                  ? const EmptyStateWidget(
                      icon: Icons.notifications_none_rounded,
                      title: 'No Alerts Found',
                      message: 'There are no active or historical notifications in this filter category.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final alert = filtered[index];
                        final isEmergency = alert['isEmergency'] as bool;
                        final status = alert['status'] as String;

                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isEmergency
                                          ? Icons.warning_amber_rounded
                                          : Icons.schedule_rounded,
                                      color: isEmergency
                                          ? AppTheme.emergencyRed
                                          : AppTheme.cautionAmber,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        alert['title'] as String,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                    ),
                                    _buildStatusBadge(status),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  alert['body'] as String,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Channel: ${alert['channel']}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                    Text(
                                      alert['timestamp'] as String,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final isSelected = _selectedFilterIndex == index;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: AppTheme.emergencyRed,
      backgroundColor: AppTheme.deepSlate,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.white : AppTheme.textSecondary,
      ),
      onSelected: (val) {
        if (val) setState(() => _selectedFilterIndex = index);
      },
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    switch (status) {
      case AppConstants.statusAcknowledged:
        color = AppTheme.safeEmerald;
        break;
      case AppConstants.statusDelivered:
        color = Colors.teal;
        break;
      case AppConstants.statusSent:
        color = Colors.lightBlue;
        break;
      case AppConstants.statusQueued:
      case AppConstants.statusQueuedOffline:
        color = AppTheme.cautionAmber;
        break;
      case AppConstants.statusFailed:
      default:
        color = AppTheme.emergencyRed;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
