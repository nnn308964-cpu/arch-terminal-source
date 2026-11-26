import 'dart:io';

import 'package:flutter/services.dart';

enum AppSoundEvent {
  tap('tap'),
  success('success'),
  error('error'),
  terminal('terminal');

  const AppSoundEvent(this.wireName);
  final String wireName;
}

class AppSoundFeedback {
  AppSoundFeedback._();

  static const _channel = MethodChannel(
    'com.example.arch_terminal/local_runtime',
  );

  static Future<void> play(AppSoundEvent event) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('playSoundFeedback', <String, String>{
      'event': event.wireName,
    });
  }
}
