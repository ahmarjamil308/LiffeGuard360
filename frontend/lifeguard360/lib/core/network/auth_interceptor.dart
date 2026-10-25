import 'package:dio/dio.dart';
import '../storage/secure_storage_service.dart';

/// Dio interceptor that injects the JWT bearer token and handles unauthorized responses.
class AuthInterceptor extends Interceptor {
  final ISecureStorage _secureStorage;
  final void Function()? _onUnauthorized;

  AuthInterceptor({
    required ISecureStorage secureStorage,
    void Function()? onUnauthorized,
  })  : _secureStorage = secureStorage,
        _onUnauthorized = onUnauthorized;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final token = await _secureStorage.getToken();
      if (token != null && token.isNotEmpty) {
        if (!options.headers.containsKey('Authorization')) {
          options.headers['Authorization'] = 'Bearer $token';
        }
      }
    } catch (_) {
      // Storage read failure must not block the request
    }
    return handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      _onUnauthorized?.call();
    }
    return handler.next(err);
  }
}
