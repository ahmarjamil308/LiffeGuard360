import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/custom_button.dart';
import '../models/checkin_model.dart';
import '../providers/checkin_provider.dart';

/// Screen 5 of 16: Smart Check-In Screen.
/// Real-time scheduled check-in lifecycle, grace-period countdown, pre-alert sirens, and PIN verification.
class SmartCheckInScreen extends StatefulWidget {
  const SmartCheckInScreen({super.key});

  @override
  State<SmartCheckInScreen> createState() => _SmartCheckInScreenState();
}

class _SmartCheckInScreenState extends State<SmartCheckInScreen> {
  int _selectedIntervalMinutes = 30;
  int _gracePeriodMinutes = 10;
  int _preAlertSeconds = 20;
  final _destinationController = TextEditingController();
  final _pinController = TextEditingController();
  bool _requirePin = false;

  @override
  void dispose() {
    _destinationController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _showPinDialog(BuildContext context, CheckInProvider provider) {
    final pinInputController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.deepSlate,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.lock_rounded, color: AppTheme.cautionAmber),
            SizedBox(width: 8),
            Text('Safety PIN Required', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your 4-digit Safety PIN to confirm that you are safe and cancel escalation.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('checkin_pin_input'),
              controller: pinInputController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              style: const TextStyle(color: Colors.white, fontSize: 18, letterSpacing: 4),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.deepSlate,
                hintText: '••••',
                hintStyle: const TextStyle(color: Colors.white38),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            key: const Key('checkin_pin_confirm_submit'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.safeEmerald),
            onPressed: () async {
              final pin = pinInputController.text.trim();
              Navigator.of(dialogCtx).pop();
              await provider.confirmSafe(pin: pin);
            },
            child: const Text('Verify & Confirm Safe', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showCancelDialog(BuildContext context, CheckInProvider provider) {
    final pinInputController = TextEditingController();
    final hasPin = provider.activeCheckIn?.hasPin == true;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.deepSlate,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Scheduled Check-In?', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to cancel this scheduled check-in timer?',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            if (hasPin) ...[
              const SizedBox(height: 12),
              const Text('Enter PIN to authenticate cancellation:', style: TextStyle(color: AppTheme.cautionAmber, fontSize: 12)),
              const SizedBox(height: 8),
              TextField(
                controller: pinInputController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppTheme.deepSlate,
                  hintText: 'PIN',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Keep Active', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.emergencyRed),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              await provider.cancelActiveCheckIn(pin: hasPin ? pinInputController.text.trim() : null);
            },
            child: const Text('Cancel Check-In', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showPasswordUnlockDialog(BuildContext context, CheckInProvider provider) {
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.deepSlate,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.password_rounded, color: Colors.lightBlueAccent),
            SizedBox(width: 8),
            Text('Account Password Recovery', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your LifeGuard 360 account password to immediately unlock this check-in without waiting for the 15-minute cooldown.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('lockout_password_input'),
              controller: passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.deepSlate,
                hintText: 'Account Password',
                hintStyle: const TextStyle(color: Colors.white38),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            key: const Key('submit_password_unlock_button'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.lightBlueAccent),
            onPressed: () async {
              final pass = passwordController.text.trim();
              if (pass.isNotEmpty) {
                Navigator.of(dialogCtx).pop();
                await provider.recoverLockoutWithPassword(pass);
              }
            },
            child: const Text('Unlock', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }


  String _formatSeconds(int totalSeconds) {
    if (totalSeconds <= 0) return '00:00';
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<CheckInProvider>(context);
    final active = provider.activeCheckIn;
    final hasActive = provider.hasActiveCheckIn;

    return Scaffold(
      backgroundColor: AppTheme.darkNavy,
      appBar: AppBar(
        title: const Text('Smart Check-In'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Status',
            onPressed: () => provider.loadActiveCheckIn(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Notification status banners
              if (provider.statusMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.safeEmerald.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.safeEmerald),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: AppTheme.safeEmerald, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(provider.statusMessage!, style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (provider.errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.emergencyRed.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.emergencyRed),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppTheme.emergencyRed, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(provider.errorMessage!, style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Active Check-In Card
              if (hasActive && active != null) ...[
                _buildActiveCheckInCard(context, provider, active),
              ] else ...[
                _buildNoActiveCheckInCard(),
              ],

              const SizedBox(height: 16),

              // Schedule New Check-In Section
              _buildScheduleCard(context, provider),

              const SizedBox(height: 16),

              // Informational Guidance Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.shield_outlined, color: AppTheme.safeEmerald, size: 20),
                          SizedBox(width: 8),
                          Text('HOW SMART CHECK-IN PROTECTS YOU', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '1. Timer Countdown: LifeGuard 360 counts down until your scheduled safety check-in.\n'
                        '2. Grace Period: If not checked in on time, you enter a grace period (e.g., 10 minutes) with gentle reminders.\n'
                        '3. Pre-Alert Siren: A final 20-second audible warning sounds before alert transmission.\n'
                        '4. Escalation: If unconfirmed, an OVERDUE emergency is dispatched to your emergency contacts.',
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveCheckInCard(BuildContext context, CheckInProvider provider, CheckInModel active) {
    final state = active.evaluateState();
    Color headerColor;
    IconData headerIcon;
    String statusTitle;
    int displaySeconds;
    String subtext;

    if (state == 'SCHEDULED') {
      headerColor = AppTheme.safeEmerald;
      headerIcon = Icons.hourglass_top_rounded;
      statusTitle = 'UPCOMING CHECK-IN';
      displaySeconds = active.secondsToScheduled();
      subtext = 'Grace Period: ${active.gracePeriodMinutes} mins • Pre-Alert: ${active.preAlertSeconds}s';
    } else if (state == 'IN_GRACE_PERIOD') {
      headerColor = AppTheme.cautionAmber;
      headerIcon = Icons.warning_amber_rounded;
      statusTitle = 'IN GRACE PERIOD — CONFIRM NOW';
      displaySeconds = active.secondsRemainingInGrace();
      subtext = 'Scheduled time passed! Confirm safety before emergency escalation.';
    } else if (state == 'OVERDUE_PRE_ALERT') {
      headerColor = AppTheme.emergencyRed;
      headerIcon = Icons.crisis_alert_rounded;
      statusTitle = 'PRE-ALERT COUNTDOWN: ESCALATING SOON';
      displaySeconds = active.secondsRemainingInPreAlert();
      subtext = 'WARNING: Emergency dispatch to priority contacts starting in ${displaySeconds}s!';
    } else {
      headerColor = AppTheme.emergencyRed;
      headerIcon = Icons.notification_important_rounded;
      statusTitle = 'OVERDUE — ESCALATED TO CONTACTS';
      displaySeconds = 0;
      subtext = 'Emergency contacts have been notified. Confirm safe to disarm.';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(headerIcon, color: headerColor, size: 22),
                const SizedBox(width: 8),
                Text(
                  statusTitle,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: headerColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              _formatSeconds(displaySeconds),
              style: TextStyle(
                fontSize: 52,
                fontWeight: FontWeight.w900,
                color: headerColor,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              active.title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
            ),
            if (active.destinationNote != null && active.destinationNote!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Destination: ${active.destinationNote}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            ],
            const SizedBox(height: 6),
            Text(
              subtext,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: headerColor.withOpacity(0.9), fontWeight: FontWeight.w600),
            ),

            if (provider.isCancellationPendingSync) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.cautionAmber.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.cautionAmber),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.cloud_off_rounded, color: AppTheme.cautionAmber, size: 16),
                        SizedBox(width: 6),
                        Text('Cancellation Pending Server Sync', style: TextStyle(color: AppTheme.cautionAmber, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'You requested cancellation while offline. The LifeGuard 360 server cannot know this until this device reconnects.\n'
                      'WARNING: Server escalation remains active if the device remains offline past the deadline.',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 11, height: 1.3),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        key: const Key('retry_sync_cancellation_button'),
                        icon: const Icon(Icons.sync_rounded, size: 14, color: AppTheme.cautionAmber),
                        label: const Text('Retry Sync Now', style: TextStyle(color: AppTheme.cautionAmber, fontSize: 11)),
                        onPressed: () => provider.syncPendingCheckInOperations(),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (active.isLocked) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.emergencyRed.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.emergencyRed),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.lock_clock_rounded, color: AppTheme.emergencyRed, size: 16),
                        SizedBox(width: 6),
                        Text('PIN Lockout Active (15m Cooldown)', style: TextStyle(color: AppTheme.emergencyRed, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '5 consecutive incorrect PIN attempts. Direct PIN confirmation is temporarily blocked to protect against unauthorized disarming.',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      key: const Key('unlock_with_password_button'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.lightBlueAccent, visualDensity: VisualDensity.compact),
                      icon: const Icon(Icons.password_rounded, size: 14, color: Colors.black),
                      label: const Text('Unlock with Account Password', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: () => _showPasswordUnlockDialog(context, provider),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Confirmation Actions
            Row(
              children: [
                Expanded(
                  child: CustomButton(
                    key: const Key('checkin_safe_button'),
                    text: 'I Am Safe',
                    icon: Icons.check_circle_outline_rounded,
                    variant: ButtonVariant.safe,
                    isLoading: provider.isLoading,
                    onPressed: () {
                      if (active.hasPin) {
                        _showPinDialog(context, provider);
                      } else {
                        provider.confirmSafe();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CustomButton(
                    key: const Key('checkin_help_button'),
                    text: 'I Need Help',
                    icon: Icons.emergency_rounded,
                    variant: ButtonVariant.emergency,
                    onPressed: () => Navigator.of(context).pushNamed(AppRoutes.sosEmergency),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  key: const Key('extend_checkin_button'),
                  icon: const Icon(Icons.more_time_rounded, size: 16, color: Colors.lightBlueAccent),
                  label: const Text('Extend +15m', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 12)),
                  onPressed: () => provider.extendActiveCheckIn(additionalMinutes: 15),
                ),
                const SizedBox(width: 16),
                TextButton.icon(
                  key: const Key('cancel_checkin_button'),
                  icon: const Icon(Icons.cancel_outlined, size: 16, color: AppTheme.textSecondary),
                  label: const Text('Cancel Timer', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  onPressed: () => _showCancelDialog(context, provider),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoActiveCheckInCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Icon(Icons.check_circle_outline_rounded, size: 48, color: AppTheme.safeEmerald),
            const SizedBox(height: 12),
            const Text(
              'No Active Check-In Scheduled',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              'Set a timer below when walking home alone, meeting someone new, or traveling.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleCard(BuildContext context, CheckInProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Schedule New Check-In Timer',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 6),
            const Text('Choose expected duration before safety confirmation is required.', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            const SizedBox(height: 14),

            // Interval Choice Chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [15, 30, 60, 120].map((mins) {
                final isSelected = _selectedIntervalMinutes == mins;
                return ChoiceChip(
                  label: Text(mins < 60 ? '${mins}m' : '${mins ~/ 60}h'),
                  selected: isSelected,
                  selectedColor: AppTheme.emergencyRed,
                  backgroundColor: AppTheme.deepSlate,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _selectedIntervalMinutes = mins);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // Destination note
            TextField(
              controller: _destinationController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.deepSlate,
                hintText: 'Destination / Notes (e.g., Walking home from library)',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),

            // Require PIN checkbox & field
            Row(
              children: [
                Checkbox(
                  value: _requirePin,
                  activeColor: AppTheme.safeEmerald,
                  onChanged: (val) => setState(() => _requirePin = val ?? false),
                ),
                const Text('Require Safety PIN to Confirm / Cancel', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
            if (_requirePin) ...[
              TextField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                style: const TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 4),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppTheme.deepSlate,
                  hintText: 'Enter 4-6 digit Safety PIN',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 12, letterSpacing: 0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],

            const SizedBox(height: 14),
            CustomButton(
              key: const Key('start_checkin_timer_button'),
              text: 'Start Safety Check-In (${_selectedIntervalMinutes}m)',
              icon: Icons.alarm_add_rounded,
              variant: ButtonVariant.safe,
              isLoading: provider.isLoading,
              onPressed: () async {
                final now = DateTime.now().toUtc();
                final sched = now.add(Duration(minutes: _selectedIntervalMinutes));
                await provider.scheduleCheckIn(
                  title: _destinationController.text.trim().isNotEmpty
                      ? _destinationController.text.trim()
                      : 'Routine Check-In (${_selectedIntervalMinutes}m)',
                  destinationNote: _destinationController.text.trim(),
                  scheduledFor: sched,
                  gracePeriodMinutes: _gracePeriodMinutes,
                  preAlertSeconds: _preAlertSeconds,
                  pin: _requirePin ? _pinController.text.trim() : null,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
