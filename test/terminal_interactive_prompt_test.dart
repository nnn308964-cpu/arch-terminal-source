import 'package:arch_terminal/terminal/terminal_interactive_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'detects a package-manager confirmation without preserving its raw text',
    () {
      final prompt = detectTerminalInteractivePrompt(
        ':: Proceed with installation? [Y/n] ',
      );

      expect(prompt?.kind, TerminalInteractivePromptKind.confirmation);
      expect(prompt?.suggestedReply(arabicUi: false), 'Y');
      expect(prompt?.safeExcerpt, contains('[Y/n]'));
      expect(prompt?.summary(arabicUi: false), isNot(contains('Proceed')));
      expect(prompt?.summary(arabicUi: true), contains('إرسال Y'));
    },
  );

  test(
    'marks password-like requests as sensitive and never suggests a reply',
    () {
      final prompt = detectTerminalInteractivePrompt('Enter password:');

      expect(prompt?.kind, TerminalInteractivePromptKind.sensitive);
      expect(prompt?.safeExcerpt, isEmpty);
      expect(prompt?.allowsAgentReply, isFalse);
      expect(prompt?.suggestedReply(arabicUi: true), isNull);
    },
  );

  test('detects generic text input and rejects terminal control characters in replies', () {
    final prompt = detectTerminalInteractivePrompt('Choose an editor:');

    expect(prompt?.kind, TerminalInteractivePromptKind.textInput);
    expect(isSafeInteractiveTerminalReply('nano'), isTrue);
    expect(isSafeInteractiveTerminalReply('nano\nrm -rf /'), isFalse);
    expect(isSafeInteractiveTerminalReply('\u001b[A'), isFalse);
  });

  test('deduplicates a prompt emitted over split terminal chunks', () {
    final detector = TerminalInteractivePromptDetector();

    expect(detector.consume(':: Proceed with install'), isNull);
    expect(detector.consume('ation? [Y/n]'), isNotNull);
    expect(detector.consume(' [Y/n]'), isNull);
  });
}
