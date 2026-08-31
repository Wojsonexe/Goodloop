/// Jedno wydanie z GitHub Releases.
class AppRelease {
  const AppRelease({
    required this.tag,
    required this.name,
    required this.notes,
    required this.htmlUrl,
    required this.isPrerelease,
    required this.isDraft,
    required this.publishedAt,
    required this.apkUrl,
    required this.apkSize,
  });

  final String tag; // np. "v1.1.0"
  final String name; // tytuł wydania
  final String notes; // markdown z opisem zmian
  final String htmlUrl;
  final bool isPrerelease;
  final bool isDraft;
  final DateTime? publishedAt;
  final String? apkUrl; // browser_download_url pierwszego assetu .apk
  final int apkSize; // bajty

  /// Wersja bez prefiksu "v" i bez "+build".
  String get version {
    var v = tag.trim();
    if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
    final plus = v.indexOf('+');
    return plus == -1 ? v : v.substring(0, plus);
  }

  String get apkSizeLabel {
    if (apkSize <= 0) return '';
    return '${(apkSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static AppRelease? tryParse(Map<String, dynamic> json) {
    final tag = json['tag_name'] as String?;
    if (tag == null || tag.isEmpty) return null;

    Map<String, dynamic>? apk;
    for (final a in (json['assets'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()) {
      if ((a['name'] as String? ?? '').toLowerCase().endsWith('.apk')) {
        apk = a;
        break;
      }
    }

    final rawName = (json['name'] as String? ?? '').trim();
    return AppRelease(
      tag: tag,
      name: rawName.isNotEmpty ? rawName : tag,
      notes: (json['body'] as String? ?? '').trim(),
      htmlUrl: json['html_url'] as String? ?? '',
      isPrerelease: json['prerelease'] as bool? ?? false,
      isDraft: json['draft'] as bool? ?? false,
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      apkUrl: apk?['browser_download_url'] as String?,
      apkSize: (apk?['size'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Porównuje wersje semver (obsługuje "v", "+build", pre-release "-beta.1").
/// >0 gdy [a] nowsza, <0 gdy starsza, 0 gdy równe.
int compareVersions(String a, String b) {
  (List<int>, List<String>) parse(String v) {
    v = v.trim();
    if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
    final plus = v.indexOf('+');
    if (plus != -1) v = v.substring(0, plus);
    final dash = v.indexOf('-');
    final core = dash == -1 ? v : v.substring(0, dash);
    final pre = dash == -1 ? <String>[] : v.substring(dash + 1).split('.');
    final nums =
        core.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
    while (nums.length < 3) {
      nums.add(0);
    }
    return (nums, pre);
  }

  final (ca, pa) = parse(a);
  final (cb, pb) = parse(b);

  for (var i = 0; i < 3; i++) {
    final c = ca[i].compareTo(cb[i]);
    if (c != 0) return c;
  }
  if (pa.isEmpty && pb.isEmpty) return 0;
  if (pa.isEmpty) return 1; // 1.0.0 > 1.0.0-beta
  if (pb.isEmpty) return -1;
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final na = int.tryParse(pa[i]);
    final nb = int.tryParse(pb[i]);
    final int c;
    if (na != null && nb != null) {
      c = na.compareTo(nb);
    } else if (na != null) {
      c = -1;
    } else if (nb != null) {
      c = 1;
    } else {
      c = pa[i].compareTo(pb[i]);
    }
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}
