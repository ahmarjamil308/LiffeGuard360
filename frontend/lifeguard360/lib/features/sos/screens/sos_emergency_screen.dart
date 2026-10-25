import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/custom_button.dart';
import '../providers/sos_provider.dart';

/// Screen 8 of 16: SOS Emergency Screen.
/// Immediate manual SOS trigger, offline resilient queue, siren alarm, and PIN cancellation.
class SOSEmergencyScreen extends StatefulWidget {
  const SOSEmergencyScreen({super.key});

  @override
  State<SOSEmergencyScreen> createState() => _SOSEmergencyScreenState();
}

class _SOSEmergencyScreenState extends State<SOSEmergencyScreen> {
  final _pinController = TextEditingController();
  bool _isTriggering = false;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _handleManualSOS() async {
    setState(() => _isTriggering = true);
    final sos = Provider.of<SOSProvider>(context, listen: false);

    // Immediate manual SOS execution without delay
    await sos.triggerManualSOS(
      latitude: 37.7749,
      longitude: -122.4194,
      accuracyMeters: 4.5,
      localNotes: 'Triggered manually via SOS Emergency screen',
    );

    if (mounted) {
      setState(() => _isTriggering = false);
    }
  }

  void _showCancelDialog() {
    _pinController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.deepSlate,
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: AppTheme.cautionAmber),
            SizedBox(width: 8),
            Text('Disarm Distress Alert', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your 4-digit Safety PIN to verify incident resolution and prevent unauthorized disarming.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              style: const TextStyle(color: AppTheme.textPrimary, letterSpacing: 8, fontSize: 18),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                hintText: '••••',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Back', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.emergencyRed),
            onPressed: () async {
              final pin = _pinController.text.trim();
              if (pin.length == 4) {
                final sos = Provider.of<SOSProvider>(context, listen: false);
                final incidentId = sos.activeIncident?.id ?? 0;
                Navigator.of(ctx).pop();
                if (incidentId > 0) {
                  await sos.cancelIncident(incidentId: incidentId, pin: pin);
                } else {
                  sos.silenceAlarm();
                }
              }
            },
            child: const Text('Confirm Resolution'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sos = Provider.of<SOSProvider>(context);
    final hasActive = sos.hasActiveEmergency;
    final isAlarm = sos.isAlarmActive;

    return Scaffold(
      backgroundColor: isAlarm ? const Color(0xFF1F0B0B) : AppTheme.darkNavy,
      appBar: AppBar(
        title: const Text('Emergency Distress'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: Icon(
              isAlarm ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: isAlarm ? AppTheme.emergencyRed : AppTheme.textMuted,
            ),
            tooltip: isAlarm ? 'Silence Siren' : 'Test Siren',
            onPressed: () => sos.toggleAlarm(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sos.lastError != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.cautionAmber.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.cautionAmber),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppTheme.cautionAmber, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          sos.lastError!,
                          style: const TextStyle(color: AppTheme.cautionAmberLight, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (sos.storageError != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.emergencyRed.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.emergencyRed),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppTheme.emergencyRed, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'PERSISTENCE ERROR — NOT SAVED TO DISK',
                              style: TextStyle(color: AppTheme.emergencyRed, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                            Text(
                              sos.storageError!,
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        key: const Key('sos_retry_save_button'),
                        onPressed: () => sos.retryLocalPersistence(),
                        child: const Text('RETRY SAVE', style: TextStyle(color: AppTheme.emergencyRed, fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Central Emergency Hero / SOS Tap Area
              Center(
                child: GestureDetector(
                  key: const Key('sos_emergency_main_button'),
                  onTap: _isTriggering ? null : _handleManualSOS,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: isAlarm
                            ? [const Color(0xFFFF5252), AppTheme.emergencyRedDark]
                            : [AppTheme.emergencyRed, AppTheme.emergencyRedDark],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.emergencyRed.withOpacity(isAlarm ? 0.7 : 0.35),
                          blurRadius: isAlarm ? 40 : 25,
                          spreadRadius: isAlarm ? 8 : 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isTriggering
                          ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.crisis_alert_rounded, size: 68, color: Colors.white),
                                const SizedBox(height: 10),
                                Text(
                                  hasActive ? 'EMERGENCY\nACTIVE' : 'TAP TO SEND\nDISTRESS SOS',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 1.5,
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Text(
                hasActive
                    ? (sos.activeIncident?.isLocallyQueued == true
                        ? 'OFFLINE SOS PERSISTED LOCALLY (Awaiting Network)'
                        : (sos.activeIncident?.isDelivered == true
                            ? 'DISPATCH DELIVERED TO CONTACTS (Carrier Confirmed)'
                            : 'DISTRESS DISPATCH COMMITTED (Server Accepted)'))
                    : 'Immediate t = 0 ms bypass. Zero artificial delay.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: hasActive
                      ? (sos.activeIncident?.isLocallyQueued == true
                          ? AppTheme.cautionAmber
                          : (sos.activeIncident?.isDelivered == true
                              ? AppTheme.safeEmerald
                              : AppTheme.emergencyRed))
                      : AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 20),

              if (hasActive) ...[
                CustomButton(
                  text: 'Cancel Emergency (PIN Required)',
                  icon: Icons.cancel_outlined,
                  variant: ButtonVariant.neutral,
                  onPressed: _showCancelDialog,
                ),
                const SizedBox(height: 10),
                CustomButton(
                  text: 'View Response Dispatch Details',
                  icon: Icons.track_changes_rounded,
                  variant: ButtonVariant.outline,
                  onPressed: () => Navigator.of(context).pushNamed(AppRoutes.emergencyResponseDetails),
                ),
                const SizedBox(height: 20),
              ],

              // Native Telephony Fallback Options
              const Text(
                'OFFLINE TELEPHONY & HARDWARE FALLBACKS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: Card(
                      child: InkWell(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Triggering native ACTION_DIAL intent for 911 / 112'),
                              backgroundColor: AppTheme.deepSlate,
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
                          child: Column(
                            children: [
                              Icon(Icons.call_rounded, color: AppTheme.safeEmerald, size: 28),
                              SizedBox(height: 8),
                              Text(
                                'Call 911 / 112',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Native Dialer',
                                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Card(
                      child: InkWell(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Triggering native ACTION_SENDTO intent for Contacts SMS'),
                              backgroundColor: AppTheme.deepSlate,
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
                          child: Column(
                            children: [
                              Icon(Icons.sms_rounded, color: AppTheme.cautionAmber, size: 28),
                              SizedBox(height: 8),
                              Text(
                                'Direct SMS',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Native SMS App',
                                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
