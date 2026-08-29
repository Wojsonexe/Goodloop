# --- flutter_local_notifications / Gson ---
# R8 wycina generyczne sygnatury, przez co Gson.TypeToken rzuca
# "TypeToken must be created with a type argument" przy loadScheduledNotifications.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses,EnclosingMethod

-keep class com.dexterous.** { *; }

-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken