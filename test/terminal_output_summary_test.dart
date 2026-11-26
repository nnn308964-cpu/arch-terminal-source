import 'package:arch_terminal/terminal/terminal_output_summary.dart';
import 'package:arch_terminal/terminal/terminal_command_outcome.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('summarizes a no-update pacman result locally', () {
    expect(
      summarizeTerminalOutput(
        '\x1b[1;34m::\x1b[0m Starting full system upgrade...\nthere is nothing to do',
        arabicUi: true,
      ),
      'نجحت مزامنة قواعد الحزم؛ لا توجد تحديثات متاحة حالياً.',
    );
  });

  test(
    'returns a privacy-preserving local summary instead of terminal text',
    () {
      const rawOutput =
          'error: secret-token-123 must never be copied to the agent chat';
      final summary = summarizeTerminalOutput(rawOutput, arabicUi: false);

      expect(summary, contains('Raw terminal text is hidden'));
      expect(summary, isNot(contains('secret-token-123')));
      expect(summary, isNot(contains(rawOutput)));
    },
  );

  test('classifies an explicit package error as failure', () {
    final result = classifyTerminalCommandOutput(
      'error: failed to commit transaction (failed to retrieve some files)',
      arabicUi: true,
    );

    expect(result.outcome, TerminalCommandOutcome.failure);
    expect(result.summary, isNot(contains('retrieve some files')));
  });

  test('does not mark ambiguous output as successful', () {
    final result = classifyTerminalCommandOutput(
      ':: checking package integrity...\n:: processing package changes...',
      arabicUi: false,
    );

    expect(result.outcome, TerminalCommandOutcome.unconfirmed);
    expect(result.summary, contains('does not yet prove success'));
  });
}
