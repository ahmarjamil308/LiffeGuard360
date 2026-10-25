import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../models/user_model.dart';

/// Provider managing authentication state, token lifecycle, and current user profile.
class AuthProvider extends ChangeNotifier {
  final ApiClient _apiClient;
  final ISecureStorage _secureStorage;

  UserModel? _currentUser;
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _errorMessage;

  AuthProvider({
    required ApiClient apiClient,
    required ISecureStorage secureStorage,
  })  : _apiClient = apiClient,
        _secureStorage = secureStorage;

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Initial app boot check: restores session if valid token is persisted.
  Future<void> initializeAuth() async {
    _isLoading = true;
    notifyListeners();

    try {
      final token = await _secureStorage.getToken();
      if (token != null && token.isNotEmpty) {
        // Try to fetch current user profile
        final response = await _apiClient.get(ApiConstants.authMe);
        if (response.statusCode == 200 && response.data != null) {
          final raw = response.data as Map<String, dynamic>;
          final data = (raw['data'] is Map<String, dynamic>)
              ? raw['data'] as Map<String, dynamic>
              : raw;
          final userData = data['user'] as Map<String, dynamic>;
          _currentUser = UserModel.fromJson(userData);
          await _secureStorage.write(
            AppConstants.keyUserData,
            jsonEncode(_currentUser!.toJson()),
          );
        }
      }
    } catch (e) {
      // If token is invalid or network error, check cached profile or reset
      if (e is AuthException) {
        await _secureStorage.deleteToken();
        _currentUser = null;
      } else {
        // In offline mode, check cached user data
        final cachedUserJson = await _secureStorage.read(AppConstants.keyUserData);
        if (cachedUserJson != null) {
          try {
            _currentUser = UserModel.fromJson(
              jsonDecode(cachedUserJson) as Map<String, dynamic>,
            );
          } catch (_) {}
        }
      }
    } finally {
      _isLoading = false;
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Authenticate with email & password
  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiClient.post(
        ApiConstants.authLogin,
        data: {
          'email': email.trim(),
          'email_or_phone': email.trim(),
          'password': password,
        },
      );

      if ((response.statusCode == 200 || response.statusCode == 201) && response.data != null) {
        final raw = response.data as Map<String, dynamic>;
        final data = (raw['data'] is Map<String, dynamic>)
            ? raw['data'] as Map<String, dynamic>
            : raw;
        final token = (data['token'] ?? data['tokens']?['access_token'])?.toString() ?? '';
        final userData = (data['user'] is Map<String, dynamic>)
            ? data['user'] as Map<String, dynamic>
            : data;

        await _secureStorage.saveToken(token);
        _currentUser = UserModel.fromJson(userData);
        await _secureStorage.write(
          AppConstants.keyUserData,
          jsonEncode(_currentUser!.toJson()),
        );

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        throw const AuthException('Login failed. Please verify your credentials.');
      }
    } on AppException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'An unexpected error occurred: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Register new user account
  Future<bool> register({
    required String fullName,
    required String email,
    required String password,
    String? phoneNumber,
    String? emergencyPin,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final payload = <String, dynamic>{
        'full_name': fullName.trim(),
        'email': email.trim().toLowerCase(),
        'password': password,
      };
      if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
        payload['phone_number'] = phoneNumber.trim();
        payload['phone'] = phoneNumber.trim();
      }
      if (emergencyPin != null && emergencyPin.trim().isNotEmpty) {
        payload['emergency_pin'] = emergencyPin.trim();
        await _secureStorage.saveEmergencyPin(emergencyPin.trim());
      }

      final response = await _apiClient.post(
        ApiConstants.authRegister,
        data: payload,
      );

      if ((response.statusCode == 200 || response.statusCode == 201) && response.data != null) {
        final raw = response.data as Map<String, dynamic>;
        final data = (raw['data'] is Map<String, dynamic>)
            ? raw['data'] as Map<String, dynamic>
            : raw;
        final token = (data['token'] ?? data['tokens']?['access_token'])?.toString() ?? '';
        final userData = (data['user'] is Map<String, dynamic>)
            ? data['user'] as Map<String, dynamic>
            : data;

        await _secureStorage.saveToken(token);
        _currentUser = UserModel.fromJson(userData);
        await _secureStorage.write(
          AppConstants.keyUserData,
          jsonEncode(_currentUser!.toJson()),
        );

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        throw const ValidationException('Registration failed. Please check your details.');
      }
    } on AppException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'An unexpected error occurred: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Sign out and clear stored session tokens
  Future<void> logout() async {
    await _secureStorage.deleteToken();
    await _secureStorage.delete(AppConstants.keyUserData);
    _currentUser = null;
    _errorMessage = null;
    notifyListeners();
  }
}
