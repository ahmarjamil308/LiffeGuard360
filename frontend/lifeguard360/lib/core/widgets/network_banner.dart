import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Persistent or conditional offline status warning banner.
class NetworkUnavailableBanner extends StatelessWidget {
  final int pendingCount;
  final VoidCallback? onSyncNow;
  final bool isSyncing;

  const NetworkUnavailableBanner({
    super.key,
    this.pendingCount = 0,
    this.onSyncNow,
    this.isSyncing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppTheme.cautionAmber.withOpacity(0.18),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            color: AppTheme.cautionAmber,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Offline Mode Active',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppTheme.cautionAmber,
                  ),
                ),
                Text(
                  pendingCount > 0
                      ? '$pendingCount incident(s) queued locally'
                      : 'Local monitoring & siren available',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (onSyncNow != null && pendingCount > 0)
            isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(AppTheme.cautionAmber),
                    ),
                  )
                : TextButton(
                    onPressed: onSyncNow,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.cautionAmber,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text(
                      'Sync Now',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
        ],
      ),
    );
  }
}
