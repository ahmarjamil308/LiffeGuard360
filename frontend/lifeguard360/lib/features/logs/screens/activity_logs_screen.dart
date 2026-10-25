import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state_widget.dart';

/// Screen 13 of 16: Activity Logs Screen.
/// Immutable chronological safety audit log for event auditing and accountability.
class ActivityLogsScreen extends StatefulWidget {
  const ActivityLogsScreen({super.key});

  @override
  State<ActivityLogsScreen> createState() => _ActivityLogsScreenState();
}

class _ActivityLogsScreenState extends State<ActivityLogsScreen> {
  String _selectedFilter = 'ALL';

  final List<Map<String, dynamic>> _logs = [
    {
      'id': 1,
      'event_type': 'MANUAL_SOS_TRIGGERED',
      'action': 'Manual SOS button pressed by user',
      'category': 'SOS',
      'timestamp': 'Today, 10:14:02 AM',
      'details': 'Latitude: 37.7749, Longitude: -122.4194, Accuracy: ±4.5m',
    },
    {
      'id': 2,
      'event_type': 'OUTBOX_SYNC_COMPLETED',
      'action': 'Idempotent SOS dispatch synchronized with backend',
      'category': 'SYSTEM',
      'timestamp': 'Today, 10:14:04 AM',
      'details': '2 dispatches enqueued (SMS + Push)',
    },
    {
      'id': 3,
      'event_type': 'CHECKIN_CONFIRMED_SAFE',
      'action': 'User confirmed scheduled check-in',
      'category': 'CHECKIN',
      'timestamp': 'Today, 09:30:00 AM',
      'details': 'Grace period remaining: 9m 40s. Safe state logged.',
    },
    {
      'id': 4,
      'event_type': 'SENSOR_HEARTBEAT',
      'action': 'Android foreground service telemetry cycle',
      'category': 'SYSTEM',
      'timestamp': 'Today, 09:15:00 AM',
      'details': '3-axis accelerometer nominal. Stationary resting phone.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = _logs.where((log) {
      if (_selectedFilter == 'ALL') return true;
      return log['category'] == _selectedFilter;
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.darkNavy,
      appBar: AppBar(
        title: const Text('Activity Audit Logs'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('All Events', 'ALL'),
                    const SizedBox(width: 8),
                    _buildFilterChip('SOS Distress', 'SOS'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Check-Ins', 'CHECKIN'),
                    const SizedBox(width: 8),
                    _buildFilterChip('System & Sensors', 'SYSTEM'),
                  ],
                ),
              ),
            ),
            const Divider(),

            Expanded(
              child: filtered.isEmpty
                  ? const EmptyStateWidget(
                      icon: Icons.history_edu_rounded,
                      title: 'No Logs Found',
                      message: 'No activity records match the selected category.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final log = filtered[index];
                        final category = log['category'] as String;

                        Color indicatorColor;
                        IconData icon;
                        switch (category) {
                          case 'SOS':
                            indicatorColor = AppTheme.emergencyRed;
                            icon = Icons.warning_rounded;
                            break;
                          case 'CHECKIN':
                            indicatorColor = AppTheme.safeEmerald;
                            icon = Icons.check_circle_outline_rounded;
                            break;
                          case 'SYSTEM':
                          default:
                            indicatorColor = Colors.lightBlue;
                            icon = Icons.info_outline_rounded;
                            break;
                        }

                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(icon, color: indicatorColor, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        log['event_type'] as String,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          fontFamily: 'monospace',
                                          color: indicatorColor,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      log['timestamp'] as String,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  log['action'] as String,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  log['details'] as String,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSecondary,
                                  ),
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

  Widget _buildFilterChip(String label, String key) {
    final isSelected = _selectedFilter == key;
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
        if (val) setState(() => _selectedFilter = key);
      },
    );
  }
}
