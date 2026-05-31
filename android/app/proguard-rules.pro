# Flutter & Dart
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Suppress warnings from dependencies
-dontwarn javax.lang.model.element.Modifier

# Keep native methods (Rust cargokit, super_native_extensions, etc.)
-keepclasseswithmembernames class * {
    native <methods>;
}

# Google Sign-In
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Keep Sentry crash reporting classes
-keep class io.sentry.** { *; }
-dontwarn io.sentry.**

# Gson / JSON serialization (used by some plugins)
-keepattributes Signature
-keepattributes *Annotation*

# Keep R8 from stripping out native libraries
-keep class **.BuildConfig { *; }
