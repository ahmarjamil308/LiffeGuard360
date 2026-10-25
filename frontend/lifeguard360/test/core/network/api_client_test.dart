import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeguard360/core/constants/api_constants.dart';
import 'package:lifeguard360/core/errors/exceptions.dart';
import 'package:lifeguard360/core/network/api_client.dart';
import 'package:lifeguard360/core/network/auth_interceptor.dart';
import 'package:lifeguard360/core/storage/secure_storage_service.dart';

void main() {
  group('ApiClient and AuthInterceptor Tests', () {
    late MockSecureStorageService mockStorage;

    setUp(() {
      mockStorage = MockSecureStorageService();
    });

    test('updates base URL dynamically', () {
      final client = ApiClient(secureStorage: mockStorage);
      expect(client.dio.options.baseUrl, equals(ApiConstants.baseUrl));

      client.updateBaseUrl('http://192.168.1.100:5000/api/v1');
      expect(client.dio.options.baseUrl, equals('http://192.168.1.100:5000/api/v1'));
      expect(ApiConstants.baseUrl, equals('http://192.168.1.100:5000/api/v1'));
    });

    test('AuthInterceptor injects Authorization Bearer header when token exists', () async {
      await mockStorage.saveToken('test-jwt-token-xyz');

      final dio = Dio();
      dio.interceptors.add(AuthInterceptor(secureStorage: mockStorage));

      RequestOptions? capturedOptions;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedOptions = options;
            handler.resolve(Response(requestOptions: options, statusCode: 200));
          },
        ),
      );

      await dio.get('https://example.com/test');

      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.headers['Authorization'], equals('Bearer test-jwt-token-xyz'));
    });

    test('AuthInterceptor does not overwrite existing Authorization header', () async {
      await mockStorage.saveToken('test-jwt-token-xyz');

      final dio = Dio();
      dio.interceptors.add(AuthInterceptor(secureStorage: mockStorage));

      RequestOptions? capturedOptions;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedOptions = options;
            handler.resolve(Response(requestOptions: options, statusCode: 200));
          },
        ),
      );

      await dio.get(
        'https://example.com/test',
        options: Options(headers: {'Authorization': 'CustomExistingToken'}),
      );

      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.headers['Authorization'], equals('CustomExistingToken'));
    });

    test('AuthInterceptor triggers onUnauthorized callback upon 401', () async {
      var unauthorizedCalled = false;
      final dio = Dio();
      dio.interceptors.add(
        AuthInterceptor(
          secureStorage: mockStorage,
          onUnauthorized: () {
            unauthorizedCalled = true;
          },
        ),
      );
      dio.httpClientAdapter = _Mock401Adapter();

      try {
        await dio.get('https://example.com/test');
      } catch (_) {}

      expect(unauthorizedCalled, isTrue);
    });

    test('ApiClient handles 400 Bad Request with ValidationException', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 400,
                  data: {'error': 'Invalid email address'},
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      final client = ApiClient(customDio: dio);

      expect(
        () async => await client.get('/test'),
        throwsA(isA<ValidationException>().having(
          (e) => e.message,
          'message',
          contains('Invalid email address'),
        )),
      );
    });

    test('ApiClient handles 401 Unauthorized with AuthException', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 401,
                  data: {'error': 'Invalid credentials'},
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      final client = ApiClient(customDio: dio);

      expect(
        () async => await client.post('/test'),
        throwsA(isA<AuthException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('ApiClient handles 409 Conflict with IncidentConflictException', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 409,
                  data: {'error': 'Idempotent conflict detected'},
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      final client = ApiClient(customDio: dio);

      expect(
        () async => await client.post('/test'),
        throwsA(isA<IncidentConflictException>()),
      );
    });

    test('ApiClient handles connection timeout with NetworkException', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionTimeout,
              ),
            );
          },
        ),
      );

      final client = ApiClient(customDio: dio);

      expect(
        () async => await client.get('/test'),
        throwsA(isA<NetworkException>()),
      );
    });
  });
}

class _Mock401Adapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"error": "Session expired"}',
      401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

