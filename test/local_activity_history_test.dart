import 'dart:convert';

import 'package:arch_terminal/terminal/ai_skill_discovery.dart';
import 'package:arch_terminal/terminal/local_activity_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'stores a bounded terminal session record without terminal contents',
    () {
      final started = DateTime.utc(2026, 8, 23, 20);
      final record = LocalTerminalSessionRecord(
        id: 'session-1',
        label: 'Arch',
        startedAt: started,
        status: LocalTerminalSessionStatus.active,
      );
      final history = const LocalActivityHistory()
          .recordSession(record)
          .replaceSession(record.close(exitCode: 0));
      final restored = LocalActivityHistory.fromJson(
        jsonEncode(history.toJson()),
      );

      expect(restored.sessions.single.label, 'Arch');
      expect(restored.sessions.single.status, LocalTerminalSessionStatus.ended);
      expect(restored.sessions.single.exitCode, 0);
      expect(jsonEncode(restored.toJson()), isNot(contains('terminal output')));
    },
  );

  test(
    'keeps approved commands locally but excludes sensitive assignments',
    () {
      final record = LocalTerminalSessionRecord(
        id: 'session-commands',
        label: 'Arch',
        startedAt: DateTime.utc(2026, 8, 23, 20),
        status: LocalTerminalSessionStatus.active,
      );
      final history = const LocalActivityHistory()
          .recordSession(record)
          .recordApprovedCommand(record.id, 'pacman -Syu')
          .recordApprovedCommand(record.id, 'TOKEN=should-not-be-stored');
      final restored = LocalActivityHistory.fromJson(
        jsonEncode(history.toJson()),
      );

      expect(restored.sessions.single.commands, hasLength(1));
      expect(restored.sessions.single.commands.single.command, 'pacman -Syu');
      expect(
        jsonEncode(restored.toJson()),
        isNot(contains('should-not-be-stored')),
      );
    },
  );

  test(
    'records discovered canonical capabilities and toggles a local favorite',
    () {
      final discovery = AiSkillCatalog.parse(
        jsonEncode(<String, Object?>{
          'skills': <Object?>[
            <String, String>{'id': 'arch_package_maintenance', 'reason': 'x'},
          ],
          'tools': <Object?>[
            <String, String>{'id': 'guarded_pty_command', 'reason': 'x'},
          ],
        }),
      );
      final history = const LocalActivityHistory().recordDiscovery(discovery);
      final skill = history.capabilities.firstWhere(
        (item) => item.kind == LocalCapabilityKind.skill,
      );
      final favorited = history.toggleFavorite(skill);
      final restored = LocalActivityHistory.fromJson(
        jsonEncode(favorited.toJson()),
      );

      expect(restored.capabilities, hasLength(2));
      expect(restored.isFavorite(restored.capabilities.first), isTrue);
      expect(
        jsonEncode(restored.toJson()),
        isNot(contains('pacman -Syu transaction')),
      );
    },
  );

  test('ignores unknown capability ids from persisted activity data', () {
    final history = LocalActivityHistory.fromJson(
      jsonEncode(<String, Object?>{
        'capabilities': <Object?>[
          <String, String>{
            'kind': 'tool',
            'id': 'untrusted_tool',
            'discoveredAt': '2026-08-23T20:00:00Z',
            'lastUsedAt': '2026-08-23T20:00:00Z',
          },
        ],
      }),
    );

    expect(history.capabilities, isEmpty);
  });
}
