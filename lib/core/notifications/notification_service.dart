import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

part 'notification_service.g.dart';

const _kDailyReminderId = 1;
const _kTestNotificationId = 99;

/// Jak faktycznie udało się zaplanować przypomnienie.
enum ReminderScheduleOutcome {
  /// Nie zaplanowano — serwis nie był zainicjalizowany.
  notInitialized,

  /// Alarm dokładny — przyjdzie o wybranej minucie.
  exact,

  /// Alarm niedokładny — brak uprawnienia SCHEDULE_EXACT_ALARM.
  /// Przyjdzie, ale może z opóźnieniem (okno serwisowe / Doze).
  inexact,
}

class NotificationTime {
  const NotificationTime({required this.hour, required this.minute});
  final int hour;
  final int minute;

  @override
  bool operator ==(Object other) =>
      other is NotificationTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);
}

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _prefsHourKey = 'notificationHour';
  static const _prefsMinuteKey = 'notificationMinute';
  static const _prefsEnabledKey = 'notificationsEnabled';

  bool _initialized = false;
  Future<void>? _initializing;

  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initializing ??= _doInitialize().whenComplete(() {
      _initializing = null;
    });
  }

  Future<void> _doInitialize() async {
    tz_data.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      debugPrint(
          '[Notifications] Could not resolve timezone, falling back to UTC: $e');
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (details) {
        debugPrint('[Notifications] Tapped: ${details.payload}');
      },
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      try {
        await androidPlugin.requestNotificationsPermission();
      } catch (e) {
        debugPrint('[Notifications] Permission request skipped: $e');
      }
    }

    _initialized = true;
    debugPrint('[Notifications] Initialized');

    // Respektuj to, co user zapisał w poprzedniej sesji — nie ma tu żadnego
    // parametru z zewnątrz, to jedyne źródło prawdy.
    final enabled = await isEnabled();
    if (enabled) {
      final time = await getScheduledTime();
      try {
        final outcome = await scheduleDailyReminder(
          hour: time.hour,
          minute: time.minute,
        );
        debugPrint('[Notifications] Re-armed on startup: $outcome');
      } catch (e) {
        // scheduleDailyReminder sam degraduje do alarmu niedokładnego, gdy
        // brakuje uprawnienia exact-alarm; cokolwiek tu doleci to realnie
        // nieoczekiwany błąd i nie może wywrócić startu aplikacji.
        debugPrint('[Notifications] Could not re-arm reminder on startup: $e');
      }
    }
  }

  Future<void> _persist(int hour, int minute) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsHourKey, hour);
    await prefs.setInt(_prefsMinuteKey, minute);
    await prefs.setBool(_prefsEnabledKey, true);
  }

  Future<NotificationTime> getScheduledTime() async {
    final prefs = await SharedPreferences.getInstance();
    return NotificationTime(
      hour: prefs.getInt(_prefsHourKey) ?? 20,
      minute: prefs.getInt(_prefsMinuteKey) ?? 0,
    );
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsEnabledKey) ?? true;
  }

  Future<void> disableReminder() async {
    await _plugin.cancel(_kDailyReminderId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabledKey, false);
  }

  Future<ReminderScheduleOutcome> scheduleDailyReminder({
    int hour = 20,
    int minute = 0,
  }) async {
    if (!_initialized) return ReminderScheduleOutcome.notInitialized;

    await _persist(hour, minute);
    await _plugin.cancel(_kDailyReminderId);

    final scheduled = _nextInstanceOf(hour, minute);
    debugPrint('[Notifications] Scheduling for: $scheduled');

    const androidDetails = AndroidNotificationDetails(
      'daily_reminder',
      'Codzienne przypomnienie',
      channelDescription: 'Przypomnienie o dzisiejszym zadaniu dobroci',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      showWhen: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    const title = '💝 Czas na dobry uczynek!';
    const body =
        'Twoje dzisiejsze zadanie czeka — zrób coś dobrego i zdobądź punkty.';

    // Preferuj alarm dokładny — przypomnienie „o 20:00” ma przyjść o 20:00.
    // Gdy brakuje SCHEDULE_EXACT_ALARM (Android 12+, domyślnie odrzucone na
    // 14+), plugin rzuca PlatformException: schodzimy wtedy na alarm
    // niedokładny (spóźnione przypomnienie > brak przypomnienia) i zwracamy
    // wołającemu, w jakim trybie się udało, by UI mógł zasugerować włączenie
    // uprawnienia.
    try {
      await _plugin.zonedSchedule(
        _kDailyReminderId,
        title,
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint('[Notifications] ✅ Exact alarm scheduled at $hour:$minute');
      return ReminderScheduleOutcome.exact;
    } on PlatformException catch (e) {
      debugPrint(
          '[Notifications] Exact alarm denied ($e) — falling back to inexact');
      await _plugin.zonedSchedule(
        _kDailyReminderId,
        title,
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint('[Notifications] ✅ Inexact alarm scheduled at $hour:$minute');
      return ReminderScheduleOutcome.inexact;
    }
  }

  /// Najbliższe wystąpienie [hour]:[minute] w strefie czasowej urządzenia.
  /// Jeśli ten moment już minął (lub jest teraz) — przechodzi na jutro.
  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Whether the app currently has permission to schedule exact alarms
  /// (Android 12+). Always true on platforms/API levels that don't require
  /// this permission at all.
  Future<bool> canScheduleExactAlarms() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return true;
    try {
      return await androidPlugin.canScheduleExactNotifications() ?? false;
    } catch (e) {
      debugPrint('[Notifications] canScheduleExactAlarms check failed: $e');
      return false;
    }
  }

  /// Sends the user to the system "Alarms & reminders" settings screen and
  /// waits for them to return, resolving with whether the permission is
  /// now granted. Callers are responsible for explaining *why* first (see
  /// settings_screen.dart) — this method itself does not show any UI other
  /// than the system settings screen.
  Future<bool> requestExactAlarmPermission() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return true;
    try {
      return await androidPlugin.requestExactAlarmsPermission() ?? false;
    } catch (e) {
      debugPrint('[Notifications] requestExactAlarmPermission failed: $e');
      return false;
    }
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
    debugPrint('[Notifications] All cancelled');
  }

  Future<void> rearmIfEnabled() async {
    if (!_initialized) return;
    if (!await isEnabled()) return;
    final time = await getScheduledTime();
    try {
      await scheduleDailyReminder(hour: time.hour, minute: time.minute);
    } catch (e) {
      debugPrint('[Notifications] re-arm on resume failed: $e');
    }
  }

  /// Immediately shows one test notification, using the same Android
  /// channel as the daily reminder. Does not touch SharedPreferences and
  /// does not affect the scheduled daily reminder in any way — purely a
  /// diagnostic "does this device actually show notifications?" check.
  ///
  /// Calls [initialize] first (a no-op if already initialized) so the test
  /// has the best chance of actually working, and so a real setup problem
  /// surfaces as an error here instead of silently doing nothing.
  Future<void> showTestNotification() async {
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      'daily_reminder',
      'Codzienne przypomnienie',
      channelDescription: 'Przypomnienie o dzisiejszym zadaniu dobroci',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      showWhen: true,
    );

    await _plugin.show(
      _kTestNotificationId,
      'GoodLoop test',
      'Powiadomienia działają poprawnie 🚀',
      const NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
    debugPrint('[Notifications] Test notification shown');
  }
}

@Riverpod(keepAlive: true)
NotificationService notificationService(Ref ref) {
  return NotificationService();
}

@riverpod
class NotificationSettings extends _$NotificationSettings {
  @override
  Future<NotificationTime> build() =>
      ref.watch(notificationServiceProvider).getScheduledTime();

  Future<ReminderScheduleOutcome> schedule(int hour, int minute) async {
    final service = ref.read(notificationServiceProvider);
    final outcome =
        await service.scheduleDailyReminder(hour: hour, minute: minute);
    state = AsyncData(NotificationTime(hour: hour, minute: minute));
    return outcome;
  }
}
