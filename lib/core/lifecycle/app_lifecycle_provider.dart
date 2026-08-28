import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bieżący [AppLifecycleState] jako provider — kontrolery reagują na
/// przejścia foreground/background bez własnego [WidgetsBindingObserver].
/// Wersja manualna (bez @riverpod), bo build_runner jest chwilowo zepsuty
/// przez rozjazd analyzer 7.x vs Dart 3.13.
class AppLifecycleController extends Notifier<AppLifecycleState>
    with WidgetsBindingObserver {
  @override
  AppLifecycleState build() {
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    ref.onDispose(() => binding.removeObserver(this));
    return binding.lifecycleState ?? AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    this.state = state;
  }
}

final appLifecycleProvider =
    NotifierProvider<AppLifecycleController, AppLifecycleState>(
  AppLifecycleController.new,
);
