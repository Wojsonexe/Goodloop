import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Wysyła użytkownika do ekranów systemowych, które na chińskich ROM-ach
/// (ColorOS/Realme/OPPO, MIUI/Xiaomi, EMUI/Huawei, FuntouchOS/vivo) decydują,
/// czy zaplanowane powiadomienia przychodzą o czasie:
///  * wyłączenie optymalizacji baterii dla aplikacji,
///  * „automatyczne uruchamianie" (autostart).
///
/// Tych ekranów nie da się otworzyć standardowym API — każdy producent chowa je
/// pod prywatną Activity. Próbujemy kolejnych znanych komponentów i otwieramy
/// pierwszy, który istnieje.
class OemBatteryHelper {
  OemBatteryHelper._();

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Ekran wyłączania optymalizacji baterii dla tej aplikacji.
  /// false = nie udało się otworzyć nic sensownego.
  static Future<bool> openBatteryOptimization() async {
    if (!isSupported) return false;
    final pkg = (await PackageInfo.fromPlatform()).packageName;

    // 1. Bezpośredni dialog „wyłączyć optymalizację dla GoodLoop?".
    if (await _tryLaunch(AndroidIntent(
      action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
      data: 'package:$pkg',
    ))) {
      return true;
    }

    // 2. Pełna lista aplikacji z optymalizacją baterii.
    if (await _tryLaunch(const AndroidIntent(
      action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
    ))) {
      return true;
    }

    // 3. Ostatecznie: ustawienia samej aplikacji.
    return _tryLaunch(AndroidIntent(
      action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
      data: 'package:$pkg',
    ));
  }

  /// Ekran „autostart / automatyczne uruchamianie" właściwy dla producenta.
  /// false = urządzenie nie ma takiego ekranu (czysty Android) — nie ma czego
  /// pokazać.
  static Future<bool> openAutoStart() async {
    if (!isSupported) return false;
    for (final (package, component) in _autoStartComponents) {
      final launched = await _tryLaunch(AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: package,
        componentName: component,
        flags: const [Flag.FLAG_ACTIVITY_NEW_TASK],
      ));
      if (launched) return true;
    }
    return false;
  }

  static Future<bool> _tryLaunch(AndroidIntent intent) async {
    try {
      if (await intent.canResolveActivity() != true) return false;
      await intent.launch();
      return true;
    } catch (e) {
      debugPrint('[OemBatteryHelper] intent launch failed: $e');
      return false;
    }
  }

  /// (package, w pełni kwalifikowana nazwa Activity)
  static const List<(String, String)> _autoStartComponents = [
    // MIUI / Xiaomi / Redmi / POCO
    (
      'com.miui.securitycenter',
      'com.miui.permcenter.autostart.AutoStartManagementActivity',
    ),
    // ColorOS / Realme / OPPO
    (
      'com.coloros.safecenter',
      'com.coloros.safecenter.permission.startup.StartupAppListActivity',
    ),
    (
      'com.coloros.safecenter',
      'com.coloros.safecenter.startupapp.StartupAppListActivity',
    ),
    (
      'com.oppo.safe',
      'com.oppo.safe.permission.startup.StartupAppListActivity',
    ),
    (
      'com.coloros.safecenter',
      'com.coloros.privacypermissionsentry.PermissionTopActivity',
    ),
    // EMUI / Huawei / Honor
    (
      'com.huawei.systemmanager',
      'com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity',
    ),
    (
      'com.huawei.systemmanager',
      'com.huawei.systemmanager.optimize.process.ProtectActivity',
    ),
    // FuntouchOS / OriginOS / vivo / iQOO
    (
      'com.vivo.permissionmanager',
      'com.vivo.permissionmanager.activity.BgStartUpManagerActivity',
    ),
    (
      'com.iqoo.secure',
      'com.iqoo.secure.ui.phoneoptimize.BgStartUpManager',
    ),
  ];
}
