import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goodloop/core/network/api_config.dart';

/// Wspólny klient HTTP do backendu GoodLoop. Interceptor dokleja świeży
/// Firebase ID token do każdego żądania (`Authorization: Bearer …`).
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.apiPath, // …/api/v1
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      contentType: Headers.jsonContentType,
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        try {
          final token = await FirebaseAuth.instance.currentUser?.getIdToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        } catch (_) {
          // brak/wygasły token — żądanie poleci bez nagłówka i serwer zwróci 401
        }
        handler.next(options);
      },
    ),
  );

  return dio;
});
