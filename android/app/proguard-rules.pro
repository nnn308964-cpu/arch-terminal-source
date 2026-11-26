# Arch Terminal release rules
# Keep Flutter plugin registrants and Android service entry points discoverable.
-keep class io.flutter.plugins.** { *; }
-keep class com.example.arch_terminal.** { *; }

# Keep native method names used by the embedded terminal/PTY integration.
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}
