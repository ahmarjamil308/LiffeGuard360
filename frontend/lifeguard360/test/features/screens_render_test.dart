import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeguard360/core/location/location_service.dart';
import 'package:lifeguard360/core/network/api_client.dart';
import 'package:lifeguard360/core/platform/android_service_bridge.dart';
import 'package:lifeguard360/core/routes/app_routes.dart';
import 'package:lifeguard360/core/sensors/sensor_monitoring_service.dart';
import 'package:lifeguard360/core/storage/local_incident_store.dart';
import 'package:lifeguard360/core/storage/secure_storage_service.dart';
import 'package:lifeguard360/features/monitoring/providers/monitoring_provider.dart';
import 'package:lifeguard360/core/theme/app_theme.dart';
import 'package:lifeguard360/features/logs/screens/activity_logs_screen.dart';
import 'package:lifeguard360/features/alerts/screens/alerts_notifications_screen.dart';
import 'package:lifeguard360/features/auth/providers/auth_provider.dart';
import 'package:lifeguard360/features/auth/screens/login_screen.dart';
import 'package:lifeguard360/features/auth/screens/register_screen.dart';
import 'package:lifeguard360/features/checkin/screens/smart_checkin_screen.dart';
import 'package:lifeguard360/features/contacts/screens/add_edit_contact_screen.dart';
import 'package:lifeguard360/features/contacts/screens/emergency_contacts_screen.dart';
import 'package:lifeguard360/features/dashboard/screens/dashboard_screen.dart';
import 'package:lifeguard360/features/emergency_response/screens/emergency_response_details_screen.dart';
import 'package:lifeguard360/features/location/screens/live_location_screen.dart';
import 'package:lifeguard360/features/monitoring/screens/monitoring_status_screen.dart';
import 'package:lifeguard360/features/profile/screens/profile_screen.dart';
import 'package:lifeguard360/features/risk/screens/risk_analysis_screen.dart';
import 'package:lifeguard360/features/settings/screens/settings_screen.dart';
import 'package:lifeguard360/features/sos/providers/sos_provider.dart';
import 'package:lifeguard360/features/sos/screens/sos_emergency_screen.dart';
import 'package:lifeguard360/features/splash/screens/splash_screen.dart';
import 'package:lifeguard360/features/checkin/providers/checkin_provider.dart';
import 'package:provider/provider.dart';

Widget createTestHarness(Widget child) {
  final mockStorage = MockSecureStorageService();
  final mockLocalStore = MockLocalIncidentStore();
  final apiClient = ApiClient(secureStorage: mockStorage);
  final mockLocationService = MockLocationService();
  final mockSensorService = MockSensorMonitoringService();
  final mockAndroidBridge = MockAndroidServiceBridge();

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(
          apiClient: apiClient,
          secureStorage: mockStorage,
        ),
      ),
      ChangeNotifierProvider<SOSProvider>(
        create: (_) => SOSProvider(
          apiClient: apiClient,
          localStore: mockLocalStore,
          secureStorage: mockStorage,
          locationService: mockLocationService,
        ),
      ),
      ChangeNotifierProvider<MonitoringProvider>(
        create: (_) => MonitoringProvider(
          sensorService: mockSensorService,
          locationService: mockLocationService,
          androidBridge: mockAndroidBridge,
        )..initialize(),
      ),
      ChangeNotifierProvider<CheckInProvider>(
        create: (_) => CheckInProvider(apiClient: apiClient),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: child,
      routes: AppRoutes.routes,
    ),
  );
}

void main() {
  group('16-Screen Render Smoke Tests', () {
    testWidgets('Screen 1: SplashScreen renders without crashing', (tester) async {
      await tester.pumpWidget(createTestHarness(const SplashScreen()));
      expect(find.text('LIFEGUARD 360'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump();
    });

    testWidgets('Screen 2: LoginScreen renders without crashing', (tester) async {
      await tester.pumpWidget(createTestHarness(const LoginScreen()));
      expect(find.text('Welcome to LifeGuard 360'), findsOneWidget);
      expect(find.byKey(const Key('login_submit_button')), findsOneWidget);
    });

    testWidgets('Screen 3: RegisterScreen renders without crashing', (tester) async {
      await tester.pumpWidget(createTestHarness(const RegisterScreen()));
      expect(find.text('Create Safety Account'), findsWidgets);
      expect(find.byKey(const Key('register_submit_button')), findsOneWidget);
    });

    testWidgets('Screen 4: DashboardScreen renders without crashing', (tester) async {
      await tester.pumpWidget(createTestHarness(const DashboardScreen()));
      expect(find.text('MANUAL SOS DISTRESS'), findsOneWidget);
      expect(find.byKey(const Key('dashboard_sos_button')), findsOneWidget);
    });

    testWidgets('Screen 5: SmartCheckInScreen renders without crashing', (tester) async {
      await tester.pumpWidget(createTestHarness(const SmartCheckInScreen()));
      expect(find.text('Schedule New Check-In Timer'), findsOneWidget);
      expect(find.byKey(const Key('start_checkin_timer_button')), findsOneWidget);
    });

    testWidgets('Screen 6: MonitoringStatusScreen renders without crashing', (tester) async {
      await tester.pumpWidget(createTestHarness(const MonitoringStatusScreen()));
      expect(find.text('LIVE SENSOR TELEMETRY'), findsOneWidget);
      expect(find.text('POST_NOTIFICATIONS'), findsOneWidget);
    });

    testWidgets('Screen 7: RiskAnalysisScreen renders without crashing', (tester) async {
      await tester.pumpWidget(createTestHarness(const RiskAnalysisScreen()));
      expect(find.text('FOUR FACTOR BREAKDOWN'), findsOneWidget);
      expect(find.text('Smart Check-In Factor'), findsOneWidget);
    });

    testWidgets('Screen 8: SOSEmergencyScreen renders without crashing', (tester) async {
      await tester.pumpWidget(createTestHarness(const SOSEmergencyScreen()));
      expect(find.byKey(const Key('sos_emergency_main_button')), findsOneWidget);
    });

    testWidgets('Screen 9: EmergencyContactsScreen renders without crashing', (tester) async {
      await tester.pumpWidget(createTestHarness(const EmergencyContactsScreen()));
      expect(find.text('Sarah Jenkins'), findsOneWidget);
      expect(find.text('Add Contact'), findsOneWidget);
    });

    testWidgets('Screen 10: AddEditContactScreen renders without crashing', (tester) async {
      await tester.pumpWidget(createTestHarness(const AddEditContactScreen()));
      expect(find.byKey(const Key('save_contact_button')), findsOneWidget);
    });

    testWidgets('Screen 11: LiveLocationScreen renders without crashing', (tester) async {
      await tester.pumpWidget(createTestHarness(const LiveLocationScreen()));
      expect(find.text('Live Location Telemetry'), findsOneWidget);
      expect(find.byKey(const Key('share_location_button')), findsOneWidget);
    });

    testWidgets('Screen 12: AlertsNotificationsScreen renders without crashing', (tester) async {
      await tester.pumpWidget(createTestHarness(const AlertsNotificationsScreen()));
      expect(find.text('Alerts & Notifications'), findsOneWidget);
    });

    testWidgets('Screen 13: ActivityLogsScreen renders without crashing', (tester) async {
      await tester.pumpWidget(createTestHarness(const ActivityLogsScreen()));
      expect(find.text('Activity Audit Logs'), findsOneWidget);
    });

    testWidgets('Screen 14: SettingsScreen renders without crashing', (tester) async {
      await tester.pumpWidget(createTestHarness(const SettingsScreen()));
      expect(find.text('SEPARATED EMERGENCY TIMERS'), findsOneWidget);
      expect(find.byKey(const Key('save_settings_button')), findsOneWidget);
    });

    testWidgets('Screen 15: ProfileScreen renders without crashing', (tester) async {
      await tester.pumpWidget(createTestHarness(const ProfileScreen()));
      expect(find.text('User Profile'), findsOneWidget);
      expect(find.byKey(const Key('profile_sign_out_button')), findsOneWidget);
    });

    testWidgets('Screen 16: EmergencyResponseDetailsScreen renders without crashing', (tester) async {
      await tester.pumpWidget(createTestHarness(const EmergencyResponseDetailsScreen()));
      expect(find.text('Emergency Response Details'), findsOneWidget);
      expect(find.byKey(const Key('resolve_incident_button')), findsOneWidget);
    });
  });
}
