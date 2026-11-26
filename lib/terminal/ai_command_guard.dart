enum AiCommandRisk { normal, elevated, destructive }

class AiCommandReview {
  const AiCommandReview({
    required this.command,
    required this.risk,
    required this.reason,
    this.blocked = false,
  });

  final String command;
  final AiCommandRisk risk;
  final String? reason;
  final bool blocked;

  bool get requiresWarning => risk != AiCommandRisk.normal;
  bool get requiresTypedConfirmation => risk == AiCommandRisk.destructive;
}

/// A deliberately conservative local guard. It does not try to prove commands
/// safe; it identifies clear high-impact patterns before an AI proposal reaches
/// the PTY. Human confirmation remains mandatory for every AI-generated command.
AiCommandReview reviewAiCommand(
  String rawCommand, {
  List<String> blockedPatterns = const <String>[],
}) {
  final command = rawCommand.trim();
  final normalized = command.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  for (final rawPattern in blockedPatterns) {
    final pattern = rawPattern.trim().toLowerCase();
    if (pattern.isNotEmpty && normalized.contains(pattern)) {
      return AiCommandReview(
        command: command,
        risk: AiCommandRisk.elevated,
        reason: 'هذا الأمر يطابق قاعدة حظر محلية: $pattern',
        blocked: true,
      );
    }
  }

  const destructivePatterns = <String>[
    r'\brm\s+-[^\n]*r[^\n]*f\s+/(\s|$)',
    r'\brm\s+-[^\n]*f[^\n]*r\s+/(\s|$)',
    r'\bmkfs(\.|\s)',
    r'\bdd\s+.*\bof=/dev/',
    r'\b(shutdown|reboot|poweroff|halt)\b',
    r'\b:.*\(\).*\{.*\|.*&',
    r'\b(pacman|apt|apk)\s+.*\b(remove|purge|rsc)\b.*\b(base|bash|linux)',
    r'>\s*/dev/(block|mmcblk|sda)',
  ];
  for (final pattern in destructivePatterns) {
    if (RegExp(pattern).hasMatch(normalized)) {
      return AiCommandReview(
        command: command,
        risk: AiCommandRisk.destructive,
        reason: 'قد يحذف بيانات أو يوقف النظام أو يكتب إلى جهاز تخزين.',
      );
    }
  }

  const elevatedPatterns = <String>[
    r'\brm\s+-',
    r'\bchmod\s+-r',
    r'\bchown\s+-r',
    r'\b(pacman|apt|apk)\s+.*\b(remove|purge|rsc)\b',
    r'\b(curl|wget)\b.*\|\s*(sh|bash)',
    r'>\s*/etc/',
    r'\b/sdcard/',
  ];
  for (final pattern in elevatedPatterns) {
    if (RegExp(pattern).hasMatch(normalized)) {
      return AiCommandReview(
        command: command,
        risk: AiCommandRisk.elevated,
        reason: 'قد يغيّر ملفات أو حزم أو ينفّذ محتوى تم تنزيله.',
      );
    }
  }

  return AiCommandReview(
    command: command,
    risk: AiCommandRisk.normal,
    reason: null,
  );
}
