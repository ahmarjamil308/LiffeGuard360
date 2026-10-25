import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/custom_button.dart';
import '../../sos/providers/sos_provider.dart';

/// Screen 16 of 16: Emergency Response Details Screen.
/// Detailed response dispatch tracker, responder acknowledgment receipts, and disarm action.
class EmergencyResponseDetailsScreen extends StatefulWidget {
  const EmergencyResponseDetailsScreen({super.key});

  @override
  State<EmergencyResponseDetailsScreen> createState() => _EmergencyResponseDetailsScreenState();
}

class _EmergencyResponseDetailsScreenState extends State<EmergencyResponseDetailsScreen> {
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _showCancelDialog() {
    _pinController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.deepSlate,
        title: const Text('Confirm Incident Resolution', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter 4-digit Safety PIN to verify incident cancellation and notify responders.',
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
    final active = sos.activeIncident;

    return Scaffold(
      backgroundColor: AppTheme.darkNavy,
      appBar: AppBar(
        title: const Text('Emergency Response Details'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Incident Status Card
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
                            'INCIDENT STATUS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.emergencyRed.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppTheme.emergencyRed),
                            ),
                            child: Text(
                              active?.status ?? AppConstants.statusQueuedOffline,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.emergencyRed,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Trigger: ${active?.triggerSource ?? "MANUAL_BUTTON"}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Client UUID: ${active?.clientIncidentUuid ?? "Local-Pending"}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Dispatch Pipeline Progress
              const Text(
                'DISPATCH PIPELINE PROGRESS',
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
                      _buildPipelineStep(
                        title: '1. Incident Committed Locally',
                        subtitle: sos.isPersistedLocally
                            ? 'Local-first timestamp recorded on durable storage'
                            : 'Incident active in memory (durable storage pending)',
                        isCompleted: true,
                        isActive: false,
                      ),
                      _buildPipelineStep(
                        title: '2. Server Accepted & Outbox Enqueued',
                        subtitle: active?.isServerAccepted == true
                            ? 'Backend registered incident and outbox records created'
                            : (active?.isLocallyQueued == true
                                ? 'Awaiting network connection to reach backend server'
                                : 'Connecting to backend...'),
                        isCompleted: active?.isServerAccepted == true,
                        isActive: active?.isLocallyQueued == true,
                      ),
                      _buildPipelineStep(
                        title: '3. Gateway Dispatched',
                        subtitle: active?.isGatewayAccepted == true
                            ? 'Twilio SMS & FCM Push delivered to gateway'
                            : 'Pending carrier transmission handoff',
                        isCompleted: active?.isGatewayAccepted == true,
                        isActive: active?.isServerAccepted == true && active?.isGatewayAccepted != true,
                      ),
                      _buildPipelineStep(
                        title: '4. Delivered to Handset',
                        subtitle: active?.isDelivered == true
                            ? 'Carrier delivery receipt (DLR) confirmed by SMS provider'
                            : 'Awaiting carrier delivery receipt (FCM push pending receipt)',
                        isCompleted: active?.isDelivered == true,
                        isActive: active?.isGatewayAccepted == true && active?.isDelivered != true,
                      ),
                      _buildPipelineStep(
                        title: '5. Link Viewed by Responder',
                        subtitle: active?.isViewed == true
                            ? 'Contact opened emergency portal link (viewed only)'
                            : 'Awaiting responder link visit',
                        isCompleted: active?.isViewed == true,
                        isActive: active?.isDelivered == true && active?.isViewed != true,
                      ),
                      _buildPipelineStep(
                        title: '6. Responder Confirmed Assistance',
                        subtitle: active?.isAcknowledged == true
                            ? 'Contact explicitly clicked "Acknowledge" and verified help'
                            : 'Awaiting explicit responder assistance confirmation',
                        isCompleted: active?.isAcknowledged == true,
                        isActive: active?.isViewed == true && active?.isAcknowledged != true,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Responder Acknowledgment Log Card
              const Text(
                'RESPONDER DISPATCH & DELIVERY STATUS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 10),

              if (active?.dispatches != null && active!.dispatches!.isNotEmpty)
                ...active.dispatches!.map((d) {
                  final map = d is Map<String, dynamic> ? d : <String, dynamic>{};
                  final status = map['status'] as String? ?? 'QUEUED';
                  final channel = map['channel'] as String? ?? 'SMS';
                  final contactName = map['contact_name'] as String? ?? 'Contact';
                  final isDeliv = status == 'DELIVERED' || status == 'ACKNOWLEDGED';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8.0),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: isDeliv ? AppTheme.safeEmeraldLight : AppTheme.cautionAmberLight,
                            child: Icon(
                              isDeliv ? Icons.verified_user_rounded : Icons.outbox_rounded,
                              color: isDeliv ? AppTheme.safeEmeraldDark : AppTheme.cautionAmberDark,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$contactName ($channel)',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Status: $status',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDeliv ? AppTheme.safeEmerald : AppTheme.cautionAmber,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                })
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Row(
                      children: [
                        Icon(
                          active?.isLocallyQueued == true ? Icons.cloud_off_rounded : Icons.info_outline_rounded,
                          color: AppTheme.cautionAmber,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            active?.isLocallyQueued == true
                                ? 'Alert stored locally in offline outbox. Contacts will be dispatched as soon as device reconnects.'
                                : 'No carrier dispatch receipts recorded yet.',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),

              CustomButton(
                key: const Key('resolve_incident_button'),
                text: 'Resolve / Disarm Incident',
                icon: Icons.check_circle_outline_rounded,
                variant: ButtonVariant.safe,
                onPressed: _showCancelDialog,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPipelineStep({
    required String title,
    required String subtitle,
    required bool isCompleted,
    required bool isActive,
  }) {
    Color color;
    IconData icon;
    if (isCompleted) {
      color = AppTheme.safeEmerald;
      icon = Icons.check_circle_rounded;
    } else if (isActive) {
      color = AppTheme.cautionAmber;
      icon = Icons.radio_button_checked_rounded;
    } else {
      color = AppTheme.textMuted;
      icon = Icons.radio_button_off_rounded;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isCompleted || isActive ? AppTheme.textPrimary : AppTheme.textMuted,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
