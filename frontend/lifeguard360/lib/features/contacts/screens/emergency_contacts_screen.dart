import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/database/database_service.dart';
import '../../../core/database/sync_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_service.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/emergency_contact_model.dart';

/// Screen 9 of 16: Emergency Contacts Screen.
/// Supports offline viewing, adding, editing, deleting, and automatic Firebase synchronization.
class EmergencyContactsScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final DatabaseService? databaseService;

  const EmergencyContactsScreen({
    super.key,
    this.apiClient,
    this.databaseService,
  });

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  late final ApiClient _apiClient;
  late final DatabaseService _dbService;
  List<EmergencyContactModel> _contacts = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? ApiClient(secureStorage: SecureStorageService());
    _dbService = widget.databaseService ?? DatabaseService.instance;
    _loadContacts();
  }

  /// Loads contacts: instantly loads from SQLite, then synchronizes if online.
  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.currentUser?.id.toString();

    // 1. Instant local read from SQLite
    try {
      final localRows = await _dbService.getContacts(userId: userId);
      final localContacts = localRows.map((r) => EmergencyContactModel.fromSqlite(r)).toList();
      if (mounted) {
        setState(() {
          _contacts = localContacts;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }

    // 2. If online, trigger background synchronization with Firebase/Backend
    final isOnline = NetworkService.instance.isOnline;
    if (isOnline) {
      _triggerBackgroundSync(userId);
    }
  }

  Future<void> _triggerBackgroundSync(String? userId) async {
    if (_isSyncing) return;
    if (mounted) setState(() => _isSyncing = true);

    try {
      await SyncService.instance.syncContacts(_apiClient, userId: userId);
      // Reload fresh SQLite data after synchronization
      final updatedRows = await _dbService.getContacts(userId: userId);
      if (mounted) {
        setState(() {
          _contacts = updatedRows.map((r) => EmergencyContactModel.fromSqlite(r)).toList();
          _isSyncing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _deleteContact(EmergencyContactModel contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.deepSlate,
        title: const Text('Delete Contact', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Are you sure you want to remove ${contact.contactName} from your emergency contacts?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.emergencyRed),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final clientUuid = contact.clientUuid ?? 'client_${contact.id}';
      
      // Remove locally from SQLite immediately (soft delete for sync or hard delete if draft)
      await _dbService.deleteContactLocally(clientUuid);

      // If online, perform immediate server & Firebase deletion
      if (NetworkService.instance.isOnline && contact.id != null) {
        try {
          await _apiClient.delete(ApiConstants.contactDetail(contact.id!));
          await _dbService.purgeDeletedContact(clientUuid);
        } catch (_) {
          // If network drop occurred during delete, it remains flagged for sync
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${contact.contactName} removed from emergency contacts'),
            backgroundColor: AppTheme.emergencyRed,
          ),
        );
      }

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.currentUser?.id.toString();
      final updatedRows = await _dbService.getContacts(userId: userId);
      if (mounted) {
        setState(() {
          _contacts = updatedRows.map((r) => EmergencyContactModel.fromSqlite(r)).toList();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = NetworkService.instance.isOnline;

    return Scaffold(
      backgroundColor: AppTheme.darkNavy,
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
        actions: [
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.safeEmerald),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync_rounded),
              tooltip: 'Sync Contacts',
              onPressed: _loadContacts,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.emergencyRed,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Contact', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () async {
          final result = await Navigator.of(context).pushNamed(AppRoutes.addEditContact);
          if (result == true) {
            _loadContacts();
          }
        },
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Connectivity & Offline Banner
            if (!isOnline)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.amber.shade900.withOpacity(0.9),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Offline Mode: Contacts saved locally and sync automatically when connected.',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: _isLoading && _contacts.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.emergencyRed),
                    )
                  : _contacts.isEmpty
                      ? EmptyStateWidget(
                          icon: Icons.contact_emergency_rounded,
                          title: 'No Emergency Contacts Added',
                          message:
                              'Add at least one trusted contact to receive automated distress alerts, SMS dispatches, and cloud backup.',
                          actionButtonText: 'Add First Contact',
                          onAction: () async {
                            final result = await Navigator.of(context).pushNamed(AppRoutes.addEditContact);
                            if (result == true) {
                              _loadContacts();
                            }
                          },
                        )
                      : RefreshIndicator(
                          color: AppTheme.emergencyRed,
                          backgroundColor: AppTheme.deepSlate,
                          onRefresh: _loadContacts,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                            itemCount: _contacts.length,
                            itemBuilder: (context, index) {
                              final contact = _contacts[index];
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(14.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor: AppTheme.emergencyRed.withOpacity(0.15),
                                            child: Text(
                                              '#${contact.priorityOrder}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.emergencyRed,
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
                                                        contact.contactName,
                                                        style: const TextStyle(
                                                          fontSize: 15,
                                                          fontWeight: FontWeight.w700,
                                                          color: AppTheme.textPrimary,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    _buildSyncBadge(contact),
                                                  ],
                                                ),
                                                Text(
                                                  '${contact.relationship} • ${contact.phoneNumber}',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: AppTheme.textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, color: AppTheme.textMuted, size: 20),
                                            onPressed: () async {
                                              final result = await Navigator.of(context).pushNamed(
                                                AppRoutes.addEditContact,
                                                arguments: contact,
                                              );
                                              if (result == true) {
                                                _loadContacts();
                                              }
                                            },
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.emergencyRed, size: 20),
                                            onPressed: () => _deleteContact(contact),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          _buildChannelChip('SMS Dispatch', contact.notifySms),
                                          const SizedBox(width: 8),
                                          _buildChannelChip('Push Notification', contact.notifyPush),
                                        ],
                                      ),
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

  Widget _buildSyncBadge(EmergencyContactModel contact) {
    if (contact.isPendingSync) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.amber.shade900.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.amber, width: 0.5),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, size: 10, color: Colors.amber),
            SizedBox(width: 3),
            Text('Pending Sync', style: TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    } else if (contact.isSyncFailed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.emergencyRed.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppTheme.emergencyRed, width: 0.5),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 10, color: AppTheme.emergencyRed),
            SizedBox(width: 3),
            Text('Sync Failed', style: TextStyle(color: AppTheme.emergencyRed, fontSize: 9, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.safeEmerald.withOpacity(0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppTheme.safeEmerald, width: 0.5),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_done_rounded, size: 10, color: AppTheme.safeEmerald),
            SizedBox(width: 3),
            Text('Synced', style: TextStyle(color: AppTheme.safeEmeraldLight, fontSize: 9, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
  }

  Widget _buildChannelChip(String label, bool isEnabled) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isEnabled
            ? AppTheme.safeEmerald.withOpacity(0.15)
            : AppTheme.slateBorder.withOpacity(0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isEnabled ? AppTheme.safeEmerald : AppTheme.slateBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isEnabled ? Icons.check_circle_rounded : Icons.cancel_outlined,
            size: 12,
            color: isEnabled ? AppTheme.safeEmerald : AppTheme.textMuted,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isEnabled ? AppTheme.safeEmeraldLight : AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
