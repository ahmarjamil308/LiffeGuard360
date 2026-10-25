import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';

/// Contract for secure local storage of credentials, tokens, and safety PINs.
abstract class ISecureStorage {
  Future<void> saveToken(String token);
  Future<String?> getToken();
  Future<void> deleteToken();

  Future<void> saveEmergencyPin(String pin);
  Future<String?> getEmergencyPin();
  Future<void> deleteEmergencyPin();

  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
  Future<void> clearAll();
}

/// Production implementation backed by FlutterSecureStorage with Android Keystore encryption.
class SecureStorageService implements ISecureStorage {
  final FlutterSecureStorage _storage;

  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
                resetOnError: true,
              ),
            );

  @override
  Future<void> saveToken(String token) async {
    await _storage.write(key: AppConstants.keyJwtToken, value: token);
  }

  @override
  Future<String?> getToken() async {
    return await _storage.read(key: AppConstants.keyJwtToken);
  }

  @override
  Future<void> deleteToken() async {
    await _storage.delete(key: AppConstants.keyJwtToken);
  }

  @override
  Future<void> saveEmergencyPin(String pin) async {
    await _storage.write(key: AppConstants.keyEmergencyPin, value: pin);
  }

  @override
  Future<String?> getEmergencyPin() async {
    return await _storage.read(key: AppConstants.keyEmergencyPin);
  }

  @override
  Future<void> deleteEmergencyPin() async {
    await _storage.delete(key: AppConstants.keyEmergencyPin);
  }

  @override
  Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  @override
  Future<String?> read(String key) async {
    return await _storage.read(key: key);
  }

  @override
  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  @override
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}

/// In-memory implementation for unit and widget testing without native Keystore bindings.
class MockSecureStorageService implements ISecureStorage {
  final Map<String, String> _memory = {};

  @override
  Future<void> saveToken(String token) async {
    _memory[AppConstants.keyJwtToken] = token;
  }

  @override
  Future<String?> getToken() async {
    return _memory[AppConstants.keyJwtToken];
  }

  @override
  Future<void> deleteToken() async {
    _memory.remove(AppConstants.keyJwtToken);
  }

  @override
  Future<void> saveEmergencyPin(String pin) async {
    _memory[AppConstants.keyEmergencyPin] = pin;
  }

  @override
  Future<String?> getEmergencyPin() async {
    return _memory[AppConstants.keyEmergencyPin];
  }

  @override
  Future<void> deleteEmergencyPin() async {
    _memory.remove(AppConstants.keyEmergencyPin);
  }

  @override
  Future<void> write(String key, String value) async {
    _memory[key] = value;
  }

  @override
  Future<String?> read(String key) async {
    return _memory[key];
  }

  @override
  Future<void> delete(String key) async {
    _memory.remove(key);
  }

  @override
  Future<void> clearAll() async {
    _memory.clear();
  }
}
