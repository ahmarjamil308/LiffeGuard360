/// Typed exceptions for LifeGuard 360 network, authentication, and offline storage.
abstract class AppException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic details;

  const AppException(this.message, {this.statusCode, this.details});

  @override
  String toString() => message;
}

class NetworkException extends AppException {
  const NetworkException([String message = 'Network connection unavailable. Please check your internet connection.'])
      : super(message, statusCode: 0);
}

class AuthException extends AppException {
  const AuthException([String message = 'Authentication required or session expired.', int? statusCode = 401])
      : super(message, statusCode: statusCode);
}

class ValidationException extends AppException {
  const ValidationException([String message = 'Invalid input provided.', dynamic details])
      : super(message, statusCode: 400, details: details);
}

class IncidentConflictException extends AppException {
  const IncidentConflictException([String message = 'Incident idempotency conflict detected.', dynamic details])
      : super(message, statusCode: 409, details: details);
}

class ForbiddenException extends AppException {
  const ForbiddenException([String message = 'Access denied. You do not have permission for this resource.'])
      : super(message, statusCode: 403);
}

class NotFoundException extends AppException {
  const NotFoundException([String message = 'Requested resource was not found.'])
      : super(message, statusCode: 404);
}

class ServerException extends AppException {
  const ServerException([String message = 'Internal server error. Please try again later.', int? statusCode = 500])
      : super(message, statusCode: statusCode);
}

class OfflineStorageException extends AppException {
  const OfflineStorageException([String message = 'Failed to read or write local incident storage.'])
      : super(message);
}
