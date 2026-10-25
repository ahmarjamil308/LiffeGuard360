import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeguard360/core/network/api_client.dart';
import 'package:lifeguard360/core/storage/local_incident_store.dart';
import 'package:lifeguard360/core/storage/secure_storage_service.dart';
import 'package:lifeguard360/core/theme/app_theme.dart';
import 'package:lifeguard360/features/auth/providers/auth_provider.dart';
import 'package:lifeguard360/features/auth/screens/login_screen.dart';
import 'package:lifeguard360/features/auth/screens/register_screen.dart';
import 'package:lifeguard360/features/sos/providers/sos_provider.dart';
import 'package:provider/provider.dart';

Widget createAuthTestHarness(Widget child) {
  final mockStorage = MockSecureStorageService();
  final mockLocalStore = MockLocalIncidentStore();
  final apiClient = ApiClient(secureStorage: mockStorage);

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
        ),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: child,
    ),
  );
}

void main() {
  group('Auth Screens Form Validation Tests', () {
    testWidgets('LoginScreen validates empty email and password', (tester) async {
      await tester.pumpWidget(createAuthTestHarness(const LoginScreen()));

      // Tap Sign In without filling form
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pump();

      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
    });

    testWidgets('LoginScreen validates invalid email format', (tester) async {
      await tester.pumpWidget(createAuthTestHarness(const LoginScreen()));

      await tester.enterText(find.byKey(const Key('login_email_field')), 'invalid-email');
      await tester.enterText(find.byKey(const Key('login_password_field')), 'Secret123!');
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pump();

      expect(find.text('Please enter a valid email address'), findsOneWidget);
    });

    testWidgets('RegisterScreen validates short password and invalid PIN', (tester) async {
      await tester.pumpWidget(createAuthTestHarness(const RegisterScreen()));

      await tester.enterText(find.byKey(const Key('register_name_field')), 'Alice Smith');
      await tester.enterText(find.byKey(const Key('register_email_field')), 'alice@test.com');
      await tester.enterText(find.byKey(const Key('register_phone_field')), '+14155551234');
      await tester.enterText(find.byKey(const Key('register_password_field')), 'short');
      await tester.enterText(find.byKey(const Key('register_pin_field')), '12'); // Only 2 digits

      await tester.tap(find.byKey(const Key('register_submit_button')));
      await tester.pump();

      expect(find.text('Password must be at least 8 characters'), findsOneWidget);
      expect(find.text('PIN must be exactly 4 numeric digits'), findsOneWidget);
    });
  });
}
