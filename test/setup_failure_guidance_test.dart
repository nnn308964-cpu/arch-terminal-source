import 'package:arch_terminal/terminal/setup_failure_guidance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'storage-full guidance explains that retry preserves the saved state',
    () {
      final guidance = setupFailureGuidance(
        phase: 'extracting',
        detail: 'There is not enough internal space to extract Arch Linux.',
        arabicUi: false,
      );

      expect(guidance, contains('free internal storage'));
      expect(guidance, contains('checkpoint'));
    },
  );

  test('network guidance explains byte-range resume', () {
    final guidance = setupFailureGuidance(
      phase: 'downloading',
      detail: 'Unable to download Arch Linux (HTTP 503)',
      arabicUi: true,
    );

    expect(guidance, contains('يستأنف التنزيل'));
  });
}
