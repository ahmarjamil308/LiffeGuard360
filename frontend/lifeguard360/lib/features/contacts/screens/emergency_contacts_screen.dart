import 'package:flutter/material.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../models/emergency_contact_model.dart';

/// Screen 9 of 16: Emergency Contacts Screen.
/// Manage prioritized circle of trusted responders receiving SMS and Push alerts.
class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  final _apiClient = ApiClient(secureStorage: SecureStorageService());
  List<EmergencyContactModel> _contacts = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _apiClient.get(ApiConstants.contacts);
      if (response.statusCode == 200 && response.data != null) {
        final raw = response.data as Map<String, dynamic>;
        final data = (raw['data'] is Map<String, dynamic>)
            ? raw['data'] as Map<String, dynamic>
            : raw;
        final rawContacts = (data['contacts'] as List<dynamic>?) ?? [];
        if (mounted) {
          setState(() {
            _contacts = rawContacts
                .map((item) => EmergencyContactModel.fromJson(item as Map<String, dynamic>))
                .toList();
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
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

    if (confirmed == true && contact.id != null) {
      try {
        await _apiClient.delete(ApiConstants.contactDetail(contact.id!));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${contact.contactName} removed from emergency contacts'),
              backgroundColor: AppTheme.emergencyRed,
            ),
          );
        }
        await _loadContacts();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete contact: $e'),
              backgroundColor: AppTheme.emergencyRed,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkNavy,
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
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
        child: _isLoading
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
                : ListView.builder(
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
                                        Text(
                                          contact.contactName,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.textPrimary,
                                          ),
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
    );
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
