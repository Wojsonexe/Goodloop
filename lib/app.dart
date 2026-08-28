import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_theme.dart';
import 'core/lifecycle/app_lifecycle_provider.dart';
import 'core/notifications/notification_service.dart';
import 'core/router/app_router.dart';
import 'domain/providers/theme_provider.dart';

class GoodLoopApp extends ConsumerWidget {
  const GoodLoopApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    // Gdy aplikacja wraca na pierwszy plan po dłuższej nieobecności
    // (force-stop, wyczyszczenie alarmów przez OEM), przeplanuj przypomnienie.
    ref.listen<AppLifecycleState>(appLifecycleProvider, (prev, next) {
      if (next == AppLifecycleState.resumed &&
          prev != null &&
          prev != AppLifecycleState.resumed) {
        ref.read(notificationServiceProvider).rearmIfEnabled();
      }
    });

    return MaterialApp.router(
      title: 'GoodLoop',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
