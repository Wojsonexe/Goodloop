import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goodloop/firebase_options.dart';
import 'app.dart';
import 'package:goodloop/core/notifications/notification_service.dart';
import 'package:goodloop/core/utils/logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final notificationService = NotificationService();
  try {
    await notificationService.initialize();
  } catch (e, stack) {
    logger.e('❌ Failed to initialize NotificationService: $e',
        stackTrace: stack);
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
