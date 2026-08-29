import 'package:dio/dio.dart';

/// Błąd z warstwy sieciowej sprowadzony do komunikatu po polsku.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

ApiException toApiException(Object error) {
  if (error is! DioException) {
    return ApiException('Coś poszło nie tak. Spróbuj ponownie.');
  }

  final status = error.response?.statusCode;
  final data = error.response?.data;
  if (data is Map && data['message'] is String) {
    return ApiException(data['message'] as String, statusCode: status);
  }

  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.connectionError =>
      ApiException('Brak połączenia z serwerem.', statusCode: status),
    _ => ApiException('Błąd serwera${status != null ? ' ($status)' : ''}.',
        statusCode: status),
  };
}
