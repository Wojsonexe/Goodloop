import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../logger.dart';

const _dailyReminderNotificationId = 0;
const _prefsHourKey = 'notificationHour';
const _prefsMinuteKey = 'notificationMinute';
const _defaultHour = 9;
const _defaultMinute = 0;

/// An hour/minute pair, independent of any specific date.
class NotificationTime {
  const NotificationTime({required this.hour, required this.minute});

  final int hour;
  final int minute;

  @override
  bool operator ==(Object other) =>
      other is NotificationTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => 'NotificationTime($hour:$minute)';
}

/// Owns the single [FlutterLocalNotificationsPlugin] instance for the app
/// and everything needed to reliably schedule the daily reminder:
/// one-time idempotent initialization (timezone + plugin + permissions),
/// scheduling, cancelling, and reading back the persisted schedule.
///
/// Exactly one [NotificationService] should exist for the app's lifetime —
/// see [notificationServiceProvider], which Riverpod guarantees is only
/// built once per [ProviderScope].
class NotificationService {
  NotificationService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  bool _initialized = false;

  /// Non-null while an initialization is in flight, so concurrent callers
  /// await the same attempt instead of racing to initialize the native
  /// plugin (and request permissions) more than once.
  Future<void>? _initializing;

  /// Initializes timezone data, the notification plugin, and requests
  /// platform permissions. Safe to call more than once or concurrently —
  /// the real work only ever runs a single time.
  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initializing ??= _doInitialize().whenComplete(() {
      _initializing = null;
    });
  }

  Future<void> _doInitialize() async {
    tz_data.initializeTimeZones();
    await _configureLocalTimezone();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    final success = await _plugin.initialize(settings);
    if (success == false) {
      logger.w('⚠️ NotificationService: plugin.initialize() reported failure');
    }

    await _requestPermissions();
    _initialized = true;

    // If the user had already configured a reminder time in a previous
    // session, re-arm it now. Scheduled alarms are lost on device reboot
    // (this app does not register a native boot receiver — see report),
    // so re-scheduling on every cold start is what keeps the reminder
    // working across reboots without requiring native platform code.
    if (await hasScheduledReminder()) {
      final time = await getScheduledTime();
      try {
        await scheduleDailyReminder(hour: time.hour, minute: time.minute);
      } catch (e) {
        logger.w('⚠️ NotificationService: failed to re-arm reminder on startup: $e');
      }
    }
  }

  Future<void> _configureLocalTimezone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      logger.w(
        '⚠️ NotificationService: could not resolve device timezone ($e), '
        'falling back to UTC — scheduled times will be wrong for non-UTC users',
      );
    }
  }

  Future<void> _requestPermissions() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      logger.w('⚠️ NotificationService: Android permission request failed: $e');
    }

    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      logger.w('⚠️ NotificationService: iOS permission request failed: $e');
    }
  }

  /// Schedules (or reschedules) the daily reminder for the given local time.
  ///
  /// Uses [AndroidScheduleMode.inexactAllowWhileIdle]: the notification may
  /// fire a few minutes late (Android batches inexact alarms to save
  /// battery) but still fires while the device is idle/Doze, and — unlike
  /// exact scheduling — never needs the user to grant the separate
  /// "Alarms & reminders" special permission. For a daily reminder, that
  /// tradeoff is the right one.
  Future<void> scheduleDailyReminder({
    required int hour,
    required int minute,
  }) async {
    await initialize();

    await _plugin.cancel(_dailyReminderNotificationId);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsHourKey, hour);
    await prefs.setInt(_prefsMinuteKey, minute);

    await _plugin.zonedSchedule(
      _dailyReminderNotificationId,
      'Time for Kindness! 💝',
      'Your daily act of kindness awaits. Let\'s make someone\'s day better!',
      nextInstanceOf(hour, minute),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminder',
          'Daily Reminders',
          channelDescription: 'Daily task reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Pure computation of the next occurrence of [hour]:[minute] in the
  /// timezone [tz.local] is currently configured for. Kept free of any
  /// plugin/platform dependency so it can be unit tested directly.
  static tz.TZDateTime nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Whether the user has ever configured a reminder time (as opposed to
  /// [getScheduledTime] simply falling back to its default).
  Future<bool> hasScheduledReminder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_prefsHourKey);
  }

  Future<NotificationTime> getScheduledTime() async {
    final prefs = await SharedPreferences.getInstance();
    return NotificationTime(
      hour: prefs.getInt(_prefsHourKey) ?? _defaultHour,
      minute: prefs.getInt(_prefsMinuteKey) ?? _defaultMinute,
    );
  }

  Future<void> cancelNotifications() async {
    await _plugin.cancelAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsHourKey);
    await prefs.remove(_prefsMinuteKey);
  }
}

/// Exactly one instance for the app's lifetime — constructed once in
/// `main()` (where the async plugin initialization happens) and provided
/// to the widget tree via `notificationServiceProvider.overrideWithValue`.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  throw UnimplementedError(
    'notificationServiceProvider must be overridden in main() with an '
    'already-constructed, already-initialized NotificationService.',
  );
});

class NotificationSettingsNotifier
    extends StateNotifier<AsyncValue<NotificationTime>> {
  NotificationSettingsNotifier(this._service) : super(const AsyncValue.loading()) {
    _load();
  }

  final NotificationService _service;

  Future<void> _load() async {
    try {
      state = AsyncValue.data(await _service.getScheduledTime());
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> schedule(int hour, int minute) async {
    state = const AsyncValue.loading();
    try {
      await _service.scheduleDailyReminder(hour: hour, minute: minute);
      state = AsyncValue.data(NotificationTime(hour: hour, minute: minute));
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  Future<void> cancel() async {
    state = const AsyncValue.loading();
    try {
      await _service.cancelNotifications();
      state = const AsyncValue.data(
        NotificationTime(hour: _defaultHour, minute: _defaultMinute),
      );
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }
}

final notificationSettingsProvider = StateNotifierProvider<
    NotificationSettingsNotifier, AsyncValue<NotificationTime>>((ref) {
  return NotificationSettingsNotifier(ref.watch(notificationServiceProvider));
});
