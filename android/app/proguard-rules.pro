# ML Kit: używamy tylko alfabetu łacińskiego, pozostałe moduły językowe nie są dołączone
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
# PDF / skaner dokumentów
-keep class io.scanbot.** { *; }
-dontwarn org.bouncycastle.**
-dontwarn com.google.android.play.core.**
