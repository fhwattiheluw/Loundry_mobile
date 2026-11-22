#!/usr/bin/env bash
#
# Melengkapi berkas platform yang tidak ikut masuk git: Gradle wrapper,
# ikon aplikasi, dan proyek iOS.
#
# Skrip ini sengaja TIDAK menjalankan `flutter create .` langsung di repo,
# karena perintah itu akan menimpa AndroidManifest.xml dan build.gradle yang
# sudah disesuaikan untuk izin Bluetooth, AdMob, dan konfigurasi rilis.
#
# Cukup dijalankan sekali setelah clone:
#   bash tool/bootstrap.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK tidak ditemukan. Pasang dulu: https://docs.flutter.dev/get-started/install"
  exit 1
fi

echo "==> Membuat proyek sementara untuk mengambil berkas platform"
flutter create \
  --org com.laundrypos \
  --project-name laundry_pos \
  --platforms=android \
  "$TEMP_DIR/scaffold" >/dev/null

SCAFFOLD="$TEMP_DIR/scaffold"

echo "==> Menyalin Gradle wrapper"
mkdir -p "$REPO_ROOT/android/gradle/wrapper"
cp "$SCAFFOLD/android/gradlew" "$REPO_ROOT/android/gradlew"
cp "$SCAFFOLD/android/gradlew.bat" "$REPO_ROOT/android/gradlew.bat"
cp "$SCAFFOLD/android/gradle/wrapper/gradle-wrapper.jar" \
   "$REPO_ROOT/android/gradle/wrapper/gradle-wrapper.jar"
chmod +x "$REPO_ROOT/android/gradlew"

# Ikon Laundry Manise sudah ada di dalam git. Yang disalin dari scaffold
# hanya ikon bawaan Flutter, jadi penyalinan dilewati bila ikon kita ada.
if [ -f "$REPO_ROOT/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" ]; then
  echo "==> Ikon aplikasi sudah ada, dilewati"
else
  echo "==> Menyalin ikon aplikasi bawaan"
  for density in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
    mkdir -p "$REPO_ROOT/android/app/src/main/res/mipmap-$density"
    cp "$SCAFFOLD/android/app/src/main/res/mipmap-$density/ic_launcher.png" \
       "$REPO_ROOT/android/app/src/main/res/mipmap-$density/ic_launcher.png"
  done
fi

echo "==> Mengambil dependensi"
cd "$REPO_ROOT"
flutter pub get

echo
echo "Selesai. Langkah berikutnya:"
echo "  flutter test          # jalankan pengujian"
echo "  flutter run           # jalankan di perangkat Android"
echo
echo "Catatan: ikon yang disalin masih ikon bawaan Flutter."
echo "Ganti berkas di android/app/src/main/res/mipmap-* dengan logo laundry Anda."
