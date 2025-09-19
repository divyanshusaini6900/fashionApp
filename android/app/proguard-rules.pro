# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.embedding.** { *; }

# Play Core (Fix for missing classes)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Firebase Auth
-keep class com.google.firebase.auth.** { *; }
-keep class com.firebase.ui.auth.** { *; }

# Firebase Firestore
-keep class com.google.firebase.firestore.** { *; }
-keep class com.google.firestore.** { *; }

# Firebase Storage
-keep class com.google.firebase.storage.** { *; }

# Gson (used by Firebase)
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# OkHttp
-dontwarn okhttp3.**
-dontwarn okhttps.**
-keep class okhttp3.** { *; }

# Dio and network libraries
-keep class dio.** { *; }
-keep class io.flutter.plugin.network.** { *; }

# DNS and networking (critical for release builds)
-keep class java.net.** { *; }
-keep class javax.net.ssl.** { *; }
-keep class android.net.** { *; }
-keep class java.security.** { *; }
-dontwarn java.net.**
-dontwarn javax.net.ssl.**

# Background services and WorkManager
-keep class androidx.work.** { *; }
-keep class id.flutter.flutter_background_service.** { *; }
-keep class be.tramckrijte.workmanager.** { *; }
-dontwarn androidx.work.**

# Connectivity and network state
-keep class io.flutter.plugins.connectivity.** { *; }
-keep class dev.fluttercommunity.plus.connectivity.** { *; }

# Permission handler
-keep class com.baseflow.permissionhandler.** { *; }

# Image picker
-keep class io.flutter.plugins.imagepicker.** { *; }

# Cached network image
-keep class io.flutter.plugins.cachednetworkimage.** { *; }

# Device info plus
-keep class dev.fluttercommunity.plus.device_info.** { *; }

# Path provider
-keep class io.flutter.plugins.pathprovider.** { *; }

# URL launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# Keep your app's model classes
-keep class com.ratnawnai.RatNawnAI.** { *; }

# Keep native method names
-keepclassmembers class * {
    native <methods>;
}

# Razorpay specific rules
-keep class com.razorpay.** { *; }
-dontwarn com.razorpay.**
-keep class proguard.annotation.** { *; }
-dontwarn proguard.annotation.**

# General rules
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Application
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.content.ContentProvider

# Prevent obfuscation of types which need reflection
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
