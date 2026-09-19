# The Flutter ML Kit bridge supports scripts that are optional at the app level.
# This build deliberately ships Chinese and Latin recognition only.
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
