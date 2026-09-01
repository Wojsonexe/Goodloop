import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

/// Adres backendu (REST + WebSocket czatu).
///
/// Nadpisanie na czas kompilacji (np. dla emulatora Androida):
///   flutter run --dart-define=API_URL=http://10.0.2.2:3000
///   flutter run --dart-define=WEBSOCKET_URL=ws://10.0.2.2:3000/chat
class ApiConfig {
  ApiConfig._();

  /// Host serwera dev w LAN (fizyczne urządzenie w tej samej sieci).
  static const String _lanHost = '10.10.10.108';
  static const int _port = 3000;

  /// Backend produkcyjny (Railway) — buildy release.
  static const String _prodBaseUrl =
      'https://goodloop-api-production.up.railway.app';

  static String get baseUrl {
    const override = String.fromEnvironment('API_URL');
    return override.isEmpty ? _defaultBaseUrl() : override;
  }

  static String _defaultBaseUrl() {
    if (kReleaseMode) return _prodBaseUrl;
    if (kIsWeb) return 'http://localhost:$_port';
    if (Platform.isAndroid) {
      // Emulator: użyj --dart-define=API_URL=http://10.0.2.2:$_port
      // Fizyczne urządzenie w LAN:
      return 'http://$_lanHost:$_port';
    }
    // iOS symulator / macOS / Linux / Windows dzielą sieć z hostem.
    // Fizyczny iPhone: --dart-define=API_URL=http://$_lanHost:$_port
    return 'http://localhost:$_port';
  }

  static String get webSocketUrl {
    // socket_io_client sam negocjuje upgrade do WS — podajemy http(s),
    // NIE ws(s): Uri.parse('wss://host').port == 0 w Dart → łączy się z :0.
    return '$baseUrl/chat';
  }

  static String get apiPath => '$baseUrl/api/v1';

  static String get debugInfo => '''
Base:     $baseUrl
WS:       $webSocketUrl
Platform: ${kIsWeb ? 'web' : Platform.operatingSystem}
Override: ${const String.fromEnvironment('API_URL', defaultValue: '(brak)')}
'''
      .trim();
}
