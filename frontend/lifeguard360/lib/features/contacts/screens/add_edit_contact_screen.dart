import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/database/database_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_service.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/custom_button.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/emergency_contact_model.dart';

/// Screen 10 of 16: Add / Edit Contact Screen.
/// Form for adding or editing a trusted emergency contact with offline persistence & Firebase sync.
class AddEditContactScreen extends StatefulWidget {
  final EmergencyContactModel? contactToEdit;
  final ApiClient? apiClient;
  final DatabaseService? databaseService;

  const AddEditContactScreen({
    super.key,
    this.contactToEdit,
    this.apiClient,
    this.databaseService,
  });

  @override
  State<AddEditContactScreen> createState() => _AddEditContactScreenState();
}

class _AddEditContactScreenState extends State<AddEditContactScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late String _relationship;
  late int _priorityOrder;
  late bool _notifySms;
  late bool _notifyPush;
  bool _isLoading = false;
  late final ApiClient _apiClient;
  late final DatabaseService _dbService;

  final List<String> _relationships = [
    'Spouse',
    'Parent',
    'Child',
    'Sibling',
    'Friend',
    'Colleague',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? ApiClient(secureStorage: SecureStorageService());
    _dbService = widget.databaseService ?? DatabaseService.instance;

    final c = widget.contactToEdit;
    _nameController = TextEditingController(text: c?.contactName ?? '');
    _phoneController = TextEditingController(text: c?.phoneNumber ?? '');
    _emailController = TextEditingController(text: c?.email ?? '');
    _relationship = c?.relationship ?? 'Parent';
    _priorityOrder = c?.priorityOrder ?? 1;
    _notifySms = c?.notifySms ?? true;
    _notifyPush = c?.notifyPush ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _saveContact() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.currentUser?.id.toString();
    final isOnline = NetworkService.instance.isOnline;
    final isEditing = widget.contactToEdit != null;

    final clientUuid = widget.contactToEdit?.clientUuid ??
        (widget.contactToEdit?.id != null ? 'server_${widget.contactToEdit!.id}' : DatabaseService.generateUuid());
    final serverId = widget.contactToEdit?.id;

    final payload = {
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'email': _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
      'relationship': _relationship,
      'priority_tier': _priorityOrder,
      'notify_sms': _notifySms,
      'notify_push': _notifyPush,
    };

    // 1. Always save to local SQLite database first
    final sqliteRow = {
      if (serverId != null) 'server_id': serverId,
      'client_uuid': clientUuid,
      if (userId != null) 'user_id': userId,
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'email': _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
      'relationship': _relationship,
      'priority_tier': _priorityOrder,
      'notify_sms': _notifySms ? 1 : 0,
      'notify_push': _notifyPush ? 1 : 0,
      'notify_call': 0,
      'is_active': 1,
      'sync_status': isOnline ? 'synced' : 'pending',
      'sync_operation': isEditing ? 'UPDATE' : 'CREATE',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    await _dbService.saveContact(sqliteRow);

    // 2. If online, attempt synchronization with Firebase / Backend
    int? confirmedServerId = serverId;
    bool syncSucceeded = false;

    if (isOnline) {
      try {
        if (isEditing && serverId != null) {
          final res = await _apiClient.put(
            ApiConstants.contactDetail(serverId),
            data: payload,
          );
          if (res.statusCode == 200) {
            syncSucceeded = true;
            await _dbService.markContactSynced(clientUuid, serverId);
          }
        } else {
          final res = await _apiClient.post(
            ApiConstants.contacts,
            data: payload,
          );
          if (res.statusCode == 201 && res.data != null) {
            final raw = res.data as Map<String, dynamic>;
            final data = (raw['data'] is Map<String, dynamic>)
                ? raw['data'] as Map<String, dynamic>
                : raw;
            final created = data['contact'] as Map<String, dynamic>?;
            confirmedServerId = created?['id'] as int?;
            if (confirmedServerId != null) {
              syncSucceeded = true;
              await _dbService.markContactSynced(clientUuid, confirmedServerId);
            }
          }
        }
      } catch (_) {
        // Network drop during call: mark as pending in SQLite for future automatic retry
        await _dbService.saveContact({
          ...sqliteRow,
          'sync_status': 'pending',
        });
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
      final message = syncSucceeded
          ? 'Emergency contact ${_nameController.text.trim()} saved & synced with Firebase.'
          : 'Emergency contact ${_nameController.text.trim()} saved locally. Will sync with Firebase when online.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: syncSucceeded ? AppTheme.safeEmerald : Colors.amber.shade800,
        ),
      );
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.contactToEdit != null;

    return Scaffold(
      backgroundColor: AppTheme.darkNavy,
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Contact' : 'Add Emergency Contact'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Name
                TextFormField(
                  key: const Key('contact_name_field'),
                  controller: _nameController,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Contact Full Name',
                    prefixIcon: Icon(Icons.person_outline, color: AppTheme.textSecondary),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Contact name is required';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Phone
                TextFormField(
                  key: const Key('contact_phone_field'),
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Phone Number (E.164 Format)',
                    hintText: '+14155552671',
                    prefixIcon: Icon(Icons.phone_outlined, color: AppTheme.textSecondary),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Phone number is required';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Relationship Dropdown
                DropdownButtonFormField<String>(
                  value: _relationship,
                  dropdownColor: AppTheme.deepSlate,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Relationship',
                    prefixIcon: Icon(Icons.group_outlined, color: AppTheme.textSecondary),
                  ),
                  items: _relationships.map((rel) {
                    return DropdownMenuItem(value: rel, child: Text(rel));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _relationship = val);
                  },
                ),
                const SizedBox(height: 14),

                // Priority Order Dropdown
                DropdownButtonFormField<int>(
                  value: _priorityOrder,
                  dropdownColor: AppTheme.deepSlate,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Alert Priority (1 = First Responder)',
                    prefixIcon: Icon(Icons.format_list_numbered, color: AppTheme.textSecondary),
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('Priority #1 (Primary Immediate)')),
                    DropdownMenuItem(value: 2, child: Text('Priority #2 (Secondary Responder)')),
                    DropdownMenuItem(value: 3, child: Text('Priority #3 (Guardian / Authority)')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _priorityOrder = val);
                  },
                ),
                const SizedBox(height: 14),

                // Optional Email
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Email Address (Optional)',
                    prefixIcon: Icon(Icons.email_outlined, color: AppTheme.textSecondary),
                  ),
                ),
                const SizedBox(height: 20),

                // Channels Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Notification Dispatch Channels',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Send SMS Distress Alerts',
                              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                          value: _notifySms,
                          activeColor: AppTheme.safeEmerald,
                          onChanged: (val) => setState(() => _notifySms = val),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Send Push Notifications',
                              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                          value: _notifyPush,
                          activeColor: AppTheme.safeEmerald,
                          onChanged: (val) => setState(() => _notifyPush = val),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                CustomButton(
                  key: const Key('save_contact_button'),
                  text: isEditing ? 'Update Contact' : 'Save Emergency Contact',
                  isLoading: _isLoading,
                  onPressed: _saveContact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
