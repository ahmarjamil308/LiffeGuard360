import 'dart:io';
import 'package:dio/dio.dart';
import '../constants/api_constants.dart';
import '../errors/exceptions.dart';
import '../storage/secure_storage_service.dart';
import 'auth_interceptor.dart';

/// Central HTTP Client for LifeGuard 360 REST API.
class ApiClient {
  final Dio dio;

  ApiClient({
    Dio? customDio,
    ISecureStorage? secureStorage,
    void Function()? onUnauthorized,
  }) : dio = customDio ??
            Dio(
              BaseOptions(
                baseUrl: ApiConstants.baseUrl,
                connectTimeout: ApiConstants.connectTimeout,
                receiveTimeout: ApiConstants.receiveTimeout,
                sendTimeout: ApiConstants.sendTimeout,
                headers: {
                  HttpHeaders.contentTypeHeader: 'application/json',
                  HttpHeaders.acceptHeader: 'application/json',
                },
              ),
            ) {
    if (secureStorage != null && customDio == null) {
      dio.interceptors.add(
        AuthInterceptor(
          secureStorage: secureStorage,
          onUnauthorized: onUnauthorized,
        ),
      );
    }
  }

  void updateBaseUrl(String newUrl) {
    dio.options.baseUrl = newUrl;
    ApiConstants.baseUrl = newUrl;
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await dio.get<T>(
        path,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is AppException) rethrow;
      throw ServerException(e.toString());
    }
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await dio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is AppException) rethrow;
      throw ServerException(e.toString());
    }
  }

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await dio.put<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is AppException) rethrow;
      throw ServerException(e.toString());
    }
  }

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await dio.delete<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is AppException) rethrow;
      throw ServerException(e.toString());
    }
  }

  AppException _handleDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return const NetworkException(
          'Network connection timed out or unreachable. Check your connectivity.',
        );

      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode ?? 500;
        final responseData = error.response?.data;
        String message = 'An unexpected error occurred.';

        if (responseData is Map<String, dynamic>) {
          if (responseData['errors'] is Map) {
            final errMap = responseData['errors'] as Map;
            if (errMap.isNotEmpty) {
              final firstKey = errMap.keys.first;
              final firstVal = errMap[firstKey];
              if (firstVal is List && firstVal.isNotEmpty) {
                message = '$firstKey: ${firstVal.first}';
              } else {
                message = '$firstKey: $firstVal';
              }
            } else {
              message = responseData['message']?.toString() ?? message;
            }
          } else if (responseData['errors'] is List && (responseData['errors'] as List).isNotEmpty) {
            message = (responseData['errors'] as List).first.toString();
          } else {
            message = responseData['error']?.toString() ??
                responseData['message']?.toString() ??
                message;
          }
        }

        switch (statusCode) {
          case 400:
            return ValidationException(message, responseData);
          case 401:
            return AuthException(message, statusCode);
          case 403:
            return ForbiddenException(message);
          case 404:
            return NotFoundException(message);
          case 409:
            return IncidentConflictException(message, responseData);
          case 500:
          case 502:
          case 503:
          case 504:
            return ServerException(message, statusCode);
          default:
            return ServerException(message, statusCode);
        }

      case DioExceptionType.cancel:
        return const NetworkException('Request was cancelled.');

      default:
        return NetworkException(
          error.message ?? 'An unknown network error occurred.',
        );
    }
  }
}
