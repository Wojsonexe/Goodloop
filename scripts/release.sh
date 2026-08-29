#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# GoodLoop release helper: build APK -> tag -> GitHub prerelease.
# Wersję czyta z pubspec.yaml (bump ręcznie przed uruchomieniem).
#
#   ./scripts/release.sh ["notatki do release'u"]

VERSION=$(grep -E '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//' | tr -d '[:space:]')
NAME=${VERSION%%+*}
TAG="v${NAME}"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG już istnieje — bumpnij 'version:' w pubspec.yaml." >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree brudny — zacommituj/wyczyść przed release'em." >&2
  exit 1
fi

echo "==> Build $TAG ($VERSION)"
flutter build apk --release --android-skip-build-dependency-validation

OUT="build/app/outputs/flutter-apk/goodloop-${NAME}.apk"
cp build/app/outputs/flutter-apk/app-release.apk "$OUT"

echo "==> Tag + push"
git tag -a "$TAG" -m "Release $TAG"
git push origin "$TAG"

echo "==> GitHub release"
gh release create "$TAG" "$OUT" \
  --title "$TAG" \
  --prerelease \
  --target "$(git rev-parse --abbrev-ref HEAD)" \
  --notes "${1:-Build testowy (debug-signed). Instalacja z nieznanych źródeł. Test przypomnień: zezwól na powiadomienia + „Alarmy i przypomnienia”, ustaw reminder na +2 min i zminimalizuj apkę.}"

gh release view "$TAG" --web
