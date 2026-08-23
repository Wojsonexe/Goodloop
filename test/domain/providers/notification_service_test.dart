import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goodloop/domain/providers/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

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
    // Needed for tz.local / TZDateTime math used by scheduling.
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
    // The service only ever exercises the Android-specific plugin code
    // paths (this app targets Android) — pin the platform so tests behave
    // the same regardless of the host OS running `flutter test`.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    calls = [];
    useHandler(_defaultHandler);
    service = NotificationService(FlutterLocalNotificationsPlugin());
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('initialize', () {
    test('only performs native initialization once across repeated calls', () async {
      await service.initialize();
      await service.initialize();
      await service.initialize();

      expect(calls.where((c) => c.method == 'initialize').length, 1);
    });

    test('concurrent calls do not race into multiple native initializations', () async {
      await Future.wait([
        service.initialize(),
        service.initialize(),
        service.initialize(),
      ]);

      expect(calls.where((c) => c.method == 'initialize').length, 1);
    });

    test('requests the Android notification permission during init', () async {
      await service.initialize();
      expect(calls.where((c) => c.method == 'requestNotificationsPermission').length, 1);
    });

    test('a permission-request failure does not stop initialize() from completing', () async {
      useHandler((call) async {
        if (call.method == 'requestNotificationsPermission') {
          throw PlatformException(code: 'error', message: 'denied');
        }
        return _defaultHandler(call);
      });

      await expectLater(service.initialize(), completes);
    });

    test('plugin.initialize() reporting failure (false) does not throw', () async {
      useHandler((call) async {
        if (call.method == 'initialize') return false;
        return _defaultHandler(call);
      });

      await expectLater(service.initialize(), completes);
    });
  });

  group('scheduleDailyReminder', () {
    test('persists the requested time to SharedPreferences', () async {
      await service.scheduleDailyReminder(hour: 14, minute: 30);

      final time = await service.getScheduledTime();
      expect(time, const NotificationTime(hour: 14, minute: 30));
    });

    test('sends a zonedSchedule call to the plugin', () async {
      await service.scheduleDailyReminder(hour: 8, minute: 15);
      expect(calls.any((c) => c.method == 'zonedSchedule'), isTrue);
    });

    test('cancels the previous notification before rescheduling', () async {
      await service.scheduleDailyReminder(hour: 8, minute: 0);
      await service.scheduleDailyReminder(hour: 9, minute: 0);

      expect(calls.where((c) => c.method == 'cancel').length, 2);
    });

    test('a scheduling failure surfaces to the caller instead of failing silently', () async {
      useHandler((call) async {
        if (call.method == 'zonedSchedule') {
          throw PlatformException(code: 'error', message: 'boom');
        }
        return _defaultHandler(call);
      });

      await expectLater(
        service.scheduleDailyReminder(hour: 9, minute: 0),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('cancelNotifications', () {
    test('clears the persisted scheduled time back to defaults', () async {
      await service.scheduleDailyReminder(hour: 14, minute: 30);
      await service.cancelNotifications();

      final time = await service.getScheduledTime();
      expect(time, const NotificationTime(hour: 9, minute: 0));
      expect(await service.hasScheduledReminder(), isFalse);
    });

    test('calls cancelAll on the plugin', () async {
      await service.cancelNotifications();
      expect(calls.any((c) => c.method == 'cancelAll'), isTrue);
    });
  });

  group('getScheduledTime', () {
    test('returns the 9:00 default when nothing has been configured', () async {
      final time = await service.getScheduledTime();
      expect(time, const NotificationTime(hour: 9, minute: 0));
    });

    test('returns a previously persisted time', () async {
      await service.scheduleDailyReminder(hour: 21, minute: 45);
      final time = await service.getScheduledTime();
      expect(time, const NotificationTime(hour: 21, minute: 45));
    });

    test('does not crash when SharedPreferences has no data at all', () async {
      SharedPreferences.setMockInitialValues({});
      await expectLater(service.getScheduledTime(), completes);
    });
  });

  group('hasScheduledReminder', () {
    test('is false before any schedule call', () async {
      expect(await service.hasScheduledReminder(), isFalse);
    });

    test('is true after scheduling', () async {
      await service.scheduleDailyReminder(hour: 7, minute: 0);
      expect(await service.hasScheduledReminder(), isTrue);
    });
  });

  group('re-arming on initialize', () {
    test('re-schedules automatically when a time was already configured', () async {
      // Simulate a previous session having configured a reminder.
      SharedPreferences.setMockInitialValues({
        'notificationHour': 18,
        'notificationMinute': 0,
      });
      calls = [];

      await service.initialize();

      expect(calls.any((c) => c.method == 'zonedSchedule'), isTrue);
    });

    test('does not schedule anything on a fresh install with no prior config', () async {
      await service.initialize();
      expect(calls.any((c) => c.method == 'zonedSchedule'), isFalse);
    });
  });

  group('NotificationService.nextInstanceOf', () {
    test('always returns a time at or after now', () {
      final result = NotificationService.nextInstanceOf(9, 0);
      final now = tz.TZDateTime.now(tz.local);
      expect(result.isBefore(now), isFalse);
    });

    test('never more than 24 hours away', () {
      final result = NotificationService.nextInstanceOf(9, 0);
      final diff = result.difference(tz.TZDateTime.now(tz.local));
      expect(diff.inHours, lessThanOrEqualTo(24));
    });

    test('produces the requested hour and minute', () {
      final result = NotificationService.nextInstanceOf(13, 37);
      expect(result.hour, 13);
      expect(result.minute, 37);
    });
  });
}
