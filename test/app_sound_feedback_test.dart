import 'package:arch_terminal/terminal/app_sound_feedback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses stable wire names for each local sound event', () {
    expect(AppSoundEvent.tap.wireName, 'tap');
    expect(AppSoundEvent.success.wireName, 'success');
    expect(AppSoundEvent.error.wireName, 'error');
    expect(AppSoundEvent.terminal.wireName, 'terminal');
  });
}
