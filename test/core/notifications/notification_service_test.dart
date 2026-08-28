import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goodloop/core/notifications/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;

const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

/// Default mock handler: succeeds for everything the service calls.
Future<Object?> _defaultHandler(MethodCall call) async {
  switch (call.method) {
    case 'initialize':
      return true;
    case 'requestNotificationsPermission':
      return true;
    default:
      return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  late List<MethodCall> calls;
  late NotificationService service;

  void useHandler(Future<Object?> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(() {
    // This app only ships Android — pin the platform so tests behave the
    // same regardless of the host OS running `flutter test`.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    calls = [];
    useHandler(_defaultHandler);
    service = NotificationService();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('NotificationTime', () {
    test('equality is based on hour and minute', () {
      expect(
        const NotificationTime(hour: 9, minute: 30),
        const NotificationTime(hour: 9, minute: 30),
      );
      expect(
        const NotificationTime(hour: 9, minute: 30) ==
            const NotificationTime(hour: 9, minute: 31),
        isFalse,
      );
    });
  });

  group('initialize', () {
    test('only performs native initialization once across repeated calls',
        () async {
      await service.initialize();
      await service.initialize();
      await service.initialize();

      expect(calls.where((c) => c.method == 'initialize').length, 1);
    });

    test('concurrent calls do not race into multiple native initializations',
        () async {
      await Future.wait([
        service.initialize(),
        service.initialize(),
        service.initialize(),
      ]);

      expect(calls.where((c) => c.method == 'initialize').length, 1);
    });

    test('requests the Android notification permission during init', () async {
      await service.initialize();
      expect(
          calls
              .where((c) => c.method == 'requestNotificationsPermission')
              .length,
          1);
    });

    test(
        'a permission-request failure does not stop initialize() from completing',
        () async {
      useHandler((call) async {
        if (call.method == 'requestNotificationsPermission') {
          throw PlatformException(code: 'error', message: 'denied');
        }
        return _defaultHandler(call);
      });

      await expectLater(service.initialize(), completes);
    });

    test(
        'a missing exact-alarm permission during the cold-start re-arm does not stop initialize()',
        () async {
      // Fresh install, enabled by default, but the device hasn't granted
      // SCHEDULE_EXACT_ALARM yet — the re-arm attempt inside
      // _doInitialize() must not let that exception escape.
      useHandler((call) async {
        if (call.method == 'zonedSchedule') {
          throw PlatformException(
            code: 'exact_alarms_not_permitted',
            message: 'Exact alarms are not permitted',
          );
        }
        return _defaultHandler(call);
      });

      await expectLater(service.initialize(), completes);
    });

    test(
        're-arms the reminder on init because reminders are enabled by default',
        () async {
      // Fresh install: nothing in SharedPreferences yet, but isEnabled()
      // defaults to true, so initialize() should schedule the default time.
      await service.initialize();
      expect(calls.any((c) => c.method == 'zonedSchedule'), isTrue);
    });

    test('does not re-arm on init after the user has disabled reminders',
        () async {
      await service.initialize();
      await service.disableReminder();
      calls = [];

      // Simulate a fresh app start with a new service instance, same prefs.
      final restarted = NotificationService();
      await restarted.initialize();

      expect(calls.any((c) => c.method == 'zonedSchedule'), isFalse);
    });
  });

  group('scheduleDailyReminder', () {
    test('does nothing if the service has not been initialized', () async {
      await service.scheduleDailyReminder(hour: 14, minute: 30);
      expect(calls, isEmpty);
    });

    test('persists the requested time to SharedPreferences', () async {
      await service.initialize();
      calls = [];

      await service.scheduleDailyReminder(hour: 14, minute: 30);

      final time = await service.getScheduledTime();
      expect(time, const NotificationTime(hour: 14, minute: 30));
    });

    test('marks reminders as enabled again when scheduling', () async {
      await service.initialize();
      await service.disableReminder();

      await service.scheduleDailyReminder(hour: 7, minute: 0);

      expect(await service.isEnabled(), isTrue);
    });

    test('sends a zonedSchedule call to the plugin', () async {
      await service.initialize();
      calls = [];

      await service.scheduleDailyReminder(hour: 8, minute: 15);
      expect(calls.any((c) => c.method == 'zonedSchedule'), isTrue);
    });

    test('cancels the previous notification before rescheduling', () async {
      await service.initialize();
      calls = [];

      await service.scheduleDailyReminder(hour: 8, minute: 0);
      await service.scheduleDailyReminder(hour: 9, minute: 0);

      expect(calls.where((c) => c.method == 'cancel').length, 2);
    });

    test('falls back to an inexact alarm when the exact alarm is not permitted',
        () async {
      await service.initialize();
      calls = [];

      var zonedScheduleAttempts = 0;
      useHandler((call) async {
        if (call.method == 'zonedSchedule') {
          zonedScheduleAttempts++;
          if (zonedScheduleAttempts == 1) {
            throw PlatformException(
              code: 'exact_alarms_not_permitted',
              message: 'Exact alarms are not permitted',
            );
          }
        }
        return _defaultHandler(call);
      });

      final outcome = await service.scheduleDailyReminder(hour: 9, minute: 0);

      expect(outcome, ReminderScheduleOutcome.inexact);
      expect(zonedScheduleAttempts, 2);

      final retry = calls.lastWhere((c) => c.method == 'zonedSchedule');
      final platformSpecifics =
          (retry.arguments as Map)['platformSpecifics'] as Map;
      expect(platformSpecifics['scheduleMode'], 'inexactAllowWhileIdle');
    });
  });

  group('cancelAll', () {
    test('calls cancelAll on the plugin', () async {
      await service.cancelAll();
      expect(calls.any((c) => c.method == 'cancelAll'), isTrue);
    });
  });

  group('canScheduleExactAlarms', () {
    test('returns true when the plugin reports permission granted', () async {
      useHandler((call) async {
        if (call.method == 'canScheduleExactNotifications') return true;
        return _defaultHandler(call);
      });

      expect(await service.canScheduleExactAlarms(), isTrue);
    });

    test('returns false when the plugin reports permission denied', () async {
      useHandler((call) async {
        if (call.method == 'canScheduleExactNotifications') return false;
        return _defaultHandler(call);
      });

      expect(await service.canScheduleExactAlarms(), isFalse);
    });

    test('returns false instead of throwing if the plugin call itself fails',
        () async {
      useHandler((call) async {
        if (call.method == 'canScheduleExactNotifications') {
          throw PlatformException(code: 'error', message: 'boom');
        }
        return _defaultHandler(call);
      });

      await expectLater(service.canScheduleExactAlarms(), completion(isFalse));
    });
  });

  group('requestExactAlarmPermission', () {
    test(
        'returns the granted status reported after the user returns from settings',
        () async {
      useHandler((call) async {
        if (call.method == 'requestExactAlarmsPermission') return true;
        return _defaultHandler(call);
      });

      expect(await service.requestExactAlarmPermission(), isTrue);
    });

    test('returns false when the user does not grant the permission', () async {
      useHandler((call) async {
        if (call.method == 'requestExactAlarmsPermission') return false;
        return _defaultHandler(call);
      });

      expect(await service.requestExactAlarmPermission(), isFalse);
    });

    test('returns false instead of throwing if the plugin call itself fails',
        () async {
      useHandler((call) async {
        if (call.method == 'requestExactAlarmsPermission') {
          throw PlatformException(code: 'error', message: 'boom');
        }
        return _defaultHandler(call);
      });

      await expectLater(
          service.requestExactAlarmPermission(), completion(isFalse));
    });
  });

  group('showTestNotification', () {
    test('calls the plugin to show a notification immediately', () async {
      await service.showTestNotification();

      final showCall = calls.singleWhere((c) => c.method == 'show');
      final args = showCall.arguments as Map;
      expect(args['title'], 'GoodLoop test');
      expect(args['body'], 'Powiadomienia działają poprawnie 🚀');
    });

    test('does not modify any SharedPreferences values', () async {
      // Mirrors the real app: main.dart already called initialize() before
      // the settings screen (and its test button) is ever reachable, so
      // showTestNotification()'s own initialize() call is a no-op here —
      // isolating exactly what showTestNotification() itself does to prefs.
      await service.initialize();
      final keysBefore = (await SharedPreferences.getInstance()).getKeys();
      final before = await service.getScheduledTime();
      final enabledBefore = await service.isEnabled();

      await service.showTestNotification();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), keysBefore);
      expect(await service.getScheduledTime(), before);
      expect(await service.isEnabled(), enabledBefore);
    });

    test('does not touch the daily reminder schedule', () async {
      await service.initialize();
      await service.scheduleDailyReminder(hour: 8, minute: 0);
      calls = [];

      await service.showTestNotification();

      // Only the immediate "show" call — no cancel/zonedSchedule touching
      // the daily reminder.
      expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
      expect(calls.where((c) => c.method == 'cancel'), isEmpty);
      expect(await service.getScheduledTime(),
          const NotificationTime(hour: 8, minute: 0));
    });

    test('a plugin failure propagates to the caller instead of being swallowed',
        () async {
      useHandler((call) async {
        if (call.method == 'show') {
          throw PlatformException(code: 'error', message: 'boom');
        }
        return _defaultHandler(call);
      });

      await expectLater(
        service.showTestNotification(),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('disableReminder', () {
    test('cancels the plugin notification and persists disabled state',
        () async {
      await service.initialize();
      calls = [];

      await service.disableReminder();

      expect(calls.any((c) => c.method == 'cancel'), isTrue);
      expect(await service.isEnabled(), isFalse);
    });

    test('does not clear the previously chosen hour/minute', () async {
      await service.initialize();
      await service.scheduleDailyReminder(hour: 18, minute: 30);

      await service.disableReminder();

      final time = await service.getScheduledTime();
      expect(time, const NotificationTime(hour: 18, minute: 30));
    });
  });

  group('getScheduledTime', () {
    test('returns the 20:00 default when nothing has been configured',
        () async {
      final time = await service.getScheduledTime();
      expect(time, const NotificationTime(hour: 20, minute: 0));
    });

    test('returns a previously persisted time', () async {
      await service.initialize();
      await service.scheduleDailyReminder(hour: 21, minute: 45);

      final time = await service.getScheduledTime();
      expect(time, const NotificationTime(hour: 21, minute: 45));
    });
  });

  group('isEnabled', () {
    test('defaults to true when never configured', () async {
      expect(await service.isEnabled(), isTrue);
    });
  });

  group('NotificationSettings (Riverpod)', () {
    test('build() reflects the persisted scheduled time', () async {
      SharedPreferences.setMockInitialValues({
        'notificationHour': 11,
        'notificationMinute': 5,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final time = await container.read(notificationSettingsProvider.future);
      expect(time, const NotificationTime(hour: 11, minute: 5));
    });

    test('schedule() updates state and calls through to the service', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(notificationServiceProvider).initialize();
      calls = [];

      await container
          .read(notificationSettingsProvider.notifier)
          .schedule(16, 20);

      final state = container.read(notificationSettingsProvider);
      expect(state.value, const NotificationTime(hour: 16, minute: 20));
      expect(calls.any((c) => c.method == 'zonedSchedule'), isTrue);
    });
  });
}
