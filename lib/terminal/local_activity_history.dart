import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ai_skill_discovery.dart';

enum LocalTerminalSessionStatus { active, ended, failed }

enum LocalCapabilityKind { skill, tool }

class LocalApprovedTerminalCommand {
  const LocalApprovedTerminalCommand({
    required this.command,
    required this.recordedAt,
  });

  final String command;
  final DateTime recordedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'command': command,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
  };

  static LocalApprovedTerminalCommand? fromJson(Object? value) {
    if (value is! Map) return null;
    final command = value['command']?.toString().trim();
    final recordedAt = DateTime.tryParse(value['recordedAt']?.toString() ?? '')
        ?.toLocal();
    if (command == null ||
        command.isEmpty ||
        command.length > 1200 ||
        command.contains('\n') ||
        command.contains('\r') ||
        recordedAt == null) {
      return null;
    }
    return LocalApprovedTerminalCommand(
      command: command,
      recordedAt: recordedAt,
    );
  }
}

class LocalTerminalSessionRecord {
  const LocalTerminalSessionRecord({
    required this.id,
    required this.label,
    required this.startedAt,
    required this.status,
    this.commands = const <LocalApprovedTerminalCommand>[],
    this.endedAt,
    this.exitCode,
  });

  final String id;
  final String label;
  final DateTime startedAt;
  final LocalTerminalSessionStatus status;
  final List<LocalApprovedTerminalCommand> commands;
  final DateTime? endedAt;
  final int? exitCode;

  LocalTerminalSessionRecord close({required int exitCode}) =>
      LocalTerminalSessionRecord(
        id: id,
        label: label,
        startedAt: startedAt,
        status: exitCode == 0
            ? LocalTerminalSessionStatus.ended
            : LocalTerminalSessionStatus.failed,
        commands: commands,
        endedAt: DateTime.now(),
        exitCode: exitCode,
      );

  LocalTerminalSessionRecord fail() => LocalTerminalSessionRecord(
    id: id,
    label: label,
    startedAt: startedAt,
    status: LocalTerminalSessionStatus.failed,
    commands: commands,
    endedAt: DateTime.now(),
    exitCode: null,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'status': status.name,
    'commands': commands.map((item) => item.toJson()).toList(),
    'endedAt': endedAt?.toUtc().toIso8601String(),
    'exitCode': exitCode,
  };

  static LocalTerminalSessionRecord? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id']?.toString().trim();
    final label = value['label']?.toString().trim();
    final startedAt = DateTime.tryParse(value['startedAt']?.toString() ?? '')
        ?.toLocal();
    final status = LocalTerminalSessionStatus.values
        .where((item) => item.name == value['status'])
        .cast<LocalTerminalSessionStatus?>()
        .firstOrNull;
    if (id == null ||
        id.isEmpty ||
        label == null ||
        label.isEmpty ||
        startedAt == null ||
        status == null) {
      return null;
    }
    return LocalTerminalSessionRecord(
      id: id,
      label: label.length <= 120 ? label : label.substring(0, 120),
      startedAt: startedAt,
      status: status,
      commands: value['commands'] is List
          ? (value['commands'] as List)
                .map(LocalApprovedTerminalCommand.fromJson)
                .whereType<LocalApprovedTerminalCommand>()
                .take(20)
                .toList()
          : const <LocalApprovedTerminalCommand>[],
      endedAt: DateTime.tryParse(value['endedAt']?.toString() ?? '')?.toLocal(),
      exitCode: (value['exitCode'] as num?)?.toInt(),
    );
  }

  LocalTerminalSessionRecord withApprovedCommand(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty ||
        trimmed.length > 1200 ||
        trimmed.contains('\n') ||
        _containsSensitiveAssignment(trimmed)) {
      return this;
    }
    return LocalTerminalSessionRecord(
      id: id,
      label: label,
      startedAt: startedAt,
      status: status,
      commands: <LocalApprovedTerminalCommand>[
        LocalApprovedTerminalCommand(
          command: trimmed,
          recordedAt: DateTime.now(),
        ),
        ...commands,
      ].take(20).toList(),
      endedAt: endedAt,
      exitCode: exitCode,
    );
  }

  static bool _containsSensitiveAssignment(String command) => RegExp(
    r'(?:password|passwd|token|api[_-]?key|secret)\s*=\s*[^\s;]+',
    caseSensitive: false,
  ).hasMatch(command);
}

class LocalCapabilityActivity {
  const LocalCapabilityActivity({
    required this.kind,
    required this.id,
    required this.discoveredAt,
    required this.lastUsedAt,
  });

  final LocalCapabilityKind kind;
  final String id;
  final DateTime discoveredAt;
  final DateTime lastUsedAt;

  String get favoriteKey => '${kind.name}:$id';

  LocalCapabilityActivity touch() => LocalCapabilityActivity(
    kind: kind,
    id: id,
    discoveredAt: discoveredAt,
    lastUsedAt: DateTime.now(),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'id': id,
    'discoveredAt': discoveredAt.toUtc().toIso8601String(),
    'lastUsedAt': lastUsedAt.toUtc().toIso8601String(),
  };

  static LocalCapabilityActivity? fromJson(Object? value) {
    if (value is! Map) return null;
    final kind = LocalCapabilityKind.values
        .where((item) => item.name == value['kind'])
        .cast<LocalCapabilityKind?>()
        .firstOrNull;
    final id = value['id']?.toString().trim();
    final discoveredAt = DateTime.tryParse(
      value['discoveredAt']?.toString() ?? '',
    )?.toLocal();
    final lastUsedAt = DateTime.tryParse(value['lastUsedAt']?.toString() ?? '')
        ?.toLocal();
    final known = kind == LocalCapabilityKind.skill
        ? AiSkillCatalog.byId(id ?? '') != null
        : AiSkillCatalog.toolById(id ?? '') != null;
    if (kind == null ||
        id == null ||
        id.isEmpty ||
        !known ||
        discoveredAt == null ||
        lastUsedAt == null) {
      return null;
    }
    return LocalCapabilityActivity(
      kind: kind,
      id: id,
      discoveredAt: discoveredAt,
      lastUsedAt: lastUsedAt,
    );
  }
}

class LocalActivityHistory {
  const LocalActivityHistory({
    this.sessions = const <LocalTerminalSessionRecord>[],
    this.capabilities = const <LocalCapabilityActivity>[],
    this.favoriteKeys = const <String>[],
  });

  final List<LocalTerminalSessionRecord> sessions;
  final List<LocalCapabilityActivity> capabilities;
  final List<String> favoriteKeys;

  bool isFavorite(LocalCapabilityActivity item) =>
      favoriteKeys.contains(item.favoriteKey);

  LocalActivityHistory recordSession(LocalTerminalSessionRecord record) =>
      LocalActivityHistory(
        sessions: _sessions(<LocalTerminalSessionRecord>[record, ...sessions]),
        capabilities: capabilities,
        favoriteKeys: favoriteKeys,
      );

  LocalActivityHistory replaceSession(LocalTerminalSessionRecord record) =>
      LocalActivityHistory(
        sessions: _sessions(<LocalTerminalSessionRecord>[
          record,
          ...sessions.where((item) => item.id != record.id),
        ]),
        capabilities: capabilities,
        favoriteKeys: favoriteKeys,
      );

  LocalActivityHistory deleteSession(String id) => LocalActivityHistory(
    sessions: sessions.where((item) => item.id != id).toList(),
    capabilities: capabilities,
    favoriteKeys: favoriteKeys,
  );

  LocalActivityHistory recordApprovedCommand(String sessionId, String command) {
    final matching = sessions.where((item) => item.id == sessionId).toList();
    return matching.isEmpty
        ? this
        : replaceSession(matching.first.withApprovedCommand(command));
  }

  LocalActivityHistory recordDiscovery(AiSkillDiscovery discovery) {
    final now = DateTime.now();
    final additions = <LocalCapabilityActivity>[
      ...discovery.selectedSkills.map(
        (skill) => LocalCapabilityActivity(
          kind: LocalCapabilityKind.skill,
          id: skill.id,
          discoveredAt: now,
          lastUsedAt: now,
        ),
      ),
      ...discovery.selectedTools.map(
        (tool) => LocalCapabilityActivity(
          kind: LocalCapabilityKind.tool,
          id: tool.id,
          discoveredAt: now,
          lastUsedAt: now,
        ),
      ),
    ];
    final next = <LocalCapabilityActivity>[];
    for (final item in <LocalCapabilityActivity>[
      ...additions,
      ...capabilities,
    ]) {
      final existingIndex = next.indexWhere(
        (current) => current.favoriteKey == item.favoriteKey,
      );
      if (existingIndex < 0) {
        next.add(item);
      } else if (additions.any(
        (added) => added.favoriteKey == item.favoriteKey,
      )) {
        next[existingIndex] = next[existingIndex].touch();
      }
      if (next.length >= 32) break;
    }
    return LocalActivityHistory(
      sessions: sessions,
      capabilities: next,
      favoriteKeys: favoriteKeys,
    );
  }

  LocalActivityHistory toggleFavorite(LocalCapabilityActivity item) {
    final next = <String>[...favoriteKeys];
    if (!next.remove(item.favoriteKey)) next.add(item.favoriteKey);
    return LocalActivityHistory(
      sessions: sessions,
      capabilities: capabilities,
      favoriteKeys: next.take(24).toList(),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'sessions': sessions.map((item) => item.toJson()).toList(),
    'capabilities': capabilities.map((item) => item.toJson()).toList(),
    'favoriteKeys': favoriteKeys,
  };

  static LocalActivityHistory fromJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const LocalActivityHistory();
      final sessions = decoded['sessions'] is List
          ? (decoded['sessions'] as List)
                .map(LocalTerminalSessionRecord.fromJson)
                .whereType<LocalTerminalSessionRecord>()
                .toList()
          : <LocalTerminalSessionRecord>[];
      final capabilities = decoded['capabilities'] is List
          ? (decoded['capabilities'] as List)
                .map(LocalCapabilityActivity.fromJson)
                .whereType<LocalCapabilityActivity>()
                .toList()
          : <LocalCapabilityActivity>[];
      final favorites = decoded['favoriteKeys'] is List
          ? (decoded['favoriteKeys'] as List)
                .map((item) => item.toString())
                .where(RegExp(r'^(skill|tool):[a-z_]+$').hasMatch)
                .take(24)
                .toList()
          : <String>[];
      return LocalActivityHistory(
        sessions: _sessions(sessions),
        capabilities: capabilities.take(32).toList(),
        favoriteKeys: favorites,
      );
    } catch (_) {
      return const LocalActivityHistory();
    }
  }

  static List<LocalTerminalSessionRecord> _sessions(
    Iterable<LocalTerminalSessionRecord> input,
  ) {
    final ordered = input.toList()
      ..sort((left, right) => right.startedAt.compareTo(left.startedAt));
    return ordered.take(24).toList();
  }
}

class LocalActivityHistoryStore {
  LocalActivityHistoryStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          FlutterSecureStorage(
            aOptions: AndroidOptions(migrateWithBackup: true),
          );

  static const _historyKey = 'arch_terminal.local_activity_history.v1';
  final FlutterSecureStorage _storage;

  Future<LocalActivityHistory> load() async => LocalActivityHistory.fromJson(
    await _storage.read(key: _historyKey) ?? '',
  );

  Future<void> save(LocalActivityHistory history) =>
      _storage.write(key: _historyKey, value: jsonEncode(history.toJson()));
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    for (final value in this) {
      return value;
    }
    return null;
  }
}
