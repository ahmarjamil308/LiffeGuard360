import 'package:flutter/material.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/custom_button.dart';
import '../models/emergency_contact_model.dart';

/// Screen 10 of 16: Add / Edit Contact Screen.
/// Form for adding or editing a trusted emergency contact with notification channels.
class AddEditContactScreen extends StatefulWidget {
  final EmergencyContactModel? contactToEdit;

  const AddEditContactScreen({super.key, this.contactToEdit});

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

  final _apiClient = ApiClient(secureStorage: SecureStorageService());

  Future<void> _saveContact() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final payload = {
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'email': _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
        'relationship': _relationship,
        'priority_tier': _priorityOrder,
        'notify_sms': _notifySms,
        'notify_push': _notifyPush,
      };

      final isEditing = widget.contactToEdit != null;
      if (isEditing && widget.contactToEdit!.id != null) {
        await _apiClient.put(
          ApiConstants.contactDetail(widget.contactToEdit!.id!),
          data: payload,
        );
      } else {
        await _apiClient.post(
          ApiConstants.contacts,
          data: payload,
        );
      }

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Emergency contact ${_nameController.text.trim()} saved successfully'),
            backgroundColor: AppTheme.safeEmerald,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save contact: $e'),
            backgroundColor: AppTheme.emergencyRed,
          ),
        );
      }
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
                          title: const Text('Send SMS Distres Alerts',
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
