import 'terminal_command_outcome.dart';

String summarizeTerminalOutput(String output, {required bool arabicUi}) {
  return classifyTerminalCommandOutput(output, arabicUi: arabicUi).summary;
}
