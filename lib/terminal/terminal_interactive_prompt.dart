enum TerminalInteractivePromptKind { confirmation, textInput, sensitive }

class TerminalInteractivePrompt {
  const TerminalInteractivePrompt._({
    required this.kind,
    required this.signature,
    required this.safeExcerpt,
    this.assistantExplanation,
    this.assistantReply,
    this.analysisInProgress = false,
  });

  final TerminalInteractivePromptKind kind;
  final String signature;
  final String safeExcerpt;
  final String? assistantExplanation;
  final String? assistantReply;
  final bool analysisInProgress;

  TerminalInteractivePrompt copyWith({
    String? assistantExplanation,
    String? assistantReply,
    bool? analysisInProgress,
  }) => TerminalInteractivePrompt._(
    kind: kind,
    signature: signature,
    safeExcerpt: safeExcerpt,
    assistantExplanation: assistantExplanation ?? this.assistantExplanation,
    assistantReply: assistantReply ?? this.assistantReply,
    analysisInProgress: analysisInProgress ?? this.analysisInProgress,
  );

  String summary({required bool arabicUi}) => switch (kind) {
    TerminalInteractivePromptKind.confirmation =>
      arabicUi
          ? 'الطرفية تنتظر موافقتك. إرسال Y سيكمل العملية التي بدأتها في الطرفية.'
          : 'The terminal is waiting for your approval. Sending Y continues the operation you started in the terminal.',
    TerminalInteractivePromptKind.textInput =>
      arabicUi
          ? 'الطرفية تطلب إدخال نص للمتابعة.'
          : 'The terminal is asking for text input before continuing.',
    TerminalInteractivePromptKind.sensitive =>
      arabicUi
          ? 'الطرفية تطلب قيمة حساسة؛ اكتبها مباشرةً في الطرفية ولا ترسلها إلى الوكيل.'
          : 'The terminal is asking for a sensitive value; enter it directly in the terminal and do not send it to the agent.',
  };

  String? suggestedReply({required bool arabicUi}) =>
      assistantReply ??
      switch (kind) {
        TerminalInteractivePromptKind.confirmation => 'Y',
        TerminalInteractivePromptKind.textInput => null,
        TerminalInteractivePromptKind.sensitive => null,
      };

  bool get allowsAgentReply => kind != TerminalInteractivePromptKind.sensitive;
}

class TerminalInteractivePromptDetector {
  TerminalInteractivePromptDetector({this.maxTailChars = 640});

  final int maxTailChars;
  String _tail = '';
  String? _lastSignature;

  TerminalInteractivePrompt? consume(String terminalText) {
    if (terminalText.isEmpty) return null;
    _tail += _stripAnsi(terminalText);
    if (_tail.length > maxTailChars) {
      _tail = _tail.substring(_tail.length - maxTailChars);
    }
    final next = detectTerminalInteractivePrompt(_tail);
    if (next == null || next.signature == _lastSignature) return null;
    _lastSignature = next.signature;
    return next;
  }

  void clear() {
    _tail = '';
    _lastSignature = null;
  }
}

TerminalInteractivePrompt? detectTerminalInteractivePrompt(String output) {
  final normalized = _stripAnsi(output).replaceAll('\r', '\n').trimRight();
  if (normalized.isEmpty) return null;
  final recent = normalized.length > 240
      ? normalized.substring(normalized.length - 240)
      : normalized;
  final lower = recent.toLowerCase();

  if (RegExp(
    r'\b(password|passphrase|secret|token|otp|pin)\b\s*[:?]?',
    caseSensitive: false,
  ).hasMatch(lower)) {
    return TerminalInteractivePrompt._(
      kind: TerminalInteractivePromptKind.sensitive,
      signature: 'sensitive',
      safeExcerpt: '',
    );
  }
  if (RegExp(r'(\[y/n\]|\[Y/n\]|\(y/n\)|\(Y/n\))').hasMatch(recent) &&
      RegExp(
        r'\b(proceed|continue|install|remove|upgrade|confirm|sure)\b',
        caseSensitive: false,
      ).hasMatch(recent)) {
    return TerminalInteractivePrompt._(
      kind: TerminalInteractivePromptKind.confirmation,
      signature: 'confirmation',
      safeExcerpt: _safePromptExcerpt(recent),
    );
  }
  if (RegExp(
    r'\b(enter|input|choose|select|provide|type)\b[^\n]{0,96}[:?]',
    caseSensitive: false,
  ).hasMatch(recent)) {
    return TerminalInteractivePrompt._(
      kind: TerminalInteractivePromptKind.textInput,
      signature: 'text-input',
      safeExcerpt: _safePromptExcerpt(recent),
    );
  }
  return null;
}

bool isSafeInteractiveTerminalReply(String reply) {
  final trimmed = reply.trim();
  return trimmed.isNotEmpty &&
      trimmed.length <= 256 &&
      !RegExp(r'[\r\n\u0000\u001B]').hasMatch(trimmed);
}

String _stripAnsi(String value) => value.replaceAll(
  RegExp(r'\x1B(?:\][^\x07]*(?:\x07|\x1B\\)|\[[0-?]*[ -/]*[@-~])'),
  '',
);

String _safePromptExcerpt(String text) {
  final line = text
      .split('\n')
      .lastWhere((candidate) => candidate.trim().isNotEmpty, orElse: () => '')
      .trim();
  return line.length <= 240 ? line : line.substring(line.length - 240);
}
