enum TerminalCommandOutcome { success, failure, unconfirmed }

class TerminalCommandResult {
  const TerminalCommandResult({required this.outcome, required this.summary});

  final TerminalCommandOutcome outcome;
  final String summary;

  bool get isSuccess => outcome == TerminalCommandOutcome.success;
  bool get isFailure => outcome == TerminalCommandOutcome.failure;
}

TerminalCommandResult classifyTerminalCommandOutput(
  String output, {
  required bool arabicUi,
}) {
  final clean = output
      .replaceAll(RegExp(r'\x1b\[[0-?]*[ -/]*[@-~]'), '')
      .replaceAll('\r', '')
      .trim();
  final normalized = clean.toLowerCase();

  const failureMarkers = <String>[
    'error:',
    'errors occurred',
    'failed',
    'failure',
    'command not found',
    'not found',
    'no such file',
    'could not resolve host',
    'invalid url',
    'exit=failure',
  ];
  if (failureMarkers.any(normalized.contains)) {
    return TerminalCommandResult(
      outcome: TerminalCommandOutcome.failure,
      summary: arabicUi
          ? 'فشل الأمر وفق ملاحظة محلية. لم تُعرض المخرجات الخام؛ سيبقى Workflow بحاجة إلى معالجة مختلفة.'
          : 'The command failed according to a local observation. Raw terminal text is hidden; the workflow remains open for a different repair.',
    );
  }

  if (normalized.contains('there is nothing to do')) {
    return TerminalCommandResult(
      outcome: TerminalCommandOutcome.success,
      summary: arabicUi
          ? 'نجحت مزامنة قواعد الحزم؛ لا توجد تحديثات متاحة حالياً.'
          : 'Package databases synchronized successfully; there are no available updates.',
    );
  }

  const successMarkers = <String>[
    'installed',
    'upgraded',
    'exit=success',
    'transaction successfully finished',
    'complete!',
  ];
  if (successMarkers.any(normalized.contains)) {
    return TerminalCommandResult(
      outcome: TerminalCommandOutcome.success,
      summary: arabicUi
          ? 'تؤكد الملاحظة المحلية نجاح الأمر.'
          : 'The local observation confirms the command succeeded.',
    );
  }

  return TerminalCommandResult(
    outcome: TerminalCommandOutcome.unconfirmed,
    summary: clean.isEmpty
        ? (arabicUi
              ? 'لم تصل مخرجات كافية خلال نافذة الملاحظة. قد يستمر الأمر أو ينتظر إدخالاً؛ لا تُعلَّم المهمة مكتملة.'
              : 'No sufficient output arrived during the observation window. The command may still run or wait for input; the task is not marked complete.')
        : (arabicUi
              ? 'وصلت مخرجات محلية، لكن لا يوجد دليل نجاح أو فشل كافٍ بعد. تبقى المهمة قيد التحقق.'
              : 'Local output arrived, but it does not yet prove success or failure. The task remains under verification.'),
  );
}
