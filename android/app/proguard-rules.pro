# flutter_local_notifications 用 Gson 把已排程通知序列化进 SharedPreferences，
# 反序列化走 TypeToken 子类。R8 full mode（AGP 8 release 默认开启，Flutter 插件
# isMinifyEnabled=true）会剥掉泛型签名，导致 cancel/save 抛
# PlatformException("Missing type parameter")。按 Gson 官方 full-mode 规则保留：
-keepattributes Signature
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# 通知插件模型类经 Gson 反射读写，字段名不能被混淆
-keep class com.dexterous.flutterlocalnotifications.** { *; }
