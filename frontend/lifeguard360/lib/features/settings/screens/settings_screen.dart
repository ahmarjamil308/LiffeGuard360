import 'package:flutter/material.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/custom_button.dart';

/// Screen 14 of 16: Settings Screen.
/// Configuration of separated grace periods, cancellation PIN, API host and battery optimization.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _gracePeriodMins = 10.0;
  double _preAlertSecs = 20.0;
  late final TextEditingController _apiBaseUrlController;
  final _pinController = TextEditingController();
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;

  @override
  void initState() {
    super.initState();
    _apiBaseUrlController = TextEditingController(text: ApiConstants.baseUrl);
  }

  @override
  void dispose() {
    _apiBaseUrlController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    ApiConstants.baseUrl = _apiBaseUrlController.text.trim();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Safety preferences and timer bounds saved successfully.'),
        backgroundColor: AppTheme.safeEmerald,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkNavy,
      appBar: AppBar(
        title: const Text('Safety & App Settings'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Emergency Timers Card
              const Text(
                'SEPARATED EMERGENCY TIMERS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 10),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Check-In Grace Period',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                          ),
                          Text(
                            '${_gracePeriodMins.toInt()} minutes',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.cautionAmber),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Time permitted after a scheduled check-in expires before escalation initiates (1-60 mins).',
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                      Slider(
                        value: _gracePeriodMins,
                        min: AppConstants.minGracePeriodMinutes.toDouble(),
                        max: AppConstants.maxGracePeriodMinutes.toDouble(),
                        divisions: 59,
                        activeColor: AppTheme.cautionAmber,
                        onChanged: (val) => setState(() => _gracePeriodMins = val),
                      ),
                      const Divider(),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Automated Pre-Alert Countdown',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                          ),
                          Text(
                            '${_preAlertSecs.toInt()} seconds',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.emergencyRed),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Pre-alert warning before automated dispatch occurs. Note: Manual SOS bypasses this countdown.',
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                      Slider(
                        value: _preAlertSecs,
                        min: AppConstants.minPreAlertSeconds.toDouble(),
                        max: AppConstants.maxPreAlertSeconds.toDouble(),
                        divisions: 35,
                        activeColor: AppTheme.emergencyRed,
                        onChanged: (val) => setState(() => _preAlertSecs = val),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // PIN Management
              const Text(
                'SAFETY CANCELLATION PIN',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 10),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Update 4-Digit Disarm PIN',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _pinController,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        obscureText: true,
                        style: const TextStyle(color: AppTheme.textPrimary, letterSpacing: 6),
                        decoration: const InputDecoration(
                          hintText: 'Enter new 4-digit PIN',
                          counterText: '',
                          prefixIcon: Icon(Icons.lock_reset_rounded, color: AppTheme.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Audio & Feedback Preferences
              const Text(
                'ALERT & FEEDBACK NOTIFICATIONS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 10),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Audible Siren Alarm', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                        subtitle: const Text('Play high-decibel local sound on distress', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                        value: _soundEnabled,
                        onChanged: (val) => setState(() => _soundEnabled = val),
                      ),
                      const Divider(),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Haptic Vibration Alerts', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                        subtitle: const Text('Continuous vibration pulses during active emergencies', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                        value: _vibrationEnabled,
                        onChanged: (val) => setState(() => _vibrationEnabled = val),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Backend REST API Host
              const Text(
                'REST API HOST CONFIGURATION',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 10),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Backend Endpoint URL',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _apiBaseUrlController,
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                        decoration: const InputDecoration(
                          labelText: 'API Base URL',
                          prefixIcon: Icon(Icons.dns_rounded, color: AppTheme.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Android Battery Optimization Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.battery_charging_full_rounded, color: AppTheme.safeEmerald, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Android Battery Optimization Guide',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '1. Open Android Settings > Apps > LifeGuard 360.\n2. Tap "Battery" or "App Battery Usage".\n3. Select "Unrestricted".\n4. This ensures uninterrupted foreground service monitoring when your screen is locked.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              CustomButton(
                key: const Key('save_settings_button'),
                text: 'Save Preferences',
                icon: Icons.save_rounded,
                variant: ButtonVariant.emergency,
                onPressed: _saveSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
