import 'dart:io';

import 'package:flutter/services.dart';

import 'device_file_content_preview.dart';

class ArchRuntime {
  ArchRuntime._();

  static const _channel = MethodChannel(
    'com.example.arch_terminal/local_runtime',
  );
  static const _progressChannel = EventChannel(
    'com.example.arch_terminal/setup_progress',
  );

  static bool get isAndroid => Platform.isAndroid;

  static String _platformText(String arabic, String english) =>
      Platform.localeName.toLowerCase().startsWith('ar') ? arabic : english;

  static Future<Map<String, Object?>> status() async {
    if (!Platform.isAndroid) {
      return <String, Object?>{
        'supported': false,
        'installed': false,
        'message': _platformText(
          'Arch عبر PRoot متاح داخل التطبيق على Android فقط.',
          'Arch through PRoot is available in the app on Android only.',
        ),
      };
    }
    final result = await _channel.invokeMethod<Map<Object?, Object?>>('status');
    return _normalize(result);
  }

  static Future<Map<String, Object?>> installArch() async {
    if (!Platform.isAndroid) {
      return <String, Object?>{
        'supported': false,
        'installed': false,
        'message': _platformText(
          'لا يحتاج Windows وLinux إلى تثبيت rootfs لتشغيل shell المحلي.',
          'Windows and Linux do not need a rootfs installation to run the local shell.',
        ),
      };
    }
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'installArch',
    );
    return _normalize(result);
  }

  static Future<Map<String, Object?>> cancelArchDownload() async {
    if (!Platform.isAndroid) return <String, Object?>{};
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'cancelArchDownload',
    );
    return _normalize(result);
  }

  static Stream<Map<String, Object?>> setupProgress() {
    if (!Platform.isAndroid) return const Stream<Map<String, Object?>>.empty();
    return _progressChannel.receiveBroadcastStream().map((Object? event) {
      if (event is Map<Object?, Object?>) return _normalize(event);
      return <String, Object?>{};
    });
  }

  static Future<Map<String, Object?>> requestAllFilesAccess() async {
    if (Platform.isAndroid) {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'requestAllFilesAccess',
      );
      return _normalize(result);
    }
    return <String, Object?>{};
  }

  static Future<void> requestBatteryOptimizationExemption() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('requestBatteryOptimizationExemption');
    }
  }

  static Future<Map<String, Object?>> requestNotificationPermission() async {
    if (Platform.isAndroid) {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'requestNotificationPermission',
      );
      return _normalize(result);
    }
    return <String, Object?>{};
  }

  static Future<Map<String, Object?>> startTerminalSessionService() async {
    if (!Platform.isAndroid) return <String, Object?>{};
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'startTerminalSessionService',
    );
    return _normalize(result);
  }

  static Future<Map<String, Object?>> stopTerminalSessionService() async {
    if (!Platform.isAndroid) return <String, Object?>{};
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'stopTerminalSessionService',
    );
    return _normalize(result);
  }

  static Future<Map<String, Object?>> setTerminalBackgroundProtection(
    bool enabled,
  ) async {
    if (!Platform.isAndroid) return <String, Object?>{};
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'setTerminalBackgroundProtection',
      <String, bool>{'enabled': enabled},
    );
    return _normalize(result);
  }

  static Future<void> acknowledgeTerminalEndRequest() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('acknowledgeTerminalEndRequest');
    }
  }

  static Future<bool> consumeTerminalRestartRequest() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('consumeTerminalRestartRequest') ??
        false;
  }

  static Future<void> reportPacmanNetworkFailure(String message) async {
    if (Platform.isAndroid && message.isNotEmpty) {
      await _channel.invokeMethod<void>(
        'reportPacmanNetworkFailure',
        <String, String>{'message': message},
      );
    }
  }

  static Future<String> readDeepSessionTranscript() async {
    if (!Platform.isAndroid) return '';
    return await _channel.invokeMethod<String>('readDeepSessionTranscript') ??
        '';
  }

  static Future<void> appendDeepSessionTranscript(String text) async {
    if (Platform.isAndroid && text.isNotEmpty) {
      await _channel.invokeMethod<void>(
        'appendDeepSessionTranscript',
        <String, String>{'text': text},
      );
    }
  }

  static Future<void> shareTerminalLog(String text) async {
    if (Platform.isAndroid && text.isNotEmpty) {
      await _channel.invokeMethod<void>('shareTerminalLog', <String, String>{
        'text': text,
      });
    }
  }

  static Future<void> openStartupDiagnostics() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('openStartupDiagnostics');
    }
  }

  static Future<Map<String, Object?>> rootfsStorageSettings() async {
    if (!Platform.isAndroid) return <String, Object?>{};
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'rootfsStorageSettings',
    );
    return _normalize(result);
  }

  static Future<Map<String, Object?>> setRootfsStorageMode(String mode) async {
    if (!Platform.isAndroid) return <String, Object?>{};
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'setRootfsStorageMode',
      <String, String>{'mode': mode},
    );
    return _normalize(result);
  }

  static Future<Map<String, Object?>> openRootfsLocation() async {
    if (!Platform.isAndroid) return <String, Object?>{};
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'openRootfsLocation',
    );
    return _normalize(result);
  }

  static Future<Map<String, String>> prepareArchCommand() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Arch PRoot runtime is Android-only.');
    }
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'archCommand',
    );
    final values = _normalize(result);
    return values.map((key, value) => MapEntry(key, value.toString()));
  }

  static Future<Map<String, Object?>> archLaunchDiagnostics() async {
    if (!Platform.isAndroid) return <String, Object?>{};
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'archLaunchDiagnostics',
    );
    return _normalize(result);
  }

  static Future<DeviceFileContentPreview> previewDeviceFile(String path) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Device file previews are Android-only.');
    }
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'previewDeviceFile',
      <String, String>{'path': path},
    );
    return DeviceFileContentPreview.fromMap(_normalize(result));
  }

  static String get localShell {
    if (Platform.isWindows) {
      return Platform.environment['COMSPEC'] ?? r'C:\Windows\System32\cmd.exe';
    }
    if (Platform.isAndroid) return '/system/bin/sh';
    return Platform.environment['SHELL'] ?? '/bin/bash';
  }

  static List<String> get localShellArguments {
    if (Platform.isWindows) return const <String>[];
    return const <String>['-l'];
  }

  static Map<String, Object?> _normalize(Map<Object?, Object?>? raw) {
    if (raw == null) return <String, Object?>{};
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
}
