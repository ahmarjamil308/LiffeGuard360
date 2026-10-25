import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/constants/app_constants.dart';
import 'core/location/location_service.dart';
import 'core/network/api_client.dart';
import 'core/platform/android_service_bridge.dart';
import 'core/routes/app_routes.dart';
import 'core/sensors/sensor_monitoring_service.dart';
import 'core/storage/local_incident_store.dart';
import 'core/storage/secure_storage_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/monitoring/providers/monitoring_provider.dart';
import 'features/sos/providers/sos_provider.dart';
import 'features/checkin/providers/checkin_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Core Service Singletons
  final secureStorage = SecureStorageService();
  final localStore = LocalIncidentStore();
  final apiClient = ApiClient(secureStorage: secureStorage);
  final locationService = LocationService();
  final sensorService = SensorMonitoringService();
  final androidBridge = AndroidServiceBridge();

  runApp(
    LifeGuard360App(
      secureStorage: secureStorage,
      localStore: localStore,
      apiClient: apiClient,
      locationService: locationService,
      sensorService: sensorService,
      androidBridge: androidBridge,
    ),
  );
}

class LifeGuard360App extends StatelessWidget {
  final ISecureStorage secureStorage;
  final ILocalIncidentStore localStore;
  final ApiClient apiClient;
  final ILocationService locationService;
  final ISensorMonitoringService sensorService;
  final IAndroidServiceBridge androidBridge;

  const LifeGuard360App({
    super.key,
    required this.secureStorage,
    required this.localStore,
    required this.apiClient,
    required this.locationService,
    required this.sensorService,
    required this.androidBridge,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(
            apiClient: apiClient,
            secureStorage: secureStorage,
          ),
        ),
        ChangeNotifierProvider<SOSProvider>(
          create: (_) => SOSProvider(
            apiClient: apiClient,
            localStore: localStore,
            secureStorage: secureStorage,
            locationService: locationService,
          ),
        ),
        ChangeNotifierProvider<MonitoringProvider>(
          create: (_) => MonitoringProvider(
            sensorService: sensorService,
            locationService: locationService,
            androidBridge: androidBridge,
          )..initialize(),
        ),
        ChangeNotifierProvider<CheckInProvider>(
          create: (_) => CheckInProvider(apiClient: apiClient)..loadActiveCheckIn(),
        ),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        initialRoute: AppRoutes.initialRoute,
        routes: AppRoutes.routes,
      ),
    );
  }
}
