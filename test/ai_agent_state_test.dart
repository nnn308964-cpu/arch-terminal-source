import 'package:arch_terminal/terminal/ai_agent_state.dart';

import 'dart:convert';

import 'package:arch_terminal/terminal/ai_environment_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'agent task state preserves a bounded chat history and reconstructs it',
    () {
      var state = const AiAgentTaskState();
      for (var index = 0; index < 26; index++) {
        state = state.add(
          AiAgentMessage(
            role: AiAgentRole.user,
            content: 'task $index',
            createdAt: DateTime(2026, 8, 22, 10, index),
          ),
        );
      }

      expect(state.messages, hasLength(24));
      expect(state.messages.first.content, 'task 2');
      expect(
        AiAgentTaskState.fromJson(state.toJson().toString()).messages,
        isEmpty,
      );
      expect(
        AiAgentTaskState.fromJson(
          '{"taskSummary":"x","messages":[{"role":"user","content":"hello","createdAt":"2026-08-22T10:00:00Z"}]}',
        ).messages.single.content,
        'hello',
      );
    },
  );

  test('agent state enforces a visible eight-command task limit', () {
    var state = const AiAgentTaskState();
    for (var index = 0; index < 8; index++) {
      state = state.add(
        AiAgentMessage(
          role: AiAgentRole.system,
          content: 'Approved command sent to terminal: echo $index',
          createdAt: DateTime(2026, 8, 22),
        ),
      );
    }
    expect(state.approvedCommandCount, 8);
    expect(state.stepLimitReached, isTrue);
  });

  test(
    'work board persists every task, status, and a bounded provider summary',
    () {
      final first = AiAgentWorkItem(
        id: 'first',
        title: 'Refresh the Arch package databases safely',
        status: AiAgentWorkStatus.queued,
        createdAt: DateTime.utc(2026, 8, 22, 10),
        updatedAt: DateTime.utc(2026, 8, 22, 10),
      );
      final second = AiAgentWorkItem(
        id: 'second',
        title: 'Review the pacman mirror configuration',
        status: AiAgentWorkStatus.waitingForApproval,
        createdAt: DateTime.utc(2026, 8, 22, 11),
        updatedAt: DateTime.utc(2026, 8, 22, 11),
      );
      final state = const AiAgentTaskState()
          .addWorkItem(first)
          .addWorkItem(second)
          .updateWorkItem('first', AiAgentWorkStatus.completed);
      final restored = AiAgentTaskState.fromJson(jsonEncode(state.toJson()));

      expect(restored.workItems, hasLength(2));
      expect(restored.openWorkItemCount, 1);
      expect(restored.completedWorkItemCount, 1);
      expect(restored.workItems.first.status, AiAgentWorkStatus.completed);
      expect(
        restored.providerContext,
        contains('[completed] Refresh the Arch package databases safely'),
      );
      expect(
        restored.providerContext,
        contains('[waitingForApproval] Review the pacman mirror configuration'),
      );
      expect(restored.removeWorkItem('second').workItems, hasLength(1));
    },
  );

  test(
    'persists a local environment snapshot and includes it in provider context',
    () {
      final environment = AiEnvironmentSnapshot(
        scannedAt: DateTime.utc(2026, 8, 22, 10),
        user: 'root',
        uid: '0',
        architecture: 'aarch64',
        osName: 'Arch Linux ARM',
        pacmanAvailable: true,
        pacmanPackageCount: 123,
        workingDirectory: '/root',
        rootFreeKiB: 2048,
        storageBound: true,
        rootfsPath: '/data/user/0/example/files/arch',
        storagePath: '/storage/emulated/0',
        hostAbi: 'arm64-v8a',
        prootAvailable: true,
        pacmanSandboxDisabled: true,
        repositoryConfigured: true,
        repositoryMirror: 'http://mirror.archlinuxarm.org/\$arch/\$repo',
        repositoryNames: 'core,extra,alarm,aur',
        repositoryDatabaseCount: 4,
      );
      final state = const AiAgentTaskState().withEnvironment(environment);
      final restored = AiAgentTaskState.fromJson(jsonEncode(state.toJson()));

      expect(restored.environment?.user, 'root');
      expect(restored.environment?.isRoot, isTrue);
      expect(restored.providerContext, contains('uid: 0'));
      expect(restored.providerContext, contains('prefer direct commands'));
      expect(
        restored.providerContext,
        contains('/data/user/0/example/files/arch'),
      );
      expect(restored.providerContext, contains('core,extra,alarm,aur'));
      expect(restored.providerContext, contains('4 local databases'));
    },
  );

  test('workflow completes an observed step and starts the next one only explicitly', () {
    final timestamp = DateTime.utc(2026, 8, 22, 12);
    final state = const AiAgentTaskState().addWorkItems(<AiAgentWorkItem>[
      AiAgentWorkItem(
        id: 'flow-0',
        workflowId: 'flow',
        workflowGoal: 'Safely update the system',
        title: 'Review the proposed command',
        detail: 'Wait for explicit approval.',
        order: 0,
        status: AiAgentWorkStatus.waitingForApproval,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      AiAgentWorkItem(
        id: 'flow-1',
        workflowId: 'flow',
        workflowGoal: 'Safely update the system',
        title: 'Explain the terminal result',
        detail: 'Summarize the result locally.',
        order: 1,
        status: AiAgentWorkStatus.queued,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    ]);

    final running = state.beginWorkflowStep('flow');
    expect(
      running.itemsForWorkflow('flow').first.status,
      AiAgentWorkStatus.inProgress,
    );
    expect(
      running.itemsForWorkflow('flow').last.status,
      AiAgentWorkStatus.queued,
    );

    final advanced = running.completeWorkflowStep('flow');
    expect(
      advanced.itemsForWorkflow('flow').first.status,
      AiAgentWorkStatus.completed,
    );
    expect(
      advanced.itemsForWorkflow('flow').last.status,
      AiAgentWorkStatus.queued,
    );
    final resumed = advanced.beginNextQueuedWorkflowStep('flow');
    expect(
      resumed
          .flagWorkflowAttention('flow')
          .itemsForWorkflow('flow')
          .last
          .status,
      AiAgentWorkStatus.needsAttention,
    );
  });

  test('a failed workflow step can reopen for one replacement command', () {
    final timestamp = DateTime.utc(2026, 8, 23, 13);
    final state = const AiAgentTaskState().addWorkItem(
      AiAgentWorkItem(
        id: 'repair-0',
        workflowId: 'repair',
        workflowGoal: 'Install Python',
        title: 'Install the package',
        detail: 'Wait for a verified terminal outcome.',
        order: 0,
        status: AiAgentWorkStatus.needsAttention,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );

    final reopened = state.reopenWorkflowAttention('repair');
    expect(
      reopened.itemsForWorkflow('repair').single.status,
      AiAgentWorkStatus.inProgress,
    );
    final awaitingApproval = reopened.requestWorkflowApproval(
      'repair',
      'pacman -Syu python',
      'Approve the replacement command?',
    );
    final item = awaitingApproval.itemsForWorkflow('repair').single;
    expect(item.status, AiAgentWorkStatus.waitingForUserInput);
    expect(item.pendingCommand, 'pacman -Syu python');
  });

  test('workflow stores a user answer, resumes the pending step, and exposes it in context', () {
    final timestamp = DateTime.utc(2026, 8, 22, 13);
    final state = const AiAgentTaskState().addWorkItem(
      AiAgentWorkItem(
        id: 'input-0',
        workflowId: 'input-flow',
        workflowGoal: 'Inspect the requested package',
        title: 'Identify the package',
        detail: 'Ask the user for its name.',
        order: 0,
        status: AiAgentWorkStatus.inProgress,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );

    final waiting = state.requestWorkflowInput(
      'input-flow',
      'Which package should I inspect?',
    );
    expect(
      waiting.itemsForWorkflow('input-flow').single.status,
      AiAgentWorkStatus.waitingForUserInput,
    );
    expect(
      waiting.itemsForWorkflow('input-flow').single.inputRequest,
      contains('package'),
    );

    final resumed = waiting.submitWorkflowInput('input-flow', 'python');
    expect(
      resumed.itemsForWorkflow('input-flow').single.status,
      AiAgentWorkStatus.inProgress,
    );
    expect(
      resumed.itemsForWorkflow('input-flow').single.inputResponse,
      'python',
    );
    expect(resumed.providerContext, contains('user response: python'));
  });

  test('parses Arabic and English approval replies locally', () {
    expect(parseWorkflowApproval('نعم'), AiWorkflowApprovalDecision.approved);
    expect(parseWorkflowApproval('yes'), AiWorkflowApprovalDecision.approved);
    expect(parseWorkflowApproval('لا'), AiWorkflowApprovalDecision.declined);
    expect(parseWorkflowApproval('later'), AiWorkflowApprovalDecision.unknown);
  });

  test(
    'persists local result paths without placing them in provider context',
    () {
      final state = const AiAgentTaskState().add(
        AiAgentMessage(
          role: AiAgentRole.observation,
          content: 'A local directory listing completed.',
          createdAt: DateTime.utc(2026, 8, 23),
          localResultPaths: const <String>[
            '/sdcard/Download/notes.txt',
            '/sdcard/Download/photo.jpg',
          ],
        ),
      );
      final restored = AiAgentTaskState.fromJson(jsonEncode(state.toJson()));

      expect(restored.messages.single.localResultPaths, hasLength(2));
      expect(
        restored.providerContext,
        isNot(contains('/sdcard/Download/notes.txt')),
      );
    },
  );

  test('routes both a workflow question and command approval to the direct reply field', () {
    final timestamp = DateTime.utc(2026, 8, 22, 14);
    final question = AiAgentWorkItem(
      id: 'question',
      workflowId: 'flow-question',
      title: 'Ask for a package name',
      status: AiAgentWorkStatus.waitingForUserInput,
      inputRequest: 'Which package?',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final approval = AiAgentWorkItem(
      id: 'approval',
      workflowId: 'flow-approval',
      title: 'Approve a safe command',
      status: AiAgentWorkStatus.waitingForUserInput,
      pendingCommand: 'pacman -Ss python',
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    expect(pendingWorkflowReply(<AiAgentWorkItem>[question]), question);
    expect(pendingWorkflowReply(<AiAgentWorkItem>[approval]), approval);
    expect(
      pendingWorkflowReply(<AiAgentWorkItem>[
        question.withStatus(AiAgentWorkStatus.completed),
      ]),
      isNull,
    );
  });

  test('automatic workflow progress waits for a completed stage and never bypasses a barrier', () {
    final timestamp = DateTime.utc(2026, 8, 22, 14);
    final queued = AiAgentWorkItem(
      id: 'queued',
      workflowId: 'flow',
      title: 'Queued stage',
      status: AiAgentWorkStatus.queued,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final waitingForInput = AiAgentWorkItem(
      id: 'input',
      workflowId: 'flow',
      title: 'Needs user input',
      status: AiAgentWorkStatus.waitingForUserInput,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    expect(
      shouldAutomaticallyAdvanceWorkflow(
        automaticMode: false,
        agentBusy: false,
        workItems: <AiAgentWorkItem>[queued],
      ),
      isFalse,
    );
    expect(
      shouldAutomaticallyAdvanceWorkflow(
        automaticMode: true,
        agentBusy: false,
        workItems: <AiAgentWorkItem>[queued],
      ),
      isTrue,
    );
    expect(
      shouldAutomaticallyAdvanceWorkflow(
        automaticMode: true,
        agentBusy: false,
        workItems: <AiAgentWorkItem>[waitingForInput, queued],
      ),
      isFalse,
    );
    expect(
      shouldAutomaticallyAdvanceWorkflow(
        automaticMode: true,
        agentBusy: true,
        workItems: <AiAgentWorkItem>[queued],
      ),
      isFalse,
    );
  });

  test(
    'workflow retains a pending command until the user approves or declines it',
    () {
      final timestamp = DateTime.utc(2026, 8, 22, 14);
      final state = const AiAgentTaskState().addWorkItem(
        AiAgentWorkItem(
          id: 'approval-0',
          workflowId: 'approval-flow',
          workflowGoal: 'Check package databases',
          title: 'Run the query',
          detail: 'Use pacman.',
          status: AiAgentWorkStatus.inProgress,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );

      final waiting = state.requestWorkflowApproval(
        'approval-flow',
        'pacman -Ss python',
        'Approve?',
      );
      expect(
        waiting.pendingWorkflowApproval('approval-flow')?.pendingCommand,
        'pacman -Ss python',
      );
      final approved = waiting.approveWorkflowPendingCommand('approval-flow');
      expect(
        approved.itemsForWorkflow('approval-flow').single.status,
        AiAgentWorkStatus.inProgress,
      );
      final declined = waiting.declineWorkflowPendingCommand('approval-flow');
      expect(
        declined.itemsForWorkflow('approval-flow').single.status,
        AiAgentWorkStatus.needsAttention,
      );
    },
  );

  test('conversation codec keeps valid conversations ordered and independently updatable', () {
    final older = AiAgentConversation(
      id: 'older',
      title: 'Older task',
      createdAt: DateTime.utc(2026, 8, 22, 10),
      updatedAt: DateTime.utc(2026, 8, 22, 10),
      state: const AiAgentTaskState(),
    );
    final newer = AiAgentConversation(
      id: 'newer',
      title: 'Newer task',
      createdAt: DateTime.utc(2026, 8, 22, 11),
      updatedAt: DateTime.utc(2026, 8, 22, 11),
      state: const AiAgentTaskState(),
    );

    final encoded = AiAgentConversationStore.encode(<AiAgentConversation>[
      older,
      newer,
    ]);
    final decoded = AiAgentConversationStore.decode(encoded);
    expect(decoded.map((item) => item.id), <String>['newer', 'older']);

    final updatedOlder = older.copyWith(
      state: older.state.add(
        AiAgentMessage(
          role: AiAgentRole.user,
          content: 'Keep this task separate',
          createdAt: DateTime.utc(2026, 8, 22, 12),
        ),
      ),
    );
    final upserted = AiAgentConversationStore.upsert(decoded, updatedOlder);
    expect(upserted, hasLength(2));
    expect(upserted.first.id, 'older');
    expect(
      upserted.first.state.messages.single.content,
      'Keep this task separate',
    );
    expect(upserted.last.state.messages, isEmpty);

    final remaining = AiAgentConversationStore.removeById(upserted, 'older');
    expect(remaining.map((item) => item.id), <String>['newer']);
  });

  test('conversation codec ignores malformed records and caps history deterministically', () {
    final records = <Map<String, Object?>>[
      <String, Object?>{'id': '', 'title': 'invalid'},
      for (var index = 0; index < 22; index++)
        AiAgentConversation(
          id: 'task-$index',
          title: 'Task $index',
          createdAt: DateTime.utc(2026, 8, 22, 10, index),
          updatedAt: DateTime.utc(2026, 8, 22, 10, index),
          state: const AiAgentTaskState(),
        ).toJson(),
    ];

    final decoded = AiAgentConversationStore.decode(jsonEncode(records));
    expect(decoded, hasLength(20));
    expect(decoded.first.id, 'task-21');
    expect(decoded.last.id, 'task-2');
  });
}
