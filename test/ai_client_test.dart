import 'package:arch_terminal/terminal/ai_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'chooses Arabic replies for Arabic user input and English otherwise',
    () {
      expect(preferredAiReplyLanguage('اتكلم عربي'), 'Arabic');
      expect(preferredAiReplyLanguage('inspect pacman'), 'English');
    },
  );

  test('parses one optional command from the strict JSON model contract', () {
    final proposal = parseAiProposal(
      '{"reply":"Install Python first.","command":"pacman -S python"}',
    );
    expect(proposal.reply, startsWith('Install Python first.'));
    expect(proposal.reply, contains('has not been verified locally yet'));
    expect(proposal.command, 'pacman -S python');
  });

  test('parses a separately proposed one-line terminal reply', () {
    final proposal = parseAiProposal(
      '{"reply":"Confirm the package transaction.","terminalReply":"Y","command":null}',
    );

    expect(proposal.command, isNull);
    expect(proposal.terminalReply, 'Y');
  });

  test(
    'renders observed evidence separately from assessment and uncertainty',
    () {
      final proposal = parseAiProposal('''
      {"reply":"The package database may be old.","command":null,"evidence":["A local download returned HTTP 404"],"assessment":"The requested package name may be stale.","uncertainty":"The current repository record was not checked.","nextVerification":"Refresh with a full upgrade and inspect the result."}
    ''');

      expect(proposal.reply, contains('Observed evidence'));
      expect(proposal.reply, contains('Assessment'));
      expect(proposal.reply, contains('Not verified yet'));
      expect(proposal.reply, contains('Next verification'));
    },
  );

  test('renders known facts, causality, relationships, and knowledge gaps', () {
    final proposal = parseAiProposal('''
      {"reply":"The session may need a restart.","command":null,"known":["The current session started before permission changed"],"causalLink":"PRoot bind arguments are fixed when a session starts, so a later permission grant does not alter that session.","relationship":"The Android storage grant controls whether the PRoot /sdcard bind is available.","knowledgeGap":"No local observation confirms that the next session sees the requested file.","nextVerification":"Start a new session and list /sdcard."}
    ''');

    expect(proposal.reply, contains('Known locally'));
    expect(proposal.reply, contains('Cause and effect'));
    expect(proposal.reply, contains('Relevant relationship'));
    expect(proposal.reply, contains('Knowledge gap'));
    expect(proposal.reply, contains('Start a new session'));
  });

  test('adds an explicit local-verification disclosure when a provider omits evidence', () {
    final proposal = parseAiProposal(
      '{"reply":"This should fix the issue.","command":null}',
    );

    expect(proposal.reply, contains('has not been verified locally yet'));
  });

  test(
    'parses a bounded structured workflow alongside the optional command',
    () {
      final proposal = parseAiProposal('''
      {"reply":"I will inspect the setup first.","workflow":[
        {"title":"Inspect pacman","detail":"Read local repository configuration."},
        {"title":"Review the update","detail":"Wait for approval before the command."}
      ],"command":"pacman -Syu"}
    ''');
      expect(proposal.workflow, hasLength(2));
      expect(proposal.workflow.first.title, 'Inspect pacman');
      expect(proposal.workflow.last.detail, contains('approval'));
    },
  );

  test('parses a focused input request without allowing a command', () {
    final proposal = parseAiProposal('''
      {"reply":"I need the target package name first.","workflow":[{"title":"Choose package","detail":"Wait for the user name."}],"inputRequest":"Which package should I inspect?","command":null}
    ''');
    expect(proposal.inputRequest, 'Which package should I inspect?');
    expect(proposal.command, isNull);
  });

  test('drops command execution when a provider returns plain text', () {
    final proposal = parseAiProposal(
      'I recommend checking the package cache first.',
    );
    expect(proposal.command, isNull);
    expect(proposal.reply, contains('package cache'));
  });

  test(
    'requires the same approval and result workflow for every terminal command',
    () {
      final instruction = AiClient.systemInstructionForTesting;

      expect(
        instruction,
        contains('same operational workflow to every terminal command'),
      );
      expect(instruction, contains('Run only one approved command at a time'));
      expect(instruction, contains('without copying raw terminal output'));
      expect(instruction, contains('terminalReply'));
      expect(instruction, contains('honest, concise reasoning audit'));
      expect(instruction, contains('Never say solved'));
      expect(instruction, contains('without naming its path'));
      expect(instruction, contains('bounded discovery command under /sdcard'));
      expect(instruction, contains('when only a device-file path is missing'));
      expect(instruction, contains('small result limit'));
      expect(instruction, contains('Use a `find /sdcard` command'));
      expect(instruction, contains('externally reviewable reasoning audit'));
      expect(
        instruction,
        contains('Never send a discovered file list, path, metadata'),
      );
    },
  );
}
