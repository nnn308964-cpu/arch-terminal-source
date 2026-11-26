import 'package:flutter/services.dart';

enum InterfaceLanguage { arabic, english }

class TerminalPreferences {
  static const defaultFontSize = 12.0;
  static const minFontSize = 7.0;
  static const maxFontSize = 20.0;
  static const defaultSoundVolume = 0.35;
  static const _channel = MethodChannel(
    'com.example.arch_terminal/local_runtime',
  );

  TerminalPreferences._({
    required this.fontSize,
    required this.language,
    required this.sessionName,
    required this.soundEnabled,
    required this.soundVolume,
  });

  final double fontSize;
  final InterfaceLanguage language;
  final String sessionName;
  final bool soundEnabled;
  final double soundVolume;

  static Future<TerminalPreferences> load() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'terminalPreferences',
      );
      final values = raw?.map((key, value) => MapEntry(key.toString(), value));
      final font =
          (values?['fontSize'] as num?)?.toDouble().clamp(
            minFontSize,
            maxFontSize,
          ) ??
          defaultFontSize;
      final language = values?['language'] == 'en'
          ? InterfaceLanguage.english
          : InterfaceLanguage.arabic;
      final sessionName = values?['sessionName']?.toString().trim();
      final soundEnabled = values?['soundEnabled'] != false;
      final soundVolume =
          (values?['soundVolume'] as num?)?.toDouble().clamp(0.0, 1.0) ??
          defaultSoundVolume;
      return TerminalPreferences._(
        fontSize: font,
        language: language,
        sessionName: sessionName?.isNotEmpty == true ? sessionName! : 'Arch',
        soundEnabled: soundEnabled,
        soundVolume: soundVolume,
      );
    } on PlatformException {
      return TerminalPreferences._(
        fontSize: defaultFontSize,
        language: InterfaceLanguage.arabic,
        sessionName: 'Arch',
        soundEnabled: true,
        soundVolume: defaultSoundVolume,
      );
    }
  }

  Future<void> setFontSize(double value) => _channel.invokeMethod<void>(
    'setTerminalPreferences',
    <String, Object>{'fontSize': value.clamp(minFontSize, maxFontSize)},
  );

  Future<void> setSoundEnabled(bool value) => _channel.invokeMethod<void>(
    'setTerminalPreferences',
    <String, Object>{'soundEnabled': value},
  );

  Future<void> setSoundVolume(double value) => _channel.invokeMethod<void>(
    'setTerminalPreferences',
    <String, Object>{'soundVolume': value.clamp(0.0, 1.0)},
  );

  Future<void> setLanguage(InterfaceLanguage value) =>
      _channel.invokeMethod<void>('setTerminalPreferences', <String, Object>{
        'language': value == InterfaceLanguage.english ? 'en' : 'ar',
      });

  Future<void> setSessionName(String value) {
    final normalized = value.trim();
    final capped = normalized.length <= 32
        ? normalized
        : normalized.substring(0, 32);
    return _channel.invokeMethod<void>(
      'setTerminalPreferences',
      <String, Object>{'sessionName': capped},
    );
  }
}
