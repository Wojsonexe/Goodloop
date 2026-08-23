import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goodloop/firebase_options.dart';
import 'app.dart';
import 'domain/providers/notification_service.dart';
import 'logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final notificationService =
      NotificationService(FlutterLocalNotificationsPlugin());
  try {
    await notificationService.initialize();
  } catch (e, stack) {
    // Notifications are not core to the app working — a failure here
    // (e.g. a device without Google Play Services) must not block startup.
    logger.e('❌ Failed to initialize NotificationService: $e', stackTrace: stack);
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(
    ProviderScope(
      overrides: [
        notificationServiceProvider.overrideWithValue(notificationService),
      ],
      child: const GoodLoopApp(),
    ),
  );
}
