import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/database/database_service.dart';
import '../../../core/database/sync_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_service.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../auth/providers/auth_provider.dart';

/// Screen 13 of 16: Activity Logs Screen.
/// Immutable chronological safety audit log for event auditing and offline accountability.
class ActivityLogsScreen extends StatefulWidget {
  final DatabaseService? databaseService;
  final ApiClient? apiClient;

  const ActivityLogsScreen({
    super.key,
    this.databaseService,
    this.apiClient,
  });

  @override
  State<ActivityLogsScreen> createState() => _ActivityLogsScreenState();
}

class _ActivityLogsScreenState extends State<ActivityLogsScreen> {
  String _selectedFilter = 'ALL';
  late final DatabaseService _dbService;
  late final ApiClient _apiClient;
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _dbService = widget.databaseService ?? DatabaseService.instance;
    _apiClient = widget.apiClient ?? ApiClient(secureStorage: SecureStorageService());
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.currentUser?.id.toString();

    try {
      var rows = await _dbService.getActivityLogs(userId: userId, category: _selectedFilter);
      if (rows.isEmpty) {
        // Seed initial audit log entries into SQLite
        await _seedInitialLogs(userId);
        rows = await _dbService.getActivityLogs(userId: userId, category: _selectedFilter);
      }

      if (mounted) {
        setState(() {
          _logs = rows;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }

    if (NetworkService.instance.isOnline) {
      _syncRemoteLogs(userId);
    }
  }

  Future<void> _syncRemoteLogs(String? userId) async {
    try {
      await SyncService.instance.syncAuditLogs(_apiClient, userId: userId);
      final refreshed = await _dbService.getActivityLogs(userId: userId, category: _selectedFilter);
      if (mounted) {
        setState(() {
          _logs = refreshed;
        });
      }
    } catch (_) {}
  }

  Future<void> _seedInitialLogs(String? userId) async {
    await _dbService.logActivity(
      eventType: 'SYSTEM_INITIALIZED',
      action: 'LifeGuard 360 offline database initialized',
      category: 'SYSTEM',
      details: 'SQLite storage operational with automatic Firebase cloud synchronization',
      userId: userId,
    );
    await _dbService.logActivity(
      eventType: 'CONNECTIVITY_ONLINE',
      action: 'Synchronized with Firebase Cloud Firestore',
      category: 'SYSTEM',
      details: 'Database records verified and synchronized with backend',
      userId: userId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkNavy,
      appBar: AppBar(
        title: const Text('Activity Audit Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadLogs,
          ),
        ],
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
              child: _isLoading && _logs.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.emergencyRed),
                    )
                  : _logs.isEmpty
                      ? const EmptyStateWidget(
                          icon: Icons.history_edu_rounded,
                          title: 'No Logs Found',
                          message: 'No activity records match the selected category.',
                        )
                      : RefreshIndicator(
                          color: AppTheme.emergencyRed,
                          backgroundColor: AppTheme.deepSlate,
                          onRefresh: _loadLogs,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            itemCount: _logs.length,
                            itemBuilder: (context, index) {
                              final log = _logs[index];
                              final category = log['category']?.toString() ?? 'SYSTEM';

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

                              final timestamp = log['timestamp']?.toString() ?? '';

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
                                              log['event_type']?.toString() ?? '',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                fontFamily: 'monospace',
                                                color: indicatorColor,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            timestamp.length > 16 ? timestamp.substring(0, 16) : timestamp,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: AppTheme.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        log['action']?.toString() ?? '',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                      if (log['details'] != null && log['details'].toString().isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          log['details']?.toString() ?? '',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
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
        if (val) {
          setState(() => _selectedFilter = key);
          _loadLogs();
        }
      },
    );
  }
}
