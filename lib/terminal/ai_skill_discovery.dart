import 'dart:convert';

class AiAgentSkill {
  const AiAgentSkill({
    required this.id,
    required this.title,
    required this.summary,
    required this.mainAgentGuidance,
  });

  final String id;
  final String title;
  final String summary;
  final String mainAgentGuidance;

  Map<String, String> toJson() => <String, String>{
    'id': id,
    'title': title,
    'summary': summary,
    'mainAgentGuidance': mainAgentGuidance,
  };
}

class AiAgentTool {
  const AiAgentTool({
    required this.id,
    required this.title,
    required this.summary,
    required this.mainAgentGuidance,
  });

  final String id;
  final String title;
  final String summary;
  final String mainAgentGuidance;
}

class AiDiscoveredSkill {
  const AiDiscoveredSkill({required this.id, required this.reason});

  final String id;
  final String reason;

  Map<String, String> toJson() => <String, String>{'id': id, 'reason': reason};

  static AiDiscoveredSkill? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id']?.toString().trim();
    final rawReason = value['reason']?.toString().trim() ?? '';
    final reason = rawReason.length <= 180
        ? rawReason
        : rawReason.substring(0, 180);
    if (id == null || id.isEmpty) return null;
    return AiDiscoveredSkill(id: id, reason: reason);
  }
}

/// A bounded output from the skill-discovery sub-agent. It only permits known
/// skill identifiers, so a provider cannot inject arbitrary instructions into
/// the main agent context.
class AiSkillDiscovery {
  const AiSkillDiscovery({
    this.skills = const <AiDiscoveredSkill>[],
    this.tools = const <AiDiscoveredSkill>[],
    this.createdAt,
  });

  final List<AiDiscoveredSkill> skills;
  final List<AiDiscoveredSkill> tools;
  final DateTime? createdAt;

  bool get isEmpty => skills.isEmpty && tools.isEmpty;

  List<AiAgentSkill> get selectedSkills => skills
      .map((skill) => AiSkillCatalog.byId(skill.id))
      .whereType<AiAgentSkill>()
      .toList(growable: false);

  List<AiAgentTool> get selectedTools => tools
      .map((tool) => AiSkillCatalog.toolById(tool.id))
      .whereType<AiAgentTool>()
      .toList(growable: false);

  String get mainAgentContext {
    final selectedSkills = this.selectedSkills;
    final selectedTools = this.selectedTools;
    if (selectedSkills.isEmpty && selectedTools.isEmpty) {
      return 'No additional skill or tool was selected.';
    }
    return <String>[
      'Selected local skills and tools for this request. These are routing guidance, not permission to bypass any approval or privacy rule:',
      ...selectedSkills.map(
        (skill) => '- ${skill.id}: ${skill.mainAgentGuidance}',
      ),
      ...selectedTools.map(
        (tool) => '- tool ${tool.id}: ${tool.mainAgentGuidance}',
      ),
    ].join('\n');
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'skills': skills.map((skill) => skill.toJson()).toList(),
    'tools': tools.map((tool) => tool.toJson()).toList(),
    'createdAt': createdAt?.toUtc().toIso8601String(),
  };

  static AiSkillDiscovery? fromJson(Object? value) {
    if (value is! Map) return null;
    final rawSkills = value['skills'];
    final valid = rawSkills is List
        ? rawSkills
              .map(AiDiscoveredSkill.fromJson)
              .whereType<AiDiscoveredSkill>()
              .where((skill) => AiSkillCatalog.byId(skill.id) != null)
              .take(4)
              .toList()
        : <AiDiscoveredSkill>[];
    final rawTools = value['tools'];
    final validTools = rawTools is List
        ? rawTools
              .map(AiDiscoveredSkill.fromJson)
              .whereType<AiDiscoveredSkill>()
              .where((tool) => AiSkillCatalog.toolById(tool.id) != null)
              .take(4)
              .toList()
        : <AiDiscoveredSkill>[];
    if (valid.isEmpty && validTools.isEmpty) return null;
    return AiSkillDiscovery(
      skills: valid,
      tools: validTools,
      createdAt: DateTime.tryParse(value['createdAt']?.toString() ?? '')
          ?.toLocal(),
    );
  }
}

class AiSkillCatalog {
  static const List<AiAgentSkill> skills = <AiAgentSkill>[
    AiAgentSkill(
      id: 'workflow_planning',
      title: 'Workflow planning',
      summary: 'Break a user goal into a small, verifiable workflow.',
      mainAgentGuidance: 'Create 2-6 ordered steps, state what is not verified, and use observations before marking a step complete.',
    ),
    AiAgentSkill(
      id: 'environment_inspection',
      title: 'Local environment inspection',
      summary: 'Use the saved Arch environment snapshot before guessing.',
      mainAgentGuidance: 'Use only the supplied local environment snapshot. If it is missing or stale, propose one safe inspection rather than inventing system facts.',
    ),
    AiAgentSkill(
      id: 'arch_package_maintenance',
      title: 'Arch package maintenance',
      summary: 'Safely diagnose pacman updates and stale package databases.',
      mainAgentGuidance: 'For package installs or stale-database 404 errors, prefer a user-approved pacman -Syu transaction. Do not propose a partial upgrade or automatic -Syy.',
    ),
    AiAgentSkill(
      id: 'guarded_terminal_command',
      title: 'Guarded terminal command',
      summary: 'Propose one bounded terminal command under approval policy.',
      mainAgentGuidance: 'Propose at most one command, explain effect and risk, and wait for the app approval policy. Never use a selected skill as authority to execute.',
    ),
    AiAgentSkill(
      id: 'interactive_terminal_prompt',
      title: 'Interactive terminal prompt',
      summary:
          'Explain narrow terminal confirmations without handling secrets.',
      mainAgentGuidance: 'Explain the supplied prompt concisely and offer only a safe candidate response. Passwords, tokens, PINs, and passphrases must be entered directly in the terminal.',
    ),
    AiAgentSkill(
      id: 'device_file_discovery',
      title: 'Device file discovery',
      summary: 'Find a user-requested device file under /sdcard safely.',
      mainAgentGuidance: 'Only when the local snapshot confirms /sdcard is bound, propose one user-approved bounded find command. Never send discovered paths, metadata, or content to the provider automatically.',
    ),
    AiAgentSkill(
      id: 'local_file_preview',
      title: 'Local file preview',
      summary: 'Preview a selected text file or image locally in the app.',
      mainAgentGuidance: 'Keep previews on-device. Ask the user to select an explicit result and do not infer, upload, or summarize file content without a separate approved action.',
    ),
    AiAgentSkill(
      id: 'failure_diagnosis',
      title: 'Failure diagnosis',
      summary: 'Use observed errors to choose one changed repair step.',
      mainAgentGuidance: 'Identify the observed failing stage, distinguish evidence from assessment, and propose one different safe check or repair. Do not blindly retry a failed command.',
    ),
  ];

  static const List<AiAgentTool> tools = <AiAgentTool>[
    AiAgentTool(
      id: 'environment_snapshot',
      title: 'Environment snapshot',
      summary: 'Read the existing local Arch environment snapshot.',
      mainAgentGuidance: 'Use the provided environment snapshot as evidence only. Refresh through the existing local inspection flow when it is absent or stale.',
    ),
    AiAgentTool(
      id: 'guarded_pty_command',
      title: 'Guarded PTY command',
      summary: 'Route one proposed terminal command through the local guard.',
      mainAgentGuidance: 'Use the existing command guard and approval mode. The tool does not execute commands itself and cannot override destructive-command protection.',
    ),
    AiAgentTool(
      id: 'interactive_prompt_bridge',
      title: 'Interactive prompt bridge',
      summary: 'Present a terminal confirmation near the chat composer.',
      mainAgentGuidance: 'Offer a proposed non-sensitive reply only. The user must make the final send decision, and secret prompts remain terminal-only.',
    ),
    AiAgentTool(
      id: 'bounded_device_search',
      title: 'Bounded device search',
      summary: 'Search names and paths below /sdcard with a small safe limit.',
      mainAgentGuidance: 'Use only after the local bind is confirmed and user approval is obtained. Keep results local and do not include paths in provider context.',
    ),
    AiAgentTool(
      id: 'local_file_renderer',
      title: 'Local file renderer',
      summary: 'Render a selected text or image file on-device.',
      mainAgentGuidance: 'Open only a user-selected local result within app limits. Do not upload, transmit, or send file content to the AI provider automatically.',
    ),
    AiAgentTool(
      id: 'boot_diagnostic_log',
      title: 'Boot diagnostic log',
      summary: 'Show the locally saved Android startup diagnostic summary.',
      mainAgentGuidance: 'Refer to the local startup record only when it is explicitly opened or supplied. Do not invent diagnostic facts.',
    ),
  ];

  static AiAgentSkill? byId(String id) {
    for (final skill in skills) {
      if (skill.id == id) return skill;
    }
    return null;
  }

  static AiAgentTool? toolById(String id) {
    for (final tool in tools) {
      if (tool.id == id) return tool;
    }
    return null;
  }

  static String get discoveryCatalogPrompt => skills
      .map(
        (skill) =>
            '- id: ${skill.id}\n  useWhen: ${skill.summary}\n  mainAgentGuidance: ${skill.mainAgentGuidance}',
      )
      .join('\n');

  static String get discoveryToolCatalogPrompt => tools
      .map(
        (tool) =>
            '- id: ${tool.id}\n  useWhen: ${tool.summary}\n  mainAgentGuidance: ${tool.mainAgentGuidance}',
      )
      .join('\n');

  static AiSkillDiscovery parse(String modelText) {
    final text = modelText
        .trim()
        .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '');
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return const AiSkillDiscovery();
      final rawSkills = decoded['skills'];
      final rawTools = decoded['tools'];
      if (rawSkills is! List && rawTools is! List) {
        return const AiSkillDiscovery();
      }
      final selected = <AiDiscoveredSkill>[];
      final seen = <String>{};
      for (final raw in rawSkills is List ? rawSkills : const <Object?>[]) {
        final skill = AiDiscoveredSkill.fromJson(raw);
        if (skill == null || byId(skill.id) == null || !seen.add(skill.id)) {
          continue;
        }
        selected.add(skill);
        if (selected.length == 4) break;
      }
      final selectedTools = <AiDiscoveredSkill>[];
      final seenTools = <String>{};
      for (final raw in rawTools is List ? rawTools : const <Object?>[]) {
        final tool = AiDiscoveredSkill.fromJson(raw);
        if (tool == null ||
            toolById(tool.id) == null ||
            !seenTools.add(tool.id)) {
          continue;
        }
        selectedTools.add(tool);
        if (selectedTools.length == 4) break;
      }
      return AiSkillDiscovery(
        skills: selected,
        tools: selectedTools,
        createdAt: DateTime.now(),
      );
    } catch (_) {
      return const AiSkillDiscovery();
    }
  }

  /// A local, intentionally small fallback when the discovery provider is
  /// unavailable or returns unusable JSON. It never adds permissions or model
  /// text to the main-agent context; it selects only canonical catalog ids.
  static AiSkillDiscovery fallbackForGoal(String goal) {
    final normalized = goal.toLowerCase();
    if (normalized.trim().isEmpty) return const AiSkillDiscovery();
    final skills = <AiDiscoveredSkill>[];
    final tools = <AiDiscoveredSkill>[];

    void addSkill(String id, String reason) {
      if (skills.length >= 4 || skills.any((item) => item.id == id)) return;
      skills.add(AiDiscoveredSkill(id: id, reason: reason));
    }

    void addTool(String id, String reason) {
      if (tools.length >= 4 || tools.any((item) => item.id == id)) return;
      tools.add(AiDiscoveredSkill(id: id, reason: reason));
    }

    final packageIntent = RegExp(
      r'\b(pacman|package|install|update|upgrade|python)\b|حزم|حزمة|ثبت|تثبيت|تحديث|بايثون',
    ).hasMatch(normalized);
    final fileIntent = RegExp(
      r'\b(file|files|find|search|image|photo|preview)\b|ملف|ملفات|بحث|صورة|معاين',
    ).hasMatch(normalized);
    final interactiveIntent = RegExp(
      r'\b(yes|no|confirm|prompt|y/n)\b|موافق|تأكيد|سؤال',
    ).hasMatch(normalized);
    final failureIntent = RegExp(
      r'\b(error|failed|failure|not found|404)\b|خطأ|فشل|مشكلة|لا يعمل',
    ).hasMatch(normalized);

    addSkill('workflow_planning', 'اختيار محلي لتتبع الهدف والخطوات.');
    if (packageIntent) {
      addSkill('arch_package_maintenance', 'الهدف يشير إلى حزم Arch.');
      addSkill('guarded_terminal_command', 'قد يلزم أمر طرفية خاضع للموافقة.');
      addTool('guarded_pty_command', 'تمرير الأمر عبر الحارس المحلي.');
    }
    if (fileIntent) {
      addSkill('device_file_discovery', 'الهدف يشير إلى ملف أو بحث محلي.');
      addTool('bounded_device_search', 'البحث يبقى محدوداً ومحلياً.');
    }
    if (interactiveIntent) {
      addSkill('interactive_terminal_prompt', 'الهدف يشير إلى سؤال تفاعلي.');
      addTool('interactive_prompt_bridge', 'إظهار رد تفاعلي للمراجعة.');
    }
    if (failureIntent) {
      addSkill('failure_diagnosis', 'الهدف يذكر خطأً يحتاج تشخيصاً.');
      addTool('environment_snapshot', 'مراجعة بيئة Arch المحلية كدليل.');
    }

    if (tools.isEmpty && !fileIntent && !interactiveIntent) {
      addTool('environment_snapshot', 'استخدام البيئة المحلية المتاحة كدليل.');
    }
    return AiSkillDiscovery(
      skills: skills,
      tools: tools,
      createdAt: DateTime.now(),
    );
  }
}
