import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ai_environment_snapshot.dart';
import 'ai_skill_discovery.dart';

enum AiAgentRole { user, agent, observation, system }

enum AiAgentWorkStatus {
  queued,
  inProgress,
  waitingForApproval,
  waitingForUserInput,
  completed,
  needsAttention,
}

enum AiWorkflowApprovalDecision { approved, declined, unknown }

bool shouldAutomaticallyAdvanceWorkflow({
  required bool automaticMode,
  required bool agentBusy,
  required Iterable<AiAgentWorkItem> workItems,
}) {
  if (!automaticMode || agentBusy) return false;
  final items = workItems.toList();
  final hasQueuedStep = items.any(
    (item) => item.status == AiAgentWorkStatus.queued,
  );
  final hasBlockingStep = items.any(
    (item) =>
        item.status == AiAgentWorkStatus.inProgress ||
        item.status == AiAgentWorkStatus.waitingForApproval ||
        item.status == AiAgentWorkStatus.waitingForUserInput ||
        item.status == AiAgentWorkStatus.needsAttention,
  );
  return hasQueuedStep && !hasBlockingStep;
}

AiAgentWorkItem? pendingWorkflowReply(Iterable<AiAgentWorkItem> workItems) {
  for (final item in workItems) {
    if (item.status == AiAgentWorkStatus.waitingForUserInput &&
        item.workflowId != null) {
      return item;
    }
  }
  return null;
}

AiWorkflowApprovalDecision parseWorkflowApproval(String raw) {
  final value = raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[ًٌٍَُِّْـ]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
  if (const <String>{
    'نعم',
    'موافق',
    'ايوه',
    'أيوه',
    'yes',
    'y',
    'ok',
    'okay',
    'approve',
  }.contains(value)) {
    return AiWorkflowApprovalDecision.approved;
  }
  if (const <String>{
    'لا',
    'لأ',
    'لا اوافق',
    'no',
    'n',
    'رفض',
    'cancel',
    'reject',
  }.contains(value)) {
    return AiWorkflowApprovalDecision.declined;
  }
  return AiWorkflowApprovalDecision.unknown;
}

class AiAgentWorkItem {
  const AiAgentWorkItem({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.workflowId,
    this.workflowGoal,
    this.detail = '',
    this.inputRequest,
    this.inputResponse,
    this.pendingCommand,
    this.order = 0,
  });

  final String id;
  final String title;
  final AiAgentWorkStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? workflowId;
  final String? workflowGoal;
  final String detail;
  final String? inputRequest;
  final String? inputResponse;
  final String? pendingCommand;
  final int order;

  AiAgentWorkItem withStatus(AiAgentWorkStatus value) => AiAgentWorkItem(
    id: id,
    title: title,
    status: value,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    workflowId: workflowId,
    workflowGoal: workflowGoal,
    detail: detail,
    inputRequest: inputRequest,
    inputResponse: inputResponse,
    pendingCommand: pendingCommand,
    order: order,
  );

  AiAgentWorkItem withInputRequest(String value) => AiAgentWorkItem(
    id: id,
    title: title,
    status: AiAgentWorkStatus.waitingForUserInput,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    workflowId: workflowId,
    workflowGoal: workflowGoal,
    detail: detail,
    inputRequest: value,
    inputResponse: null,
    pendingCommand: pendingCommand,
    order: order,
  );

  AiAgentWorkItem withUserInput(String value) => AiAgentWorkItem(
    id: id,
    title: title,
    status: AiAgentWorkStatus.inProgress,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    workflowId: workflowId,
    workflowGoal: workflowGoal,
    detail: detail,
    inputRequest: inputRequest,
    inputResponse: value,
    pendingCommand: pendingCommand,
    order: order,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'status': status.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'workflowId': workflowId,
    'workflowGoal': workflowGoal,
    'detail': detail,
    'inputRequest': inputRequest,
    'inputResponse': inputResponse,
    'pendingCommand': pendingCommand,
    'order': order,
  };

  static AiAgentWorkItem? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id']?.toString().trim();
    final title = value['title']?.toString().trim();
    final status = AiAgentWorkStatus.values
        .where((item) => item.name == value['status'])
        .cast<AiAgentWorkStatus?>()
        .firstOrNull;
    final createdAt = DateTime.tryParse(value['createdAt']?.toString() ?? '')
        ?.toLocal();
    final updatedAt = DateTime.tryParse(value['updatedAt']?.toString() ?? '')
        ?.toLocal();
    if (id == null ||
        id.isEmpty ||
        title == null ||
        title.isEmpty ||
        status == null ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }
    return AiAgentWorkItem(
      id: id,
      title: title,
      status: status,
      createdAt: createdAt,
      updatedAt: updatedAt,
      workflowId: value['workflowId']?.toString(),
      workflowGoal: value['workflowGoal']?.toString(),
      detail: value['detail']?.toString() ?? '',
      inputRequest: value['inputRequest']?.toString(),
      inputResponse: value['inputResponse']?.toString(),
      pendingCommand: value['pendingCommand']?.toString(),
      order: (value['order'] as num?)?.toInt() ?? 0,
    );
  }
}

class AiAgentMessage {
  const AiAgentMessage({
    required this.role,
    required this.content,
    required this.createdAt,
    this.proposedCommand,
    this.workflowId,
    this.localResultPaths = const <String>[],
  });
  final AiAgentRole role;
  final String content;
  final DateTime createdAt;
  final String? proposedCommand;
  final String? workflowId;
  final List<String> localResultPaths;

  Map<String, Object?> toJson() => <String, Object?>{
    'role': role.name,
    'content': content,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'proposedCommand': proposedCommand,
    'workflowId': workflowId,
    'localResultPaths': localResultPaths,
  };

  static AiAgentMessage? fromJson(Object? value) {
    if (value is! Map) return null;
    final role = AiAgentRole.values
        .where((item) => item.name == value['role'])
        .cast<AiAgentRole?>()
        .firstOrNull;
    final content = value['content']?.toString().trim();
    final createdAt = DateTime.tryParse(value['createdAt']?.toString() ?? '')
        ?.toLocal();
    return role == null ||
            content == null ||
            content.isEmpty ||
            createdAt == null
        ? null
        : AiAgentMessage(
            role: role,
            content: content,
            createdAt: createdAt,
            proposedCommand: value['proposedCommand']?.toString(),
            workflowId: value['workflowId']?.toString(),
            localResultPaths:
                (value['localResultPaths'] as List?)
                    ?.map((item) => item.toString().trim())
                    .where(
                      (path) =>
                          RegExp(r'^/sdcard(?:/[^\n\r]*)?$').hasMatch(path),
                    )
                    .take(24)
                    .toList() ??
                const <String>[],
          );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class AiAgentTaskState {
  const AiAgentTaskState({
    this.messages = const <AiAgentMessage>[],
    this.taskSummary = '',
    this.environment,
    this.workItems = const <AiAgentWorkItem>[],
    this.skillDiscovery,
  });
  final List<AiAgentMessage> messages;
  final String taskSummary;
  final AiEnvironmentSnapshot? environment;
  final List<AiAgentWorkItem> workItems;
  final AiSkillDiscovery? skillDiscovery;

  int get approvedCommandCount => messages
      .where(
        (message) =>
            message.role == AiAgentRole.system &&
            message.content.startsWith('Approved command sent to terminal:'),
      )
      .length;
  bool get stepLimitReached => approvedCommandCount >= 8;

  AiAgentTaskState add(AiAgentMessage message) {
    final next = <AiAgentMessage>[...messages, message];
    final capped = next.length <= 24 ? next : next.sublist(next.length - 24);
    return AiAgentTaskState(
      messages: capped,
      taskSummary: _summarize(capped),
      environment: environment,
      workItems: workItems,
      skillDiscovery: skillDiscovery,
    );
  }

  AiAgentTaskState withEnvironment(AiEnvironmentSnapshot? value) =>
      AiAgentTaskState(
        messages: messages,
        taskSummary: taskSummary,
        environment: value,
        workItems: workItems,
        skillDiscovery: skillDiscovery,
      );

  AiAgentTaskState withSkillDiscovery(AiSkillDiscovery? value) =>
      AiAgentTaskState(
        messages: messages,
        taskSummary: taskSummary,
        environment: environment,
        workItems: workItems,
        skillDiscovery: value,
      );

  int get openWorkItemCount => workItems
      .where((item) => item.status != AiAgentWorkStatus.completed)
      .length;
  int get completedWorkItemCount => workItems
      .where((item) => item.status == AiAgentWorkStatus.completed)
      .length;

  List<AiAgentWorkItem> itemsForWorkflow(String id) =>
      workItems.where((item) => item.workflowId == id).toList()
        ..sort((left, right) => left.order.compareTo(right.order));

  AiAgentTaskState addWorkItem(AiAgentWorkItem item) {
    final next = <AiAgentWorkItem>[...workItems, item];
    final capped = next.length <= 120 ? next : next.sublist(next.length - 120);
    return AiAgentTaskState(
      messages: messages,
      taskSummary: taskSummary,
      environment: environment,
      workItems: capped,
      skillDiscovery: skillDiscovery,
    );
  }

  AiAgentTaskState addWorkItems(Iterable<AiAgentWorkItem> items) {
    final next = <AiAgentWorkItem>[...workItems, ...items];
    final capped = next.length <= 120 ? next : next.sublist(next.length - 120);
    return AiAgentTaskState(
      messages: messages,
      taskSummary: taskSummary,
      environment: environment,
      workItems: capped,
      skillDiscovery: skillDiscovery,
    );
  }

  AiAgentTaskState updateWorkItem(String id, AiAgentWorkStatus status) =>
      AiAgentTaskState(
        messages: messages,
        taskSummary: taskSummary,
        environment: environment,
        workItems: workItems
            .map((item) => item.id == id ? item.withStatus(status) : item)
            .toList(),
        skillDiscovery: skillDiscovery,
      );

  AiAgentTaskState requestWorkflowInput(String workflowId, String request) {
    final active = itemsForWorkflow(workflowId)
        .where((item) => item.status == AiAgentWorkStatus.inProgress)
        .toList();
    return active.isEmpty
        ? this
        : _replaceWorkItem(
            active.first.id,
            active.first.withInputRequest(request),
          );
  }

  AiAgentTaskState requestWorkflowApproval(
    String workflowId,
    String command,
    String question,
  ) {
    final active = itemsForWorkflow(workflowId)
        .where(
          (item) =>
              item.status == AiAgentWorkStatus.inProgress ||
              item.status == AiAgentWorkStatus.waitingForApproval ||
              item.status == AiAgentWorkStatus.needsAttention,
        )
        .toList();
    if (active.isEmpty) return this;
    final item = active.first;
    return _replaceWorkItem(
      item.id,
      AiAgentWorkItem(
        id: item.id,
        title: item.title,
        status: AiAgentWorkStatus.waitingForUserInput,
        createdAt: item.createdAt,
        updatedAt: DateTime.now(),
        workflowId: item.workflowId,
        workflowGoal: item.workflowGoal,
        detail: item.detail,
        inputRequest: question,
        inputResponse: null,
        pendingCommand: command,
        order: item.order,
      ),
    );
  }

  AiAgentWorkItem? pendingWorkflowApproval(String workflowId) =>
      itemsForWorkflow(workflowId)
          .where(
            (item) =>
                item.status == AiAgentWorkStatus.waitingForUserInput &&
                item.pendingCommand != null,
          )
          .cast<AiAgentWorkItem?>()
          .firstOrNull;

  AiAgentTaskState approveWorkflowPendingCommand(String workflowId) {
    final pending = pendingWorkflowApproval(workflowId);
    return pending == null
        ? this
        : updateWorkItem(pending.id, AiAgentWorkStatus.inProgress);
  }

  AiAgentTaskState declineWorkflowPendingCommand(String workflowId) {
    final pending = pendingWorkflowApproval(workflowId);
    return pending == null
        ? this
        : updateWorkItem(pending.id, AiAgentWorkStatus.needsAttention);
  }

  AiAgentTaskState submitWorkflowInput(String workflowId, String response) {
    final waiting = itemsForWorkflow(workflowId)
        .where((item) => item.status == AiAgentWorkStatus.waitingForUserInput)
        .toList();
    return waiting.isEmpty
        ? this
        : _replaceWorkItem(
            waiting.first.id,
            waiting.first.withUserInput(response),
          );
  }

  AiAgentTaskState setCurrentWorkflowStatus(
    String workflowId,
    AiAgentWorkStatus status,
  ) {
    final current = itemsForWorkflow(workflowId)
        .where((item) => item.status == AiAgentWorkStatus.inProgress)
        .toList();
    return current.isEmpty ? this : updateWorkItem(current.first.id, status);
  }

  AiAgentTaskState _replaceWorkItem(String id, AiAgentWorkItem replacement) =>
      AiAgentTaskState(
        messages: messages,
        taskSummary: taskSummary,
        environment: environment,
        workItems: workItems
            .map((item) => item.id == id ? replacement : item)
            .toList(),
        skillDiscovery: skillDiscovery,
      );

  AiAgentTaskState beginWorkflowStep(String workflowId) {
    final waiting = itemsForWorkflow(workflowId)
        .where(
          (item) =>
              item.status == AiAgentWorkStatus.waitingForApproval ||
              (item.status == AiAgentWorkStatus.waitingForUserInput &&
                  item.pendingCommand != null),
        )
        .toList();
    final queued = itemsForWorkflow(workflowId)
        .where((item) => item.status == AiAgentWorkStatus.queued)
        .toList();
    final target = waiting.isNotEmpty
        ? waiting.first
        : (queued.isEmpty ? null : queued.first);
    return target == null
        ? this
        : updateWorkItem(target.id, AiAgentWorkStatus.inProgress);
  }

  AiAgentTaskState beginNextQueuedWorkflowStep(String workflowId) {
    final active = itemsForWorkflow(workflowId)
        .where(
          (item) =>
              item.status == AiAgentWorkStatus.inProgress ||
              item.status == AiAgentWorkStatus.waitingForApproval ||
              item.status == AiAgentWorkStatus.waitingForUserInput,
        )
        .toList();
    if (active.isNotEmpty) return this;
    final queued = itemsForWorkflow(workflowId)
        .where((item) => item.status == AiAgentWorkStatus.queued)
        .toList();
    return queued.isEmpty
        ? this
        : updateWorkItem(queued.first.id, AiAgentWorkStatus.inProgress);
  }

  AiAgentTaskState completeWorkflowStep(String workflowId) {
    final active = itemsForWorkflow(workflowId)
        .where((item) => item.status == AiAgentWorkStatus.inProgress)
        .toList();
    if (active.isEmpty) return this;
    return updateWorkItem(active.first.id, AiAgentWorkStatus.completed);
  }

  AiAgentTaskState flagWorkflowAttention(String workflowId) {
    final current = itemsForWorkflow(workflowId)
        .where(
          (item) =>
              item.status == AiAgentWorkStatus.inProgress ||
              item.status == AiAgentWorkStatus.waitingForApproval,
        )
        .toList();
    return current.isEmpty
        ? this
        : updateWorkItem(current.first.id, AiAgentWorkStatus.needsAttention);
  }

  AiAgentTaskState reopenWorkflowAttention(String workflowId) {
    final target = itemsForWorkflow(workflowId)
        .where(
          (item) =>
              item.status == AiAgentWorkStatus.needsAttention ||
              item.status == AiAgentWorkStatus.inProgress,
        )
        .toList();
    return target.isEmpty
        ? this
        : updateWorkItem(target.first.id, AiAgentWorkStatus.inProgress);
  }

  AiAgentTaskState removeWorkItem(String id) => AiAgentTaskState(
    messages: messages,
    taskSummary: taskSummary,
    environment: environment,
    workItems: workItems.where((item) => item.id != id).toList(),
    skillDiscovery: skillDiscovery,
  );

  List<AiAgentMessage> messagesForWorkflow(String workflowId) =>
      messages.where((message) => message.workflowId == workflowId).toList();

  String get providerContext {
    final history = messages
        .map(
          (message) =>
              '${message.role.name.toUpperCase()}: ${_providerSafeContent(message)}',
        )
        .join('\n');
    final environmentContext = environment == null
        ? 'Local Arch environment: not scanned for this session yet.'
        : environment!.providerContext;
    return '$environmentContext\n\nSaved local task board (sent only with this message):\n$_workItemsContext\n\nTask summary: $taskSummary\nRecent task messages:\n$history';
  }

  String get _workItemsContext {
    if (workItems.isEmpty) return 'No saved tasks.';
    return workItems
        .map(
          (item) =>
              '- [${item.status.name}] ${item.title}${item.inputRequest == null ? '' : ' | user question: ${item.inputRequest}'}${item.inputResponse == null ? '' : ' | user response: ${item.inputResponse}'}',
        )
        .join('\n');
  }

  static String _providerSafeContent(AiAgentMessage message) {
    if (message.role != AiAgentRole.observation) return message.content;
    final boundary = message.content.indexOf(
      '\n\nLocal terminal excerpt (not sent automatically):',
    );
    return boundary < 0
        ? message.content
        : message.content.substring(0, boundary);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'taskSummary': taskSummary,
    'messages': messages.map((message) => message.toJson()).toList(),
    'environment': environment?.toJson(),
    'workItems': workItems.map((item) => item.toJson()).toList(),
    'skillDiscovery': skillDiscovery?.toJson(),
  };

  static AiAgentTaskState fromJson(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is! Map) return const AiAgentTaskState();
      final values = value['messages'];
      final messages = values is List
          ? values
                .map(AiAgentMessage.fromJson)
                .whereType<AiAgentMessage>()
                .toList()
          : <AiAgentMessage>[];
      final workValues = value['workItems'];
      final workItems = workValues is List
          ? workValues
                .map(AiAgentWorkItem.fromJson)
                .whereType<AiAgentWorkItem>()
                .toList()
          : <AiAgentWorkItem>[];
      final summary = value['taskSummary']?.toString() ?? '';
      return AiAgentTaskState(
        messages: messages.length <= 24
            ? messages
            : messages.sublist(messages.length - 24),
        taskSummary: summary,
        environment: AiEnvironmentSnapshot.fromJson(value['environment']),
        workItems: workItems.length <= 120
            ? workItems
            : workItems.sublist(workItems.length - 120),
        skillDiscovery: AiSkillDiscovery.fromJson(value['skillDiscovery']),
      );
    } catch (_) {
      return const AiAgentTaskState();
    }
  }

  static String _summarize(List<AiAgentMessage> messages) {
    final essential = messages
        .where((message) => message.role != AiAgentRole.system)
        .map((message) => '${message.role.name}: ${message.content}')
        .join(' | ');
    return essential.length <= 1800
        ? essential
        : essential.substring(essential.length - 1800);
  }
}

class AiAgentTaskStateStore {
  AiAgentTaskStateStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          FlutterSecureStorage(
            aOptions: AndroidOptions(migrateWithBackup: true),
          );

  static const _stateKey = 'arch_terminal.ai.task_state.v1';
  final FlutterSecureStorage _storage;

  Future<AiAgentTaskState> load() async =>
      AiAgentTaskState.fromJson(await _storage.read(key: _stateKey) ?? '');

  Future<void> save(AiAgentTaskState state) =>
      _storage.write(key: _stateKey, value: jsonEncode(state.toJson()));

  Future<void> clear() => _storage.delete(key: _stateKey);
}

class AiAgentConversation {
  const AiAgentConversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.state,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final AiAgentTaskState state;

  AiAgentConversation copyWith({String? title, AiAgentTaskState? state}) =>
      AiAgentConversation(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        state: state ?? this.state,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'state': state.toJson(),
  };

  static AiAgentConversation? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id']?.toString().trim();
    final title = value['title']?.toString().trim();
    final createdAt = DateTime.tryParse(value['createdAt']?.toString() ?? '')
        ?.toLocal();
    final updatedAt = DateTime.tryParse(value['updatedAt']?.toString() ?? '')
        ?.toLocal();
    if (id == null ||
        id.isEmpty ||
        title == null ||
        title.isEmpty ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }
    return AiAgentConversation(
      id: id,
      title: title,
      createdAt: createdAt,
      updatedAt: updatedAt,
      state: AiAgentTaskState.fromJson(
        jsonEncode(value['state'] ?? const <String, Object?>{}),
      ),
    );
  }
}

class AiAgentConversationStore {
  AiAgentConversationStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          FlutterSecureStorage(
            aOptions: AndroidOptions(migrateWithBackup: true),
          );

  static const _conversationsKey = 'arch_terminal.ai.conversations.v1';
  final FlutterSecureStorage _storage;

  Future<List<AiAgentConversation>> load() async {
    try {
      return decode(await _storage.read(key: _conversationsKey) ?? '[]');
    } catch (_) {
      return const <AiAgentConversation>[];
    }
  }

  Future<void> save(List<AiAgentConversation> conversations) async {
    await _storage.write(key: _conversationsKey, value: encode(conversations));
  }

  static List<AiAgentConversation> decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <AiAgentConversation>[];
      return normalize(decoded.map(AiAgentConversation.fromJson));
    } catch (_) {
      return const <AiAgentConversation>[];
    }
  }

  static String encode(Iterable<AiAgentConversation> conversations) =>
      jsonEncode(
        normalize(conversations).map((item) => item.toJson()).toList(),
      );

  static List<AiAgentConversation> normalize(
    Iterable<AiAgentConversation?> conversations,
  ) {
    final ordered = conversations.whereType<AiAgentConversation>().toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return ordered.take(20).toList();
  }

  static List<AiAgentConversation> upsert(
    Iterable<AiAgentConversation> conversations,
    AiAgentConversation updated,
  ) => normalize(<AiAgentConversation>[
    updated,
    ...conversations.where((item) => item.id != updated.id),
  ]);

  static List<AiAgentConversation> removeById(
    Iterable<AiAgentConversation> conversations,
    String id,
  ) => normalize(conversations.where((item) => item.id != id));
}
