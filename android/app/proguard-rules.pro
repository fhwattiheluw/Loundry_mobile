# Flutter
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**

# Google Mobile Ads
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# sqflite
-keep class com.tekartik.sqflite.** { *; }

# SQLCipher. Wajib: tanpa aturan ini R8 membuang kelas native pada build
# rilis, dan database terenkripsi gagal dibuka hanya di APK rilis,
# padahal mode debug terlihat baik-baik saja.
-keep class net.sqlcipher.** { *; }
-keep class net.sqlcipher.database.** { *; }

# Printer thermal
-keep class com.example.print_bluetooth_thermal.** { *; }

# Notifikasi lokal (pengingat backup). Plugin menyimpan jadwal sebagai JSON
# lewat Gson; tanpa aturan ini R8 mengubah nama kelasnya dan jadwal gagal
# dibaca ulang hanya di APK rilis.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
