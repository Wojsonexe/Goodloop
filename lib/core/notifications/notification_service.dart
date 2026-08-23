import 'package:flutter/foundation.dart';
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
      await scheduleDailyReminder(hour: time.hour, minute: time.minute);
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

  Future<void> scheduleDailyReminder({
    int hour = 20,
    int minute = 0,
  }) async {
    if (!_initialized) return;

    await _persist(hour, minute);
    await _plugin.cancel(_kDailyReminderId);

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

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

    // Spróbuj exact — jeśli brak uprawnienia (SCHEDULE_EXACT_ALARM), spadnij na inexact.
    try {
      await _plugin.zonedSchedule(
        _kDailyReminderId,
        '💝 Czas na dobry uczynek!',
        'Twoje dzisiejsze zadanie czeka — zrób coś dobrego i zdobądź punkty.',
        scheduled,
        const NotificationDetails(
          android: androidDetails,
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint('[Notifications] ✅ Exact alarm scheduled at $hour:$minute');
    } catch (e) {
      debugPrint('[Notifications] Exact alarm failed, using inexact: $e');
      await _plugin.zonedSchedule(
        _kDailyReminderId,
        '💝 Czas na dobry uczynek!',
        'Twoje dzisiejsze zadanie czeka — zrób coś dobrego i zdobądź punkty.',
        scheduled,
        const NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint('[Notifications] ✅ Inexact alarm scheduled at $hour:$minute');
    }
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
    debugPrint('[Notifications] All cancelled');
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

  Future<void> schedule(int hour, int minute) async {
    final service = ref.read(notificationServiceProvider);
    await service.scheduleDailyReminder(hour: hour, minute: minute);
    state = AsyncData(NotificationTime(hour: hour, minute: minute));
  }
}
