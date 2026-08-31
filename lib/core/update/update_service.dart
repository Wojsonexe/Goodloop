import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_release.dart';

/// Sprawdzanie / pobieranie / instalacja aktualizacji APK z GitHub Releases.
///
/// Repo jest publiczne, więc API i pobieranie assetów działają bez tokenu.
/// UWAGA: podmiana wersji zadziała tylko gdy nowy APK jest podpisany TYM SAMYM
/// kluczem co zainstalowany (patrz android/app/build.gradle.kts).
class UpdateService {
  UpdateService({Dio? dio})
      // Własny Dio — bez interceptora tokena Firebase z dioProvider
      // (api.github.com odrzuciłoby nieznany Bearer).
      : _dio = dio ?? Dio();

  final Dio _dio;

  static const _repo = 'Wojsonexe/Goodloop';
  static const _autoCheckInterval = Duration(hours: 6);
  static const _prefsLastCheck = 'update_last_check_ms';
  static const _prefsSkippedTag = 'update_skipped_tag';

  Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// Zwraca nowsze wydanie albo null.
  Future<AppRelease?> fetchUpdate({bool allowPrerelease = true}) async {
    final current = await currentVersion();
    final res = await _dio.get<List<dynamic>>(
      'https://api.github.com/repos/$_repo/releases',
      queryParameters: {'per_page': 15},
      options: Options(headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'goodloop-app',
        'X-GitHub-Api-Version': '2022-11-28',
      }),
    );

    final releases = (res.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AppRelease.tryParse)
        .whereType<AppRelease>()
        .where((r) => !r.isDraft && r.apkUrl != null)
        .where((r) => allowPrerelease || !r.isPrerelease)
        .toList()
      ..sort((a, b) => compareVersions(b.version, a.version));

    if (releases.isEmpty) return null;
    final latest = releases.first;
    return compareVersions(latest.version, current) > 0 ? latest : null;
  }

  Future<bool> shouldAutoCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_prefsLastCheck) ?? 0;
    final elapsed = DateTime.now().millisecondsSinceEpoch - last;
    return elapsed >= _autoCheckInterval.inMilliseconds;
  }

  Future<void> markChecked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsLastCheck, DateTime.now().millisecondsSinceEpoch);
  }

  Future<bool> isSkipped(AppRelease r) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsSkippedTag) == r.tag;
  }

  Future<void> skip(AppRelease r) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsSkippedTag, r.tag);
  }

  Future<File> downloadApk(
    AppRelease release, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/goodloop-${release.tag}.apk');
    if (await file.exists()) await file.delete();

    await _dio.download(
      release.apkUrl!,
      file.path,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received / total);
      },
      options: Options(headers: {'User-Agent': 'goodloop-app'}),
    );
    return file;
  }

  Future<OpenResult> installApk(File apk) => OpenFilex.open(
        apk.path,
        type: 'application/vnd.android.package-archive',
      );
}
