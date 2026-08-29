import 'dart:io' show HttpClient;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:goodloop/config/api_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:goodloop/core/constants/app_colors.dart';
import 'package:goodloop/core/constants/storage_keys.dart';
import 'package:goodloop/core/notifications/notification_service.dart';
import 'package:goodloop/domain/providers/auth_provider.dart';
import 'package:goodloop/domain/providers/theme_provider.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final LocalAuthentication _localAuth = LocalAuthentication();

  bool _loading = true;

  // Powiadomienia
  bool _reminderEnabled = false;
  NotificationTime? _reminderTime;

  // Biometria
  bool _biometricSupported = false;
  bool _biometricEnabled = false;

  // Stopka
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = ref.read(notificationServiceProvider);

    final results = await Future.wait([
      service.isEnabled(),
      service.getScheduledTime(),
      _readBiometricState(),
      PackageInfo.fromPlatform(),
    ]);

    if (!mounted) return;
    final biometric = results[2] as ({bool supported, bool enabled});
    setState(() {
      _reminderEnabled = results[0] as bool;
      _reminderTime = results[1] as NotificationTime;
      _biometricSupported = biometric.supported;
      _biometricEnabled = biometric.enabled;
      _appVersion = 'GoodLoop v${(results[3] as PackageInfo).version}';
      _loading = false;
    });
  }

  Future<({bool supported, bool enabled})> _readBiometricState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(StorageKeys.biometricEnabled) ?? false;
      final supported = await _localAuth.canCheckBiometrics &&
          await _localAuth.isDeviceSupported();
      return (supported: supported, enabled: enabled);
    } catch (e) {
      debugPrint('[Settings] biometric state read failed: $e');
      return (supported: false, enabled: false);
    }
  }

  // ── Powiadomienia ─────────────────────────────────────────────────────────

  Future<void> _onReminderToggled(bool value) async {
    if (value) {
      await _pickReminderTime();
    } else {
      await ref.read(notificationServiceProvider).disableReminder();
      if (mounted) setState(() => _reminderEnabled = false);
    }
  }

  Future<void> _pickReminderTime() async {
    final base = _reminderTime ?? const NotificationTime(hour: 20, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
    );
    if (picked == null) return;
    if (!await _ensureExactAlarmPermission()) return;

    try {
      final outcome = await ref
          .read(notificationSettingsProvider.notifier)
          .schedule(picked.hour, picked.minute);

      if (!mounted) return;
      setState(() {
        _reminderEnabled = true;
        _reminderTime =
            NotificationTime(hour: picked.hour, minute: picked.minute);
      });
      _snack(outcome == ReminderScheduleOutcome.inexact
          ? 'Przypomnienie ustawione. Bez uprawnienia „Alarmy i przypomnienia” '
              'może przyjść z opóźnieniem.'
          : 'Przypomnienie ustawione na ${_fmt(_reminderTime!)}.');
    } catch (e) {
      if (mounted) _snack('Nie udało się ustawić przypomnienia: $e');
    }
  }

  /// true, gdy uprawnienie do dokładnych alarmów jest przyznane. Nie otwiera
  /// ustawień systemowych bez wcześniejszego wyjaśnienia po co.
  Future<bool> _ensureExactAlarmPermission() async {
    final service = ref.read(notificationServiceProvider);
    if (await service.canScheduleExactAlarms()) return true;
    if (!mounted) return false;

    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Potrzebne uprawnienie'),
        content: const Text(
          'Aby GoodLoop przypominał dokładnie o wybranej godzinie, potrzebuje '
          'uprawnienia „Alarmy i przypomnienia” w ustawieniach systemowych. '
          'Bez niego przypomnienie może nie przyjść o czasie.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Otwórz ustawienia'),
          ),
        ],
      ),
    );
    if (open != true) return false;

    final granted = await service.requestExactAlarmPermission();
    if (!granted && mounted) {
      _snack('Bez tego uprawnienia przypomnienie może nie przyjść o czasie.');
    }
    return granted;
  }

  Future<void> _sendTestNotification() async {
    try {
      await ref.read(notificationServiceProvider).showTestNotification();
      if (mounted) _snack('Wysłano testowe powiadomienie.');
    } catch (e) {
      if (mounted) _snack('Nie udało się wysłać powiadomienia: $e');
    }
  }

  // ── Biometria ─────────────────────────────────────────────────────────────

  Future<void> _toggleBiometrics(bool value) async {
    try {
      if (value) {
        final ok = await _localAuth.authenticate(
          localizedReason: 'Potwierdź, aby włączyć logowanie biometryczne',
        );
        if (!ok) return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(StorageKeys.biometricEnabled, value);
      if (mounted) setState(() => _biometricEnabled = value);
    } catch (e) {
      debugPrint('[Settings] biometric toggle failed: $e');
      if (mounted) _snack('Nie udało się zmienić ustawień biometrii.');
    }
  }

  // ── Konto ─────────────────────────────────────────────────────────────────

  Future<void> _changeUsername() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    final controller = TextEditingController(text: user.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zmień nazwę użytkownika'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nowa nazwa'),
          textInputAction: TextInputAction.done,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Zapisz'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || newName == user.displayName)
      return;
    try {
      await ref
          .read(userRepositoryProvider)
          .updateUser(user.uid, {'displayName': newName});
      if (mounted) _snack('Nazwa zaktualizowana.');
    } catch (e) {
      if (mounted) _snack('Nie udało się zmienić nazwy: $e');
    }
  }

  Future<void> _changePassword() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    final confirmed = await _confirm(
      title: 'Zmiana hasła',
      message:
          'Wyślemy link do zmiany hasła na ${user.email}. Działa tylko dla kont '
          'z hasłem (nie dla logowania przez Google).',
      confirmLabel: 'Wyślij link',
    );
    if (!confirmed) return;

    try {
      await ref.read(authControllerProvider.notifier).resetPassword(user.email);
      if (mounted) _snack('Link do zmiany hasła wysłany na ${user.email}.');
    } catch (e) {
      if (mounted) _snack('Nie udało się wysłać linku: $e');
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await _confirm(
      title: 'Usuń konto',
      message:
          'Konto i wszystkie dane zostaną trwale usunięte. Tej operacji nie '
          'można cofnąć.',
      confirmLabel: 'Usuń konto',
      destructive: true,
    );
    if (!confirmed) return;

    try {
      await ref.read(authRepositoryProvider).deleteAccount();
      if (mounted) context.go('/welcome');
    } catch (e) {
      if (mounted) {
        _snack('Nie udało się usunąć konta. Zaloguj się ponownie i spróbuj '
            'jeszcze raz.');
      }
    }
  }

  Future<void> _signOut() async {
    final confirmed = await _confirm(
      title: 'Wyloguj',
      message: 'Na pewno chcesz się wylogować?',
      confirmLabel: 'Wyloguj',
    );
    if (!confirmed) return;
    await ref.read(authControllerProvider.notifier).signOut();
    if (mounted) context.go('/welcome');
  }

  // ── Motyw ─────────────────────────────────────────────────────────────────

  Future<void> _pickTheme() async {
    final current = ref.read(themeModeProvider);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Motyw'),
        content: RadioGroup<ThemeMode>(
          groupValue: current,
          onChanged: (mode) {
            if (mode == null) return;
            ref.read(themeModeProvider.notifier).setThemeMode(mode);
            Navigator.pop(context);
          },
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<ThemeMode>(
                value: ThemeMode.light,
                title: Text('Jasny'),
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.dark,
                title: Text('Ciemny'),
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.system,
                title: Text('Systemowy'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpery UI ────────────────────────────────────────────────────────────

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: destructive
                ? ElevatedButton.styleFrom(backgroundColor: AppColors.error)
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _testApiConnection() async {
    final url = '${ApiConfig.baseUrl}/health';
    _snack('Łączę z $url …');
    final sw = Stopwatch()..start();
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final res = await (await client.getUrl(Uri.parse(url))).close();
      await res.drain<void>();
      client.close();
      if (mounted) {
        _snack('API ${res.statusCode} • ${sw.elapsedMilliseconds} ms');
      }
    } catch (e) {
      if (mounted) _snack('API błąd: $e');
    }
  }

  void _showApiConfig() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfiguracja API'),
        content: SelectableText(
          ApiConfig.debugInfo,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _fmt(NotificationTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _themeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'Jasny',
        ThemeMode.dark => 'Ciemny',
        ThemeMode.system => 'Systemowy',
      };

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ustawienia')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Powiadomienia', [
            SwitchListTile(
              secondary: const Icon(Icons.notifications_active),
              title: const Text('Codzienne przypomnienie'),
              subtitle: Text(
                _loading
                    ? 'Wczytywanie…'
                    : _reminderEnabled && _reminderTime != null
                        ? 'Codziennie o ${_fmt(_reminderTime!)}'
                        : 'Wyłączone',
              ),
              value: _reminderEnabled,
              onChanged: _loading ? null : _onReminderToggled,
            ),
            if (_reminderEnabled) ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Zmień godzinę'),
                subtitle: _reminderTime != null
                    ? Text('Teraz: ${_fmt(_reminderTime!)}')
                    : null,
                onTap: _pickReminderTime,
              ),
            ],
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.notifications_none),
              title: const Text('Wyślij testowe powiadomienie'),
              onTap: _sendTestNotification,
            ),
          ]),
          const SizedBox(height: 24),
          _section('Wygląd', [
            ListTile(
              leading: const Icon(Icons.brightness_6),
              title: const Text('Motyw'),
              subtitle: Text(_themeLabel(themeMode)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickTheme,
            ),
          ]),
          const SizedBox(height: 24),
          _section('Konto', [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Zmień nazwę użytkownika'),
              onTap: _changeUsername,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Zmień hasło'),
              onTap: _changePassword,
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint),
              title: const Text('Logowanie biometryczne'),
              subtitle: Text(
                _loading
                    ? 'Sprawdzanie…'
                    : !_biometricSupported
                        ? 'Niedostępne na tym urządzeniu'
                        : _biometricEnabled
                            ? 'Włączone'
                            : 'Wyłączone',
              ),
              value: _biometricSupported && _biometricEnabled,
              onChanged:
                  _loading || !_biometricSupported ? null : _toggleBiometrics,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('Usuń konto',
                  style: TextStyle(color: AppColors.error)),
              onTap: _deleteAccount,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.error),
              title: const Text('Wyloguj',
                  style: TextStyle(color: AppColors.error)),
              onTap: _signOut,
            ),
          ]),
          if (kDebugMode) ...[
            const SizedBox(height: 24),
            _section('Deweloper', [
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Konfiguracja API'),
                subtitle: Text(ApiConfig.baseUrl),
                onTap: _showApiConfig,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.wifi_tethering),
                title: const Text('Testuj połączenie (/health)'),
                onTap: _testApiConnection,
              ),
            ]),
          ],
          const SizedBox(height: 32),
          Center(
            child: Text(
              _appVersion.isEmpty ? '…' : _appVersion,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}
