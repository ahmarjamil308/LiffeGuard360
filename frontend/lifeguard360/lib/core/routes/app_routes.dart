import 'package:flutter/material.dart';
import '../../features/splash/screens/splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/checkin/screens/smart_checkin_screen.dart';
import '../../features/monitoring/screens/monitoring_status_screen.dart';
import '../../features/risk/screens/risk_analysis_screen.dart';
import '../../features/sos/screens/sos_emergency_screen.dart';
import '../../features/contacts/screens/emergency_contacts_screen.dart';
import '../../features/contacts/screens/add_edit_contact_screen.dart';
import '../../features/location/screens/live_location_screen.dart';
import '../../features/alerts/screens/alerts_notifications_screen.dart';
import '../../features/logs/screens/activity_logs_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/emergency_response/screens/emergency_response_details_screen.dart';

/// Central Route Registry defining exactly 16 screens for LifeGuard 360.
/// Zero onboarding screens.
class AppRoutes {
  AppRoutes._();

  // Screen 1: Splash
  static const String splash = '/splash';

  // Screen 2: Login
  static const String login = '/auth/login';

  // Screen 3: Registration
  static const String register = '/auth/register';

  // Screen 4: Home Dashboard
  static const String dashboard = '/dashboard';

  // Screen 5: Smart Check-In
  static const String smartCheckIn = '/checkin';

  // Screen 6: Monitoring Status
  static const String monitoringStatus = '/monitoring/status';

  // Screen 7: Risk Analysis
  static const String riskAnalysis = '/risk/analysis';

  // Screen 8: SOS Emergency
  static const String sosEmergency = '/sos';

  // Screen 9: Emergency Contacts
  static const String emergencyContacts = '/contacts';

  // Screen 10: Add/Edit Contact
  static const String addEditContact = '/contacts/form';

  // Screen 11: Live Location
  static const String liveLocation = '/location/live';

  // Screen 12: Alerts & Notifications
  static const String alertsNotifications = '/alerts';

  // Screen 13: Activity Logs
  static const String activityLogs = '/activity/logs';

  // Screen 14: Settings
  static const String settings = '/settings';

  // Screen 15: Profile
  static const String profile = '/profile';

  // Screen 16: Emergency Response Details
  static const String emergencyResponseDetails = '/emergency/response';

  /// Initial route upon application startup
  static const String initialRoute = splash;

  /// Exact 16-Screen Route Registry Map
  static Map<String, WidgetBuilder> get routes => {
        splash: (context) => const SplashScreen(),
        login: (context) => const LoginScreen(),
        register: (context) => const RegisterScreen(),
        dashboard: (context) => const DashboardScreen(),
        smartCheckIn: (context) => const SmartCheckInScreen(),
        monitoringStatus: (context) => const MonitoringStatusScreen(),
        riskAnalysis: (context) => const RiskAnalysisScreen(),
        sosEmergency: (context) => const SOSEmergencyScreen(),
        emergencyContacts: (context) => const EmergencyContactsScreen(),
        addEditContact: (context) => const AddEditContactScreen(),
        liveLocation: (context) => const LiveLocationScreen(),
        alertsNotifications: (context) => const AlertsNotificationsScreen(),
        activityLogs: (context) => const ActivityLogsScreen(),
        settings: (context) => const SettingsScreen(),
        profile: (context) => const ProfileScreen(),
        emergencyResponseDetails: (context) => const EmergencyResponseDetailsScreen(),
      };
}
