/// Removes only a visible interactive Bash prompt from selected terminal text.
///
/// The command and command output remain logical text. This keeps user output
/// copyable while preventing `[root@localhost ~]#` from polluting a paste.
final RegExp _interactivePrompt = RegExp(
  r'^\[[^\]@]+@[^\s\]]+\s+[^\]]*\][#$]\s?',
);

String withoutInteractivePrompts(String selectedText) => selectedText
    .split('\n')
    .map((line) => line.replaceFirst(_interactivePrompt, ''))
    .join('\n');
