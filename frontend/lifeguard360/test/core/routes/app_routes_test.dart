import 'package:flutter_test/flutter_test.dart';
import 'package:lifeguard360/core/routes/app_routes.dart';

void main() {
  group('AppRoutes 16-Screen Inventory Specification', () {
    test('routes map must contain EXACTLY 16 registered screens with 0 onboarding screens', () {
      expect(AppRoutes.routes.length, equals(16),
          reason: 'Scope invariant: Exactly 16 screens, no onboarding screens, no extra 17th battery screen.');
    });

    test('initial route must be AppRoutes.splash', () {
      expect(AppRoutes.initialRoute, equals('/splash'));
    });

    test('all 16 approved screen routes are present in the registry', () {
      final expectedRoutes = <String>[
        AppRoutes.splash,
        AppRoutes.login,
        AppRoutes.register,
        AppRoutes.dashboard,
        AppRoutes.smartCheckIn,
        AppRoutes.monitoringStatus,
        AppRoutes.riskAnalysis,
        AppRoutes.sosEmergency,
        AppRoutes.emergencyContacts,
        AppRoutes.addEditContact,
        AppRoutes.liveLocation,
        AppRoutes.alertsNotifications,
        AppRoutes.activityLogs,
        AppRoutes.settings,
        AppRoutes.profile,
        AppRoutes.emergencyResponseDetails,
      ];

      for (final route in expectedRoutes) {
        expect(AppRoutes.routes.containsKey(route), isTrue,
            reason: 'Route "$route" must exist in AppRoutes.routes');
      }
    });

    test('verify exact route path strings', () {
      expect(AppRoutes.splash, equals('/splash'));
      expect(AppRoutes.login, equals('/auth/login'));
      expect(AppRoutes.register, equals('/auth/register'));
      expect(AppRoutes.dashboard, equals('/dashboard'));
      expect(AppRoutes.smartCheckIn, equals('/checkin'));
      expect(AppRoutes.monitoringStatus, equals('/monitoring/status'));
      expect(AppRoutes.riskAnalysis, equals('/risk/analysis'));
      expect(AppRoutes.sosEmergency, equals('/sos'));
      expect(AppRoutes.emergencyContacts, equals('/contacts'));
      expect(AppRoutes.addEditContact, equals('/contacts/form'));
      expect(AppRoutes.liveLocation, equals('/location/live'));
      expect(AppRoutes.alertsNotifications, equals('/alerts'));
      expect(AppRoutes.activityLogs, equals('/activity/logs'));
      expect(AppRoutes.settings, equals('/settings'));
      expect(AppRoutes.profile, equals('/profile'));
      expect(AppRoutes.emergencyResponseDetails, equals('/emergency/response'));
    });
  });
}
