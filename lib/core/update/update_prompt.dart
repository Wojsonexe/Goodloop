import 'dart:io' show File;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import 'app_release.dart';
import 'update_providers.dart';
import 'update_service.dart';

/// Wywołaj przy starcie ekranu (auto) albo z ustawień ([manual] = true).
Future<void> runUpdateCheck(
  BuildContext context,
  WidgetRef ref, {
  bool manual = false,
}) async {
  if (kIsWeb) return;
  final service = ref.read(updateServiceProvider);

  if (!manual && !await service.shouldAutoCheck()) return;

  AppRelease? release;
  try {
    release = await service.fetchUpdate();
    await service.markChecked();
  } catch (_) {
    if (manual && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nie udało się sprawdzić aktualizacji.')),
      );
    }
    return;
  }

  if (release == null) {
    if (manual && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masz najnowszą wersję. 🎉')),
      );
    }
    return;
  }

  if (!manual && await service.isSkipped(release)) return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(release: release!, service: service),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.release, required this.service});

  final AppRelease release;
  final UpdateService service;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  final _cancelToken = CancelToken();
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  @override
  void dispose() {
    if (!_cancelToken.isCancelled) _cancelToken.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });
    try {
      final File apk = await widget.service.downloadApk(
        widget.release,
        cancelToken: _cancelToken,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      final result = await widget.service.installApk(apk);
      if (!mounted) return;
      if (result.type == ResultType.done) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _downloading = false;
          _error = _installError(result);
        });
      }
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = CancelToken.isCancel(e)
            ? null
            : 'Pobieranie nie powiodło się. Sprawdź połączenie.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = 'Coś poszło nie tak przy instalacji.';
      });
    }
  }

  String _installError(OpenResult r) => switch (r.type) {
        ResultType.permissionDenied =>
          'Zezwól aplikacji na instalowanie z nieznanych źródeł i spróbuj ponownie.',
        ResultType.noAppToOpen => 'Brak instalatora pakietów na urządzeniu.',
        _ => r.message.isNotEmpty
            ? r.message
            : 'Nie udało się otworzyć instalatora.',
      };

  @override
  Widget build(BuildContext context) {
    final r = widget.release;
    final theme = Theme.of(context);
    final notes = _prettifyNotes(r.notes);

    return AlertDialog(
      title: Text('Nowa wersja ${r.version}'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (r.apkSizeLabel.isNotEmpty)
                Text('Rozmiar: ${r.apkSizeLabel}',
                    style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              Text('Co nowego', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(notes.isEmpty ? 'Poprawki i usprawnienia.' : notes,
                  style: theme.textTheme.bodyMedium),
              if (_downloading) ...[
                const SizedBox(height: 20),
                LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress),
                const SizedBox(height: 6),
                Text('Pobieranie… ${(_progress * 100).toStringAsFixed(0)}%',
                    style: theme.textTheme.bodySmall),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: _downloading
          ? [
              TextButton(
                onPressed: () => _cancelToken.cancel(),
                child: const Text('Anuluj'),
              ),
            ]
          : [
              if (!r.isPrerelease)
                TextButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    await widget.service.skip(r);
                    if (mounted) navigator.pop();
                  },
                  child: const Text('Pomiń'),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Później'),
              ),
              FilledButton(
                onPressed: _startDownload,
                child: Text(_error == null
                    ? 'Pobierz i zainstaluj'
                    : 'Spróbuj ponownie'),
              ),
            ],
    );
  }
}

/// Lekkie odchudzenie markdownu z release notes do czytelnego tekstu.
String _prettifyNotes(String md) {
  final out = <String>[];
  for (var line in md.split('\n')) {
    line = line.trimRight();
    line = line.replaceFirst(RegExp(r'^#{1,6}\s*'), '');
    line = line.replaceFirst(RegExp(r'^\s*[-*]\s+'), '• ');
    line = line.replaceAll(RegExp(r'\*\*|__|`'), '');
    out.add(line);
  }
  return out.join('\n').trim();
}
