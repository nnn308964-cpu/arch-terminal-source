import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import 'rootfs_storage_sheet.dart';
import 'terminal/app_sound_feedback.dart';
import 'terminal/automatic_start_queue.dart';
import 'terminal/arch_runtime.dart';
import 'terminal/arch_setup_gate.dart';
import 'terminal/ai_client.dart';
import 'terminal/ai_agent_state.dart';
import 'terminal/ai_model_catalog.dart';
import 'terminal/ai_settings.dart';
import 'terminal/ai_skill_discovery.dart';
import 'terminal/ai_command_guard.dart';
import 'terminal/ai_environment_snapshot.dart';
import 'terminal/deep_transcript_buffer.dart';
import 'terminal/device_file_content_preview.dart';
import 'terminal/device_file_search_preview.dart';
import 'terminal/environment_detector.dart';
import 'terminal/inline_terminal_image.dart';
import 'terminal/inline_image_queue.dart';
import 'terminal/local_activity_history.dart';
import 'terminal/pacman_network_diagnostic.dart';
import 'terminal/setup_failure_guidance.dart';
import 'terminal/terminal_copy_text.dart';
import 'terminal/terminal_control_filter.dart';
import 'terminal/terminal_interactive_prompt.dart';
import 'terminal/terminal_command_outcome.dart';
import 'terminal/terminal_preferences.dart';
import 'terminal/terminal_session.dart';
import 'terminal/triple_tap_gate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ArchTerminalApp());
}

class ArchTerminalApp extends StatelessWidget {
  const ArchTerminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Arch Terminal',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF070A0E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF62D5FF),
          secondary: Color(0xFF7EE787),
          surface: Color(0xFF10151C),
        ),
        fontFamily: 'sans-serif',
      ),
      home: const TerminalPage(),
    );
  }
}

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage>
    with WidgetsBindingObserver {
  final terminal = Terminal(maxLines: 10000);
  final terminalFocusNode = FocusNode();
  final terminalController = TerminalController();
  final terminalViewKey = GlobalKey<TerminalViewState>();
  final _keyboardTapGate = TripleTapGate();
  final _inlineImageDecoder = InlineTerminalImageDecoder();
  late final TerminalSession session;
  TerminalPreferences? _preferences;
  final _aiSettingsStore = AiSettingsStore();
  final _aiAgentStateStore = AiAgentTaskStateStore();
  final _aiConversationStore = AiAgentConversationStore();
  final _aiModelCatalogStore = AiModelCatalogStore();
  final _activityHistoryStore = LocalActivityHistoryStore();
  AiSettings? _aiSettings;
  AiAgentTaskState _aiAgentState = const AiAgentTaskState();
  List<AiAgentConversation> _aiConversations = <AiAgentConversation>[];
  String? _activeAiConversationId;
  final ValueNotifier<AiAgentTaskState> _aiAgentStateNotifier =
      ValueNotifier<AiAgentTaskState>(const AiAgentTaskState());
  final ValueNotifier<AiEnvironmentSnapshot?> _aiEnvironmentNotifier =
      ValueNotifier<AiEnvironmentSnapshot?>(null);
  final ValueNotifier<LocalActivityHistory> _activityHistoryNotifier =
      ValueNotifier<LocalActivityHistory>(const LocalActivityHistory());
  List<AiModelInfo> _aiModels = <AiModelInfo>[];
  String? _selectedAiModelId;
  final Set<AiModelPriceTier> _aiModelFilters = AiModelPriceTier.values.toSet();
  bool _aiModelsRefreshing = false;
  bool _aiModelTesting = false;
  bool _aiBusy = false;
  AiPolicyChange? _pendingAiPolicyChange;
  Timer? _statusTimer;
  Timer? _transcriptFlushTimer;
  Timer? _agentObservationTimer;
  Timer? _environmentProbeTimer;
  StreamSubscription<Map<String, Object?>>? _progressSubscription;

  Map<String, Object?> runtimeStatus = const <String, Object?>{};
  String statusText = 'محلي بالكامل — اكتب أمراً أو افتح لوحة التحكم';
  bool busy = false;
  bool commandsOpen = false;
  bool hasSelection = false;
  bool _archPermissionGateActive = false;
  bool _permissionRequestInFlight = false;
  final _automaticStartQueue = AutomaticStartQueue();
  double terminalFontSize = TerminalPreferences.defaultFontSize;
  bool soundEnabled = true;
  double soundVolume = TerminalPreferences.defaultSoundVolume;
  InterfaceLanguage interfaceLanguage = InterfaceLanguage.arabic;
  String sessionName = 'Arch';
  bool _endingFromNotification = false;
  bool _manualSessionEndRequested = false;
  final _deepTranscriptBuffer = DeepTranscriptBuffer(maxChars: 96 * 1024);
  final _terminalControlFilter = TerminalControlFilter();
  final _terminalInteractivePromptDetector =
      TerminalInteractivePromptDetector();
  final ValueNotifier<TerminalInteractivePrompt?>
  _terminalInteractivePromptNotifier =
      ValueNotifier<TerminalInteractivePrompt?>(null);
  final _environmentDetector = EnvironmentDetector();
  String _networkOutputTail = '';
  String? _lastPacmanNetworkDiagnostic;
  final _inlineImages = InlineImageQueue(maxImages: 2);
  String? _observedAgentCommand;
  String? _observedAgentWorkflowId;
  StringBuffer? _agentObservationBuffer;
  DeviceFileSearchPreview? _deviceFileSearchPreview;
  DeviceFileContentPreview? _deviceFileContentPreview;
  bool _deviceFilePreviewLoading = false;
  String? _activeRecordedTerminalSessionId;

  bool get isMobile => Platform.isAndroid || Platform.isIOS;
  bool get _setupRunning => runtimeStatus['setupRunning'] == true;
  bool get _canCancelArchDownload =>
      _setupRunning &&
      const <String>{
        'connecting',
        'downloading',
        'verifying',
        'cancelling',
      }.contains(runtimeStatus['setupPhase']?.toString());
  bool get _archInstalled => runtimeStatus['installed'] == true;
  bool get _prootAvailable => runtimeStatus['prootAvailable'] == true;
  bool get _pacmanSandboxDisabled =>
      runtimeStatus['pacmanSandboxDisabled'] == true;
  bool get _isArabicUi => interfaceLanguage == InterfaceLanguage.arabic;
  bool get _storageReady => runtimeStatus['rootfsStorageReady'] == true;
  bool get _publicStorageGranted =>
      runtimeStatus['publicStorageGranted'] == true;
  bool get _publicArchivePresent =>
      runtimeStatus['rootfsPublicArchivePresent'] == true;
  bool get _permissionsReady =>
      runtimeStatus['notificationGranted'] == true &&
      runtimeStatus['batteryOptimizationIgnored'] == true &&
      _publicStorageGranted;

  String _ui(String arabic, String english) => _isArabicUi ? arabic : english;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    session = TerminalSession(
      onOutput: _handleTerminalOutput,
      onExit: (code) {
        unawaited(_finishRecordedTerminalSession(code));
        if (Platform.isAndroid) {
          unawaited(ArchRuntime.stopTerminalSessionService());
        }
        if (Platform.isAndroid && code != 0) {
          unawaited(_reportArm32LaunchExit(code));
        }
        if (!mounted) return;
        setState(
          () => statusText = _ui(
            'انتهت الجلسة محلياً برمز الخروج $code',
            'Local session exited with code $code',
          ),
        );
        terminal.write(
          '\r\n\x1b[90m[${_ui('انتهت الجلسة', 'Session ended')}: $code]\x1b[0m\r\n',
        );
      },
      onError: (error) {
        unawaited(_failRecordedTerminalSession());
        if (Platform.isAndroid) {
          unawaited(ArchRuntime.stopTerminalSessionService());
        }
        if (!mounted) return;
        final message = _friendlyError(error);
        setState(() {
          busy = false;
          statusText = _ui('خطأ محلي: $message', 'Local error: $message');
        });
        terminal.write(
          '\r\n\x1b[31m[${_ui('خطأ', 'Error')}: $message]\x1b[0m\r\n',
        );
      },
    );
    terminal.onOutput = session.write;
    terminal.onResize = (columns, rows, _, _) =>
        session.resize(rows: rows, columns: columns);
    terminalController.addListener(_syncSelection);
    unawaited(_loadTerminalPreferences());
    unawaited(_loadAiSettings());
    unawaited(_loadAiAgentState());
    unawaited(_loadAiModelCatalog());
    unawaited(_loadActivityHistory());
    unawaited(_restoreDeepTranscript());
    if (Platform.isAndroid) {
      _progressSubscription = ArchRuntime.setupProgress().listen((progress) {
        if (!mounted || progress.isEmpty) return;
        final previousPhase = runtimeStatus['setupPhase']?.toString();
        final nextPhase = progress['setupPhase']?.toString();
        setState(() {
          runtimeStatus = <String, Object?>{...runtimeStatus, ...progress};
          final message = progress['setupMessage']?.toString();
          // Live file names can change dozens of times a minute. Keep them in
          // the fixed-height progress card and only update the surrounding
          // status line at meaningful state boundaries to avoid layout jitter.
          final terminalOrBoundary =
              nextPhase != previousPhase ||
              nextPhase == 'complete' ||
              nextPhase == 'error' ||
              nextPhase == 'cancelled';
          if (terminalOrBoundary && message != null && message.isNotEmpty) {
            statusText = message;
          }
        });
      });
    }
    _statusTimer = Timer.periodic(
      const Duration(milliseconds: 900),
      (_) => _refreshStatus(),
    );
    unawaited(_refreshStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusTimer?.cancel();
    _transcriptFlushTimer?.cancel();
    _agentObservationTimer?.cancel();
    _environmentProbeTimer?.cancel();
    unawaited(_flushDeepTranscript());
    _progressSubscription?.cancel();
    terminalFocusNode.dispose();
    terminalController.removeListener(_syncSelection);
    terminalController.dispose();
    _aiAgentStateNotifier.dispose();
    _aiEnvironmentNotifier.dispose();
    _activityHistoryNotifier.dispose();
    _terminalInteractivePromptNotifier.dispose();
    unawaited(session.stop());
    if (Platform.isAndroid) unawaited(ArchRuntime.stopTerminalSessionService());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _permissionRequestInFlight = false;
      unawaited(_refreshStatus());
    }
  }

  Future<void> _refreshStatus() async {
    try {
      final status = await ArchRuntime.status();
      if (!mounted) return;
      setState(() => runtimeStatus = status);
      if (status['terminalEndRequested'] == true && !_endingFromNotification) {
        _endingFromNotification = true;
        try {
          _manualSessionEndRequested = true;
          if (session.isRunning) await session.stop();
          await ArchRuntime.acknowledgeTerminalEndRequest();
          if (mounted) {
            setState(
              () => statusText = _ui(
                'تم إنهاء جلسة Arch من الإشعار.',
                'The Arch session was ended from the notification.',
              ),
            );
            // End the visible Android task only after the PTY and foreground
            // service have been stopped. A later app launch starts a fresh
            // Arch session automatically and restores deep protection.
            await SystemNavigator.pop();
          }
        } finally {
          _endingFromNotification = false;
        }
        return;
      }
      if (shouldResumeAfterNotificationEnd(
        restartPending: status['terminalRestartPending'] == true,
      )) {
        final consumed = await ArchRuntime.consumeTerminalRestartRequest();
        if (consumed) {
          _manualSessionEndRequested = false;
          _automaticStartQueue.release();
        }
      }
      final shouldReconnect = shouldReconnectAfterProcessLoss(
        backgroundProtectionEnabled:
            status['terminalBackgroundProtectionEnabled'] == true,
        reconnectPending: status['terminalReconnectPending'] == true,
        serviceActive: status['terminalSessionForeground'] == true,
        manualEndRequested: _manualSessionEndRequested,
        sessionRunning: session.isRunning,
      );
      if (shouldReconnect && mounted) {
        setState(
          () => statusText = _ui(
            'أُعيد إنشاء التطبيق؛ ستُستأنف جلسة Arch تلقائياً الآن.',
            'The app was recreated; the Arch session will reconnect automatically now.',
          ),
        );
      }
      _queueAutomaticSessionStart();
      if (_archPermissionGateActive) {
        unawaited(_continueArchPermissionGate(status));
      }
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(
        () => statusText = _ui(
          'حالة Android غير متاحة: ${_friendlyError(error)}',
          'Android status is unavailable: ${_friendlyError(error)}',
        ),
      );
    }
  }

  Future<void> _loadTerminalPreferences() async {
    final preferences = await TerminalPreferences.load();
    if (!mounted) return;
    setState(() {
      _preferences = preferences;
      terminalFontSize = preferences.fontSize;
      soundEnabled = preferences.soundEnabled;
      soundVolume = preferences.soundVolume;
      interfaceLanguage = preferences.language;
      sessionName = preferences.sessionName;
      if (statusText == 'محلي بالكامل — اكتب أمراً أو افتح لوحة التحكم') {
        statusText = _ui(
          'محلي بالكامل — اكتب أمراً أو افتح لوحة التحكم',
          'Fully local — type a command or open settings.',
        );
      }
    });
  }

  Future<void> _loadAiSettings() async {
    try {
      final settings = await _aiSettingsStore.load();
      if (mounted) setState(() => _aiSettings = settings);
    } catch (_) {
      // A changed device credential can invalidate Keystore entries. Treat it
      // as no configured key and let the user save a replacement locally.
      if (mounted) {
        setState(
          () => _aiSettings = const AiSettings(
            provider: null,
            hasApiKey: false,
            consentToSendSelectedOutput: false,
          ),
        );
      }
    }
  }

  Future<void> _loadAiAgentState() async {
    try {
      var conversations = await _aiConversationStore.load();
      if (conversations.isEmpty) {
        final legacy = await _aiAgentStateStore.load();
        final now = DateTime.now();
        conversations = <AiAgentConversation>[
          AiAgentConversation(
            id: now.microsecondsSinceEpoch.toRadixString(36),
            title: legacy.messages.isEmpty
                ? _ui('محادثة جديدة', 'New conversation')
                : _conversationTitleFromState(legacy),
            createdAt: now,
            updatedAt: now,
            state: legacy,
          ),
        ];
        await _aiConversationStore.save(conversations);
      }
      final active = conversations.first;
      if (mounted) {
        setState(() {
          _aiConversations = conversations;
          _activeAiConversationId = active.id;
          _aiAgentState = active.state;
        });
        _aiAgentStateNotifier.value = active.state;
        _aiEnvironmentNotifier.value = active.state.environment;
      }
    } catch (_) {
      // The agent can start a new local task if stored history is unavailable.
    }
  }

  String _conversationTitleFromState(AiAgentTaskState state) {
    final userMessages = state.messages
        .where((message) => message.role == AiAgentRole.user)
        .toList();
    final firstUser = userMessages.isEmpty ? null : userMessages.first;
    final raw = firstUser?.content.trim();
    if (raw == null || raw.isEmpty) {
      return _ui('محادثة جديدة', 'New conversation');
    }
    return raw.length <= 42 ? raw : '${raw.substring(0, 42)}…';
  }

  Future<void> _persistActiveAiConversation(AiAgentTaskState state) async {
    final existing = _aiConversations
        .where((conversation) => conversation.id == _activeAiConversationId)
        .cast<AiAgentConversation?>()
        .firstOrNull;
    final now = DateTime.now();
    final current =
        existing ??
        AiAgentConversation(
          id: now.microsecondsSinceEpoch.toRadixString(36),
          title: _conversationTitleFromState(state),
          createdAt: now,
          updatedAt: now,
          state: state,
        );
    final nextCurrent = current.copyWith(
      title: current.state.messages.isEmpty && state.messages.isNotEmpty
          ? _conversationTitleFromState(state)
          : current.title,
      state: state,
    );
    final next = AiAgentConversationStore.upsert(_aiConversations, nextCurrent);
    if (mounted) {
      setState(() {
        _activeAiConversationId = nextCurrent.id;
        _aiConversations = next;
      });
    }
    await _aiConversationStore.save(next);
  }

  Future<void> _loadAiModelCatalog() async {
    final models = await _aiModelCatalogStore.load();
    final selected = await _aiModelCatalogStore.selectedModelId();
    if (mounted) {
      setState(() {
        _aiModels = models;
        _selectedAiModelId = selected;
      });
    }
  }

  Future<void> _loadActivityHistory() async {
    try {
      _activityHistoryNotifier.value = await _activityHistoryStore.load();
    } catch (_) {
      // The local activity view must not prevent terminal startup.
    }
  }

  Future<void> _replaceActivityHistory(LocalActivityHistory next) async {
    _activityHistoryNotifier.value = next;
    try {
      await _activityHistoryStore.save(next);
    } catch (_) {
      // The activity log is best-effort and remains local-only.
    }
  }

  Future<void> _recordTerminalSessionStart() async {
    final now = DateTime.now();
    final record = LocalTerminalSessionRecord(
      id: now.microsecondsSinceEpoch.toRadixString(36),
      label: sessionName.trim().isEmpty ? 'Arch' : sessionName.trim(),
      startedAt: now,
      status: LocalTerminalSessionStatus.active,
    );
    _activeRecordedTerminalSessionId = record.id;
    await _replaceActivityHistory(
      _activityHistoryNotifier.value.recordSession(record),
    );
  }

  Future<void> _finishRecordedTerminalSession(int code) async {
    final id = _activeRecordedTerminalSessionId;
    if (id == null) return;
    _activeRecordedTerminalSessionId = null;
    final matches = _activityHistoryNotifier.value.sessions
        .where((item) => item.id == id)
        .toList();
    if (matches.isEmpty) return;
    await _replaceActivityHistory(
      _activityHistoryNotifier.value.replaceSession(
        matches.first.close(exitCode: code),
      ),
    );
  }

  Future<void> _failRecordedTerminalSession() async {
    final id = _activeRecordedTerminalSessionId;
    if (id == null) return;
    _activeRecordedTerminalSessionId = null;
    final matches = _activityHistoryNotifier.value.sessions
        .where((item) => item.id == id)
        .toList();
    if (matches.isEmpty) return;
    await _replaceActivityHistory(
      _activityHistoryNotifier.value.replaceSession(matches.first.fail()),
    );
  }

  Future<void> _recordActivityDiscovery(AiSkillDiscovery discovery) async {
    if (discovery.isEmpty) return;
    await _replaceActivityHistory(
      _activityHistoryNotifier.value.recordDiscovery(discovery),
    );
  }

  Future<void> _toggleActivityFavorite(LocalCapabilityActivity item) =>
      _replaceActivityHistory(
        _activityHistoryNotifier.value.toggleFavorite(item),
      );

  Future<void> _deleteRecordedTerminalSession(String id) =>
      _replaceActivityHistory(_activityHistoryNotifier.value.deleteSession(id));

  Future<void> _recordApprovedTerminalCommand(String command) async {
    final sessionId = _activeRecordedTerminalSessionId;
    if (sessionId == null) return;
    await _replaceActivityHistory(
      _activityHistoryNotifier.value.recordApprovedCommand(sessionId, command),
    );
  }

  Future<void> _openLocalActivityHistory() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _LocalActivityHistoryPage(
        arabicUi: _isArabicUi,
        historyListenable: _activityHistoryNotifier,
        onToggleFavorite: _toggleActivityFavorite,
        onDeleteSession: _deleteRecordedTerminalSession,
        onRerunCommand: _reviewRecordedTerminalCommand,
      ),
    ),
  );

  Future<void> _discoverAiModels() async {
    final credentials = await _aiSettingsStore.readCredentials();
    if (credentials == null || _aiModelsRefreshing) return;
    setState(() => _aiModelsRefreshing = true);
    try {
      final discovered = await AiModelCatalogClient().discover(credentials);
      final previous = <String, AiModelInfo>{
        for (final model in _aiModels)
          '${model.provider.wireName}:${model.id}': model,
      };
      final merged = discovered
          .map(
            (model) =>
                previous['${model.provider.wireName}:${model.id}'] ?? model,
          )
          .toList();
      await _aiModelCatalogStore.save(merged);
      final selectedStillValid = merged.any(
        (model) =>
            model.id == _selectedAiModelId &&
            model.provider == credentials.provider,
      );
      final nextSelected = selectedStillValid
          ? _selectedAiModelId
          : (merged.isEmpty ? null : merged.first.id);
      if (nextSelected != null) {
        await _aiModelCatalogStore.selectModel(nextSelected);
      }
      if (mounted) {
        setState(() {
          _aiModels = merged;
          _selectedAiModelId = nextSelected;
        });
      }
    } catch (error) {
      if (mounted) _showError(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _aiModelsRefreshing = false);
    }
  }

  Future<void> _testAiModel(AiModelInfo model) async {
    final credentials = await _aiSettingsStore.readCredentials();
    if (credentials == null || _aiModelTesting) return;
    setState(() => _aiModelTesting = true);
    AiModelInfo result;
    try {
      await AiClient().propose(
        credentials: credentials,
        modelId: model.id,
        userRequest: 'Return exactly {"reply":"OK","command":null}.',
        maxTokens: 32,
      );
      result = model.tested(
        working: true,
        message: _ui(
          'نجح اختبار اتصال قصير.',
          'Short connection test succeeded.',
        ),
      );
    } catch (error) {
      result = model.tested(working: false, message: _friendlyError(error));
    }
    final updated = _aiModels
        .map(
          (item) => item.provider == result.provider && item.id == result.id
              ? result
              : item,
        )
        .toList();
    await _aiModelCatalogStore.save(updated);
    if (mounted) {
      setState(() {
        _aiModels = updated;
        _aiModelTesting = false;
      });
    }
  }

  Future<void> _openAiSettings() async {
    var provider = _aiSettings?.provider ?? AiProvider.googleAiStudio;
    var consent = _aiSettings?.consentToSendSelectedOutput ?? false;
    var approvalMode = _aiSettings?.approvalMode ?? AiApprovalMode.reviewEach;
    var workflowAdvanceMode =
        _aiSettings?.workflowAdvanceMode ?? AiWorkflowAdvanceMode.manual;
    final keyController = TextEditingController();
    final blockedCommandsController = TextEditingController(
      text: (_aiSettings?.blockedCommandPatterns ?? const <String>[]).join(
        '\n',
      ),
    );
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF111820),
          title: Text(_ui('مساعد AI الاختياري', 'Optional AI assistant')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  _ui(
                    'المفتاح يُخزن محلياً بشكل مشفر ولا يُضمّن في APK. لا يُتصل بالمزود إلا عند اكتشاف النماذج أو اختبارها أو إرسال رسالة للوكيل.',
                    'The key is encrypted locally and never included in the APK. The provider is contacted only to discover or test models or send an agent message.',
                  ),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFB7C5D3),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AiProvider>(
                  initialValue: provider,
                  items: AiProvider.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => provider = value ?? provider),
                  decoration: InputDecoration(
                    labelText: _ui('المزود', 'Provider'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: keyController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: _ui('مفتاح API', 'API key'),
                    hintText: _aiSettings?.hasApiKey == true
                        ? _ui(
                            'أدخل مفتاحاً جديداً للاستبدال',
                            'Enter a new key to replace the saved one',
                          )
                        : null,
                  ),
                ),
                CheckboxListTile(
                  value: consent,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) =>
                      setDialogState(() => consent = value ?? false),
                  title: Text(
                    _ui(
                      'أوافق على إرسال النص الذي أختاره فقط إلى المزود.',
                      'I consent to send only text I explicitly select to the provider.',
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Text(
                  _ui(
                    'التنفيذ السريع، إن فعّلته، يقتصر على الأوامر المحلية المصنفة آمنة؛ أما الأعلى خطراً فيبقى للمراجعة.',
                    'If enabled, fast execution is limited to locally normal-risk commands; higher-risk commands still require review.',
                  ),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFFFFD46A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _ui('وضع الموافقة', 'Approval mode'),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF9EE9FF),
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: <Widget>[
                    ChoiceChip(
                      selected: approvalMode == AiApprovalMode.reviewEach,
                      label: Text(_ui('مراجعة كل أمر', 'Review each command')),
                      onSelected: (_) => setDialogState(
                        () => approvalMode = AiApprovalMode.reviewEach,
                      ),
                    ),
                    ChoiceChip(
                      selected:
                          approvalMode == AiApprovalMode.typedForEveryCommand,
                      label: Text(
                        _ui('اكتب EXECUTE دائماً', 'Type EXECUTE always'),
                      ),
                      onSelected: (_) => setDialogState(
                        () =>
                            approvalMode = AiApprovalMode.typedForEveryCommand,
                      ),
                    ),
                    ChoiceChip(
                      selected:
                          approvalMode ==
                          AiApprovalMode.executeSafeAutomatically,
                      label: Text(
                        _ui('نفّذ الآمن سريعاً', 'Fast-run safe commands'),
                      ),
                      onSelected: (_) => setDialogState(
                        () => approvalMode =
                            AiApprovalMode.executeSafeAutomatically,
                      ),
                    ),
                  ],
                ),
                Text(
                  _ui(
                    'الأوامر المدمرة تطلب EXECUTE دائماً، والأوامر ذات الخطر المرتفع لا تنفذ تلقائياً.',
                    'Destructive commands always require EXECUTE; elevated-risk commands never run automatically.',
                  ),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9FB0C0),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _ui('تقدم Workflow', 'Workflow progress'),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF9EE9FF),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  children: <Widget>[
                    ChoiceChip(
                      selected:
                          workflowAdvanceMode == AiWorkflowAdvanceMode.manual,
                      label: Text(_ui('اطلب متابعة', 'Ask before next step')),
                      onSelected: (_) => setDialogState(
                        () =>
                            workflowAdvanceMode = AiWorkflowAdvanceMode.manual,
                      ),
                    ),
                    ChoiceChip(
                      selected:
                          workflowAdvanceMode ==
                          AiWorkflowAdvanceMode.automatic,
                      label: Text(
                        _ui('تابع تلقائياً', 'Continue automatically'),
                      ),
                      onSelected: (_) => setDialogState(
                        () => workflowAdvanceMode =
                            AiWorkflowAdvanceMode.automatic,
                      ),
                    ),
                  ],
                ),
                Text(
                  _ui(
                    'لا يتجاوز التقدم التلقائي أسئلة المستخدم أو طلب الموافقة على أمر.',
                    'Automatic progress never bypasses a user question or command approval.',
                  ),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9FB0C0),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: blockedCommandsController,
                  minLines: 1,
                  maxLines: 3,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: _ui(
                      'أوامر أو كلمات محظورة محلياً',
                      'Locally blocked command words',
                    ),
                    hintText: _ui(
                      'كل كلمة أو نمط في سطر، مثل: pacman -Syy',
                      'One word or pattern per line, e.g. pacman -Syy',
                    ),
                  ),
                ),
                Text(
                  _ui(
                    'لن يُنفذ أمر يحتوي نمطاً محظوراً، حتى عند المراجعة، إلا بعد إزالة النمط من هذه القائمة.',
                    'A matching command is blocked even in review mode until you remove its pattern here.',
                  ),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9FB0C0),
                  ),
                ),
                if (_aiSettings?.isReady == true) ...<Widget>[
                  const Divider(height: 24),
                  ExpansionTile(
                    initiallyExpanded: _selectedAiModelId == null,
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      _ui('اختيار النموذج', 'Choose model'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      _selectedAiModelId == null
                          ? _ui('لم يُختر نموذج بعد', 'No model selected yet')
                          : _ui(
                              'النموذج المختار محفوظ محلياً',
                              'Selected model is saved locally',
                            ),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF9FB0C0),
                      ),
                    ),
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              _ui(
                                'اكتشف النماذج المتاحة لمفتاحك',
                                'Discover models available to your key',
                              ),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFFB7C5D3),
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _aiModelsRefreshing
                                ? null
                                : () async {
                                    await _discoverAiModels();
                                    if (context.mounted) setDialogState(() {});
                                  },
                            icon: _aiModelsRefreshing
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh_rounded, size: 17),
                            label: Text(_ui('اكتشاف', 'Discover')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: AiModelPriceTier.values
                            .map(
                              (tier) => FilterChip(
                                label: Text(switch (tier) {
                                  AiModelPriceTier.free => _ui('مجاني', 'Free'),
                                  AiModelPriceTier.economic => _ui(
                                    'اقتصادي',
                                    'Economic',
                                  ),
                                  AiModelPriceTier.paid => _ui('مدفوع', 'Paid'),
                                }),
                                selected: _aiModelFilters.contains(tier),
                                onSelected: (selected) => setDialogState(() {
                                  if (selected) {
                                    _aiModelFilters.add(tier);
                                  } else if (_aiModelFilters.length > 1) {
                                    _aiModelFilters.remove(tier);
                                  }
                                }),
                              ),
                            )
                            .toList(),
                      ),
                      Builder(
                        builder: (_) {
                          final activeProvider = _aiSettings?.provider;
                          final visibleModels = _aiModels
                              .where(
                                (model) =>
                                    model.provider == activeProvider &&
                                    _aiModelFilters.contains(model.priceTier),
                              )
                              .toList();
                          if (_aiModels.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _ui(
                                  'احفظ المفتاح ثم اضغط «اكتشاف» لإظهار نماذج مزودك.',
                                  'Save the key, then press Discover to show your provider models.',
                                ),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF7F91A3),
                                ),
                              ),
                            );
                          }
                          if (visibleModels.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _ui(
                                  'لا توجد نماذج تطابق المرشحات المختارة.',
                                  'No models match the selected filters.',
                                ),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF7F91A3),
                                ),
                              ),
                            );
                          }
                          return RadioGroup<String>(
                            groupValue: _selectedAiModelId,
                            onChanged: (id) async {
                              if (id == null) return;
                              await _aiModelCatalogStore.selectModel(id);
                              if (mounted) {
                                setState(() => _selectedAiModelId = id);
                              }
                              if (context.mounted) {
                                setDialogState(() {});
                              }
                            },
                            child: Column(
                              children: visibleModels
                                  .take(12)
                                  .map(
                                    (model) => RadioListTile<String>(
                                      value: model.id,
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      title: Text(
                                        model.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      subtitle: Text(
                                        '${switch (model.priceTier) {
                                          AiModelPriceTier.free => _ui('مجاني', 'Free'),
                                          AiModelPriceTier.economic => _ui('اقتصادي', 'Economic'),
                                          AiModelPriceTier.paid => _ui('مدفوع', 'Paid'),
                                        }} · ${switch (model.testState) {
                                          AiModelTestState.untested => _ui('غير مختبر', 'Untested'),
                                          AiModelTestState.working => _ui('يعمل', 'Working'),
                                          AiModelTestState.failed => _ui('فشل الاختبار', 'Test failed'),
                                        }}',
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                      secondary: IconButton(
                                        tooltip: _ui(
                                          'اختبار قصير',
                                          'Short test',
                                        ),
                                        onPressed: _aiModelTesting
                                            ? null
                                            : () async {
                                                await _testAiModel(model);
                                                if (context.mounted) {
                                                  setDialogState(() {});
                                                }
                                              },
                                        icon: _aiModelTesting
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.bolt_outlined,
                                                size: 18,
                                              ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            if (_aiSettings?.hasApiKey == true)
              TextButton(
                onPressed: () async {
                  await _aiSettingsStore.deleteCurrentKey();
                  await _loadAiSettings();
                  if (context.mounted) Navigator.pop(context);
                },
                child: Text(_ui('حذف المفتاح', 'Delete key')),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_ui('إلغاء', 'Cancel')),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await _aiSettingsStore.save(
                    provider: provider,
                    apiKey: keyController.text,
                    consentToSendSelectedOutput: consent,
                    approvalMode: approvalMode,
                    workflowAdvanceMode: workflowAdvanceMode,
                    blockedCommandPatterns: blockedCommandsController.text
                        .split(RegExp(r'[\n,]')),
                  );
                  await _loadAiSettings();
                  if (context.mounted) Navigator.pop(context);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _ui(
                            'أدخل مفتاح API صحيحاً ووافق على إرسال النص المختار.',
                            'Enter an API key and select the consent option.',
                          ),
                        ),
                      ),
                    );
                  }
                }
              },
              child: Text(_ui('حفظ محلي', 'Save locally')),
            ),
          ],
        ),
      ),
    );
    keyController.dispose();
    blockedCommandsController.dispose();
  }

  void _handleTerminalOutput(String text) {
    final imageResult = _inlineImageDecoder.consume(text);
    var terminalText = _terminalControlFilter.consume(imageResult.terminalText);
    final environmentResult = _environmentDetector.consume(
      terminalText,
      runtimeStatus,
    );
    terminalText = environmentResult.terminalText;
    if (environmentResult.snapshot != null) {
      _environmentProbeTimer?.cancel();
      unawaited(_saveAiEnvironment(environmentResult.snapshot!));
    }
    if (terminalText.isNotEmpty) terminal.write(terminalText);
    final interactivePrompt = _terminalInteractivePromptDetector.consume(
      terminalText,
    );
    if (interactivePrompt != null) {
      _terminalInteractivePromptNotifier.value = interactivePrompt;
      if (mounted) {
        setState(
          () => statusText = interactivePrompt.summary(arabicUi: _isArabicUi),
        );
      }
    }
    final observation = _agentObservationBuffer;
    if (observation != null &&
        terminalText.isNotEmpty &&
        observation.length < 6000) {
      final remaining = 6000 - observation.length;
      observation.write(
        terminalText.length <= remaining
            ? terminalText
            : terminalText.substring(0, remaining),
      );
      _agentObservationTimer?.cancel();
      _agentObservationTimer = Timer(
        const Duration(milliseconds: 1500),
        _finishAgentObservation,
      );
    }
    if (imageResult.images.isNotEmpty && mounted) {
      setState(() {
        _inlineImages.addAll(imageResult.images);
      });
    }
    _networkOutputTail += terminalText;
    if (_networkOutputTail.length > 4096) {
      _networkOutputTail = _networkOutputTail.substring(
        _networkOutputTail.length - 4096,
      );
    }
    final networkDiagnostic = pacmanNetworkDiagnostic(
      output: _networkOutputTail,
      arabicUi: _isArabicUi,
      dnsConfigured: runtimeStatus['rootfsDnsConfigured'] == true,
      mirrorUrl:
          runtimeStatus['rootfsMirrorUrl']?.toString() ??
          'http://mirror.archlinuxarm.org/\$arch/\$repo',
    );
    if (networkDiagnostic != null &&
        networkDiagnostic != _lastPacmanNetworkDiagnostic) {
      _lastPacmanNetworkDiagnostic = networkDiagnostic;
      if (mounted) setState(() => statusText = networkDiagnostic);
      unawaited(ArchRuntime.reportPacmanNetworkFailure(networkDiagnostic));
    }
    if (runtimeStatus['terminalSessionDeep'] != true) return;
    _deepTranscriptBuffer.append(terminalText);
    _transcriptFlushTimer ??= Timer(const Duration(seconds: 1), () {
      _transcriptFlushTimer = null;
      unawaited(_flushDeepTranscript());
    });
  }

  Future<void> _submitInteractiveTerminalReply(String reply) async {
    final prompt = _terminalInteractivePromptNotifier.value;
    if (prompt == null) return;
    if (!prompt.allowsAgentReply) {
      if (mounted) {
        _showInfo(
          _ui(
            'هذا الطلب حساس. اكتب القيمة مباشرةً في الطرفية ولا ترسلها إلى الوكيل.',
            'This request is sensitive. Enter the value directly in the terminal and do not send it to the agent.',
          ),
        );
      }
      return;
    }
    if (!isSafeInteractiveTerminalReply(reply)) {
      if (mounted) {
        _showError(
          _ui(
            'اكتب رداً قصيراً في سطر واحد؛ لا تُرسل أسطر متعددة أو رموز تحكم.',
            'Use a short single-line reply; multiline input and control characters are not allowed.',
          ),
        );
      }
      return;
    }
    session.write('${reply.trim()}\n');
    _terminalInteractivePromptDetector.clear();
    _terminalInteractivePromptNotifier.value = null;
    if (mounted) {
      setState(
        () => statusText = _ui(
          'أُرسل ردك الموافق عليه إلى السؤال التفاعلي في الطرفية.',
          'Your approved reply was sent to the interactive terminal prompt.',
        ),
      );
    }
    await _appendAiAgentMessage(
      AiAgentRole.system,
      _ui(
        'أُرسل رد وافق عليه المستخدم إلى سؤال تفاعلي في الطرفية؛ لم يُحفظ النص المدخل في الدردشة.',
        'A user-approved reply was sent to an interactive terminal prompt; the entered text was not saved in chat.',
      ),
    );
  }

  void _dismissInteractiveTerminalPrompt() {
    _terminalInteractivePromptDetector.clear();
    _terminalInteractivePromptNotifier.value = null;
    if (mounted) {
      setState(
        () => statusText = _ui(
          'انتهت متابعة سؤال الطرفية. يمكنك متابعة المحادثة أو انتظار سؤال جديد.',
          'Interactive terminal prompt tracking ended. You can continue chatting or wait for a new prompt.',
        ),
      );
    }
  }

  Future<void> _askAiAboutInteractiveTerminalPrompt(
    AiCredentials credentials,
  ) async {
    final prompt = _terminalInteractivePromptNotifier.value;
    if (prompt == null || !prompt.allowsAgentReply || _aiBusy) return;
    _terminalInteractivePromptNotifier.value = prompt.copyWith(
      analysisInProgress: true,
    );
    setState(() => _aiBusy = true);
    try {
      final proposal = await AiClient().propose(
        credentials: credentials,
        userRequest: _ui(
          'حلل سؤال طرفية تفاعلياً غير حساساً. المقتطف المحدود هو: `${prompt.safeExcerpt}`. اشرح ما الذي ينتظره البرنامج وما خيارات المستخدم الآمنة. لا تنشئ Workflow، لا تقترح command، وأعِد terminalReply في سطر واحد فقط عندما تكون الإجابة آمنة وواضحة. لا تكرر المقتطف حرفياً.',
          'Analyze a non-sensitive interactive terminal prompt. The narrow excerpt is: `${prompt.safeExcerpt}`. Explain what the program is waiting for and the user’s safe choices. Do not create a workflow, do not propose a command, and return terminalReply as one line only when the answer is safe and unambiguous. Do not quote the excerpt verbatim.',
        ),
        maxTokens: 420,
      );
      final proposedReply = proposal.terminalReply;
      final safeReply =
          proposedReply != null && isSafeInteractiveTerminalReply(proposedReply)
          ? proposedReply
          : null;
      final explanation = proposal.reply
          .replaceAll(
            prompt.safeExcerpt,
            _ui('سؤال الطرفية', 'the terminal prompt'),
          )
          .trim();
      final current = _terminalInteractivePromptNotifier.value;
      if (current?.signature == prompt.signature) {
        _terminalInteractivePromptNotifier.value = prompt.copyWith(
          assistantExplanation: explanation.length <= 900
              ? explanation
              : explanation.substring(0, 900),
          assistantReply: safeReply,
          analysisInProgress: false,
        );
      }
      await _appendAiAgentMessage(
        AiAgentRole.agent,
        _ui(
          'حلّل مساعد الطرفية السؤال التفاعلي محلياً. راجع الشرح والرد المقترح في البطاقة ثم اكتب بنفسك ما توافق على إرساله.',
          'The terminal assistant analyzed the interactive prompt locally. Review the explanation and proposed reply in the card, then type what you approve sending yourself.',
        ),
      );
    } catch (error) {
      final current = _terminalInteractivePromptNotifier.value;
      if (current?.signature == prompt.signature) {
        _terminalInteractivePromptNotifier.value = prompt.copyWith(
          analysisInProgress: false,
        );
      }
      await _appendAiAgentMessage(
        AiAgentRole.system,
        _ui(
          'تعذر على مساعد الطرفية تحليل السؤال الآن: ${_friendlyError(error)}',
          'The terminal assistant could not analyze the prompt now: ${_friendlyError(error)}',
        ),
      );
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  String _auditedAiReply(AiProposal proposal) =>
      renderAiProposalAudit(proposal, arabicUi: _isArabicUi);

  Future<void> _appendAiAgentMessage(
    AiAgentRole role,
    String content, {
    String? proposedCommand,
    String? workflowId,
    List<String> localResultPaths = const <String>[],
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    final next = _aiAgentState.add(
      AiAgentMessage(
        role: role,
        content: trimmed,
        createdAt: DateTime.now(),
        proposedCommand: proposedCommand?.trim().isEmpty == true
            ? null
            : proposedCommand?.trim(),
        workflowId: workflowId,
        localResultPaths: localResultPaths
            .where((path) => RegExp(r'^/sdcard(?:/[^\n\r]*)?$').hasMatch(path))
            .take(24)
            .toList(growable: false),
      ),
    );
    if (mounted) setState(() => _aiAgentState = next);
    _aiAgentStateNotifier.value = next;
    try {
      await _aiAgentStateStore.save(next);
      await _persistActiveAiConversation(next);
    } catch (_) {
      // Local chat persistence must not prevent a running agent exchange.
    }
  }

  Future<void> _replaceAiAgentState(AiAgentTaskState next) async {
    if (mounted) setState(() => _aiAgentState = next);
    _aiAgentStateNotifier.value = next;
    try {
      await _aiAgentStateStore.save(next);
      await _persistActiveAiConversation(next);
    } catch (_) {
      // A local task-board update must not block the active chat exchange.
    }
  }

  Future<void> _createAiWorkItem(
    String title, {
    AiAgentWorkStatus status = AiAgentWorkStatus.queued,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final now = DateTime.now();
    final item = AiAgentWorkItem(
      id: now.microsecondsSinceEpoch.toRadixString(36),
      title: trimmed.length <= 280 ? trimmed : trimmed.substring(0, 280),
      status: status,
      createdAt: now,
      updatedAt: now,
    );
    await _replaceAiAgentState(_aiAgentState.addWorkItem(item));
  }

  Future<String> _createAiWorkflow(
    String goal,
    List<AiWorkflowStep> workflow, {
    required bool waitsForApproval,
  }) async {
    final now = DateTime.now();
    final workflowId = now.microsecondsSinceEpoch.toRadixString(36);
    final steps = workflow.isEmpty
        ? <AiWorkflowStep>[
            AiWorkflowStep(
              title: _ui(
                'فهم الطلب وتحديد الخطوة التالية',
                'Understand the request and identify the next step',
              ),
              detail: _ui(
                'لم يُرجع النموذج خطة منظمة؛ راجع الرد وحدّث هذه المهمة إذا لزم.',
                'The model did not return a structured plan; review its reply and update this task if needed.',
              ),
            ),
          ]
        : workflow;
    final goalLabel = goal.trim().length <= 280
        ? goal.trim()
        : goal.trim().substring(0, 280);
    final items = <AiAgentWorkItem>[
      for (var index = 0; index < steps.length; index++)
        AiAgentWorkItem(
          id: '$workflowId-$index',
          title: steps[index].title.length <= 160
              ? steps[index].title
              : steps[index].title.substring(0, 160),
          detail: steps[index].detail.length <= 300
              ? steps[index].detail
              : steps[index].detail.substring(0, 300),
          status: index == 0
              ? (waitsForApproval
                    ? AiAgentWorkStatus.waitingForApproval
                    : AiAgentWorkStatus.inProgress)
              : AiAgentWorkStatus.queued,
          createdAt: now,
          updatedAt: now,
          workflowId: workflowId,
          workflowGoal: goalLabel,
          order: index,
        ),
    ];
    await _replaceAiAgentState(_aiAgentState.addWorkItems(items));
    return workflowId;
  }

  Future<void> _setAiWorkItemStatus(String id, AiAgentWorkStatus status) =>
      _replaceAiAgentState(_aiAgentState.updateWorkItem(id, status));

  Future<void> _deleteAiWorkItem(String id) =>
      _replaceAiAgentState(_aiAgentState.removeWorkItem(id));

  void _beginAgentObservation(String command, {String? workflowId}) {
    _agentObservationTimer?.cancel();
    _observedAgentCommand = command;
    _observedAgentWorkflowId = workflowId;
    _agentObservationBuffer = StringBuffer();
    _agentObservationTimer = Timer(
      const Duration(seconds: 4),
      _finishAgentObservation,
    );
  }

  void _finishAgentObservation() {
    _agentObservationTimer?.cancel();
    _agentObservationTimer = null;
    final command = _observedAgentCommand;
    final workflowId = _observedAgentWorkflowId;
    final output = _agentObservationBuffer?.toString().trim() ?? '';
    _observedAgentCommand = null;
    _observedAgentWorkflowId = null;
    _agentObservationBuffer = null;
    if (command == null) return;
    final listedDirectory = deviceDirectoryFromListCommand(command);
    final parsedDeviceFilePreview = isBoundedDeviceFileSearchCommand(command)
        ? parseDeviceFileSearchPreview(output)
        : listedDirectory == null
        ? null
        : parseDeviceDirectoryListingPreview(
            output,
            directory: listedDirectory,
          );
    final deviceFilePreview = parsedDeviceFilePreview?.isEmpty == true
        ? null
        : parsedDeviceFilePreview;
    if (deviceFilePreview != null && mounted) {
      setState(() => _deviceFileSearchPreview = deviceFilePreview);
    }
    final commandResult = classifyTerminalCommandOutput(
      output,
      arabicUi: _isArabicUi,
    );
    final pacmanDiagnostic = pacmanNetworkDiagnostic(
      output: output,
      arabicUi: _isArabicUi,
      dnsConfigured: runtimeStatus['rootfsDnsConfigured'] == true,
      mirrorUrl:
          runtimeStatus['rootfsMirrorUrl']?.toString() ??
          'http://mirror.archlinuxarm.org/\$arch/\$repo',
    );
    unawaited(() async {
      await _appendAiAgentMessage(
        AiAgentRole.observation,
        deviceFilePreview == null
            ? '${_ui('نتيجة محلية بعد الأمر', 'Local result after command')} `$command`:\n${pacmanDiagnostic ?? commandResult.summary}'
            : _ui(
                'اكتمل بحث محلي عن الملفات. عُرضت ${deviceFilePreview.paths.length} نتيجة داخل التطبيق ولم تُرسل الأسماء أو المسارات إلى مزود AI.',
                'A local file search completed. ${deviceFilePreview.paths.length} result(s) are shown in the app; names and paths were not sent to the AI provider.',
              ),
        workflowId: workflowId,
        localResultPaths: deviceFilePreview?.paths ?? const <String>[],
      );
      if (workflowId != null) {
        if (commandResult.isSuccess || deviceFilePreview != null) {
          await _replaceAiAgentState(
            _aiAgentState.completeWorkflowStep(workflowId),
          );
          if (_aiSettings?.workflowAdvanceMode ==
              AiWorkflowAdvanceMode.automatic) {
            final credentials = await _aiSettingsStore.readCredentials();
            if (credentials != null) {
              await _maybeAutomaticallyContinueWorkflow(
                credentials,
                workflowId,
              );
            }
          }
        } else {
          await _replaceAiAgentState(
            _aiAgentState.flagWorkflowAttention(workflowId),
          );
          await _appendAiAgentMessage(
            AiAgentRole.system,
            commandResult.isFailure
                ? _ui(
                    'لم تكتمل المهمة: سجّل التطبيق فشل الأمر محلياً. سيقترح المساعد خطوة إصلاح مختلفة بدلاً من إعلان النجاح.',
                    'The task was not completed: the app recorded a local command failure. The assistant will propose a different repair instead of declaring success.',
                  )
                : _ui(
                    'لم تكتمل المهمة: لا توجد بعد ملاحظة محلية تثبت نجاح الأمر. راجع النتيجة أو انتظر/تابع التحقق.',
                    'The task was not completed: no local observation proves success yet. Review the result or wait/continue verification.',
                  ),
            workflowId: workflowId,
          );
          if (commandResult.isFailure) {
            final credentials = await _aiSettingsStore.readCredentials();
            if (credentials != null) {
              await _requestAiErrorRecovery(
                credentials,
                workflowId: workflowId,
                command: command,
                localSummary: pacmanDiagnostic ?? commandResult.summary,
              );
            }
          }
        }
      }
    }());
  }

  Future<void> _requestAiErrorRecovery(
    AiCredentials credentials, {
    required String workflowId,
    required String command,
    required String localSummary,
  }) async {
    if (_aiBusy) return;
    setState(() => _aiBusy = true);
    try {
      await _replaceAiAgentState(
        _aiAgentState.reopenWorkflowAttention(workflowId),
      );
      final workflowSteps = _aiAgentState.itemsForWorkflow(workflowId);
      final step = workflowSteps.isEmpty ? null : workflowSteps.first;
      final goal = step?.workflowGoal ?? step?.title ?? command;
      final skillContext = _aiAgentState.skillDiscovery?.mainAgentContext ?? '';
      final proposal = await AiClient().propose(
        credentials: credentials,
        userRequest:
            'Recover the existing terminal workflow "$goal". The user-approved command "$command" did not succeed. Local diagnostic summary: "$localSummary". Do not claim the task succeeded, do not repeat the same command blindly, do not create a new workflow, and do not expose raw terminal output. Identify the likely failed stage from the supplied summary and propose at most one different safe command, or ask one focused question if more information is required.',
        taskContext: <String>[
          _aiAgentState.providerContext,
          skillContext,
        ].where((value) => value.isNotEmpty).join('\n\n'),
        preferredLanguage: preferredAiReplyLanguage(goal),
      );
      if (proposal.inputRequest != null) {
        await _replaceAiAgentState(
          _aiAgentState.requestWorkflowInput(
            workflowId,
            proposal.inputRequest!,
          ),
        );
      } else if (proposal.command == null) {
        await _replaceAiAgentState(
          _aiAgentState.flagWorkflowAttention(workflowId),
        );
        await _appendAiAgentMessage(
          AiAgentRole.system,
          _ui(
            'لم يقدم المساعد أمر إصلاح قابل للتنفيذ بعد؛ تبقى المهمة بحاجة إلى مراجعة ولا تُعلَّم مكتملة.',
            'The assistant did not provide an executable repair command yet; the task remains under review and is not marked complete.',
          ),
          workflowId: workflowId,
        );
      }
      await _appendAiAgentMessage(
        AiAgentRole.agent,
        _auditedAiReply(proposal),
        proposedCommand: proposal.command,
        workflowId: workflowId,
      );
      await _prepareWorkflowCommandApproval(
        proposal.command,
        workflowId: workflowId,
      );
    } catch (error) {
      await _replaceAiAgentState(
        _aiAgentState.flagWorkflowAttention(workflowId),
      );
      await _appendAiAgentMessage(
        AiAgentRole.system,
        _ui(
          'تعذر تجهيز إصلاح تلقائي: ${_friendlyError(error)}. تبقى المهمة بحاجة إلى متابعة.',
          'Could not prepare an automatic repair: ${_friendlyError(error)}. The task remains under review.',
        ),
        workflowId: workflowId,
      );
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _createAiConversation() async {
    final now = DateTime.now();
    final conversation = AiAgentConversation(
      id: now.microsecondsSinceEpoch.toRadixString(36),
      title: _ui('محادثة جديدة', 'New conversation'),
      createdAt: now,
      updatedAt: now,
      state: AiAgentTaskState(environment: _aiAgentState.environment),
    );
    final next = AiAgentConversationStore.upsert(
      _aiConversations,
      conversation,
    );
    if (mounted) {
      setState(() {
        _aiConversations = next;
        _activeAiConversationId = conversation.id;
        _aiAgentState = conversation.state;
      });
    }
    _aiAgentStateNotifier.value = conversation.state;
    _aiEnvironmentNotifier.value = conversation.state.environment;
    await _aiAgentStateStore.save(conversation.state);
    await _aiConversationStore.save(next);
  }

  Future<void> _openAiConversation(String id) async {
    final conversation = _aiConversations
        .where((item) => item.id == id)
        .cast<AiAgentConversation?>()
        .firstOrNull;
    if (conversation == null) return;
    if (mounted) {
      setState(() {
        _activeAiConversationId = conversation.id;
        _aiAgentState = conversation.state;
      });
    }
    _aiAgentStateNotifier.value = conversation.state;
    _aiEnvironmentNotifier.value = conversation.state.environment;
    await _aiAgentStateStore.save(conversation.state);
  }

  Future<void> _deleteAiConversation(String id) async {
    final next = AiAgentConversationStore.removeById(_aiConversations, id);
    if (next.isEmpty) {
      await _createAiConversation();
      return;
    }
    final wasActive = id == _activeAiConversationId;
    if (mounted) setState(() => _aiConversations = next);
    await _aiConversationStore.save(next);
    if (wasActive) await _openAiConversation(next.first.id);
  }

  Future<void> _saveAiEnvironment(AiEnvironmentSnapshot snapshot) async {
    final next = _aiAgentState.withEnvironment(snapshot);
    await _replaceAiAgentState(next);
    _aiEnvironmentNotifier.value = snapshot;
  }

  void _scanAiEnvironment({bool userRequested = false}) {
    if (!session.isRunning) {
      if (userRequested) {
        _showInfo(
          _ui(
            'شغّل جلسة Arch أولاً لتحديث البيئة.',
            'Start an Arch session first to refresh the environment.',
          ),
        );
      }
      return;
    }
    _environmentProbeTimer?.cancel();
    _environmentProbeTimer = Timer(
      userRequested ? Duration.zero : const Duration(milliseconds: 350),
      () {
        if (!session.isRunning) return;
        session.write(_environmentDetector.beginProbe());
        _environmentProbeTimer = Timer(const Duration(seconds: 6), () {
          if (!_environmentDetector.isProbeActive) return;
          _environmentDetector.cancel();
          if (userRequested && mounted) {
            _showInfo(
              _ui(
                'انتهت مهلة فحص البيئة؛ أعد المحاولة بعد ظهور موجّه Arch.',
                'Environment scan timed out; retry after the Arch prompt is ready.',
              ),
            );
          }
        });
      },
    );
  }

  Future<void> _flushDeepTranscript() async {
    final pending = _deepTranscriptBuffer.take();
    if (pending.isEmpty) return;
    try {
      await ArchRuntime.appendDeepSessionTranscript(pending);
    } catch (_) {
      // Transcript persistence must never prevent a running terminal from working.
    }
  }

  Future<void> _restoreDeepTranscript() async {
    try {
      final transcript = await ArchRuntime.readDeepSessionTranscript();
      if (!mounted || transcript.isEmpty) return;
      terminal.write(
        '\r\n\x1b[90m[${_ui('استعادة سجل الجلسة العميقة', 'Deep session transcript restored')}]\x1b[0m\r\n',
      );
      terminal.write(transcript);
      terminal.write('\r\n');
    } catch (_) {
      // A missing or unreadable optional transcript must not block a fresh terminal.
    }
  }

  void _syncSelection() {
    final active = terminalController.selection != null;
    if (mounted && active != hasSelection) {
      setState(() => hasSelection = active);
    }
  }

  Future<void> _setTerminalFontSize(double value) async {
    final next = value.clamp(
      TerminalPreferences.minFontSize,
      TerminalPreferences.maxFontSize,
    );
    setState(() => terminalFontSize = next);
    await _preferences?.setFontSize(next);
  }

  Future<void> _setSoundEnabled(bool value) async {
    setState(() => soundEnabled = value);
    await _preferences?.setSoundEnabled(value);
    if (value) unawaited(_playSound(AppSoundEvent.success));
  }

  Future<void> _setSoundVolume(double value) async {
    final next = value.clamp(0.0, 1.0);
    setState(() => soundVolume = next);
    await _preferences?.setSoundVolume(next);
  }

  Future<void> _playSound(AppSoundEvent event) async {
    if (!soundEnabled || soundVolume <= 0) return;
    try {
      await AppSoundFeedback.play(event);
    } catch (_) {
      // Sound feedback is optional and must never block a local action.
    }
  }

  Future<void> _setInterfaceLanguage(InterfaceLanguage value) async {
    setState(() => interfaceLanguage = value);
    await _preferences?.setLanguage(value);
  }

  Future<void> _editSessionName() async {
    final controller = TextEditingController(text: sessionName);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF111820),
        title: Text(_ui('اسم الجلسة', 'Session name')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          decoration: InputDecoration(
            hintText: _ui('مثال: تطوير Arch', 'Example: Arch development'),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_ui('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () async {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              setState(() => sessionName = value);
              await _preferences?.setSessionName(value);
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(_ui('حفظ', 'Save')),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _copySelection() async {
    final selection = terminalController.selection;
    if (selection == null) return;
    await Clipboard.setData(
      ClipboardData(
        text: withoutInteractivePrompts(terminal.buffer.getText(selection)),
      ),
    );
    terminalController.clearSelection();
    if (mounted) _showInfo(_ui('تم نسخ النص المحدد.', 'Selected text copied.'));
  }

  String? _selectedTerminalText() {
    final selection = terminalController.selection;
    return selection == null
        ? null
        : withoutInteractivePrompts(terminal.buffer.getText(selection));
  }

  Future<void> _openAiAssistant() async {
    final credentials = await _aiSettingsStore.readCredentials();
    if (credentials == null) {
      if (mounted) {
        _showInfo(
          _ui(
            'اضبط مزود AI ومفتاحك وموافقتك أولاً.',
            'Configure an AI provider, your key, and consent first.',
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _AiAgentPage(
          arabicUi: _isArabicUi,
          stateProvider: () => _aiAgentState,
          stateListenable: _aiAgentStateNotifier,
          environmentListenable: _aiEnvironmentNotifier,
          interactivePromptListenable: _terminalInteractivePromptNotifier,
          conversations: () => _aiConversations,
          activeConversationId: () => _activeAiConversationId,
          hasTerminalSelection: () =>
              _selectedTerminalText()?.trim().isNotEmpty == true,
          onCreateConversation: _createAiConversation,
          onOpenConversation: _openAiConversation,
          onDeleteConversation: _deleteAiConversation,
          onRefreshEnvironment: () => _scanAiEnvironment(userRequested: true),
          onSend: (prompt, includeSelection) => _requestAiProposal(
            credentials,
            prompt,
            includeSelection ? _selectedTerminalText() : null,
          ),
          onSubmitInteractiveTerminalReply: _submitInteractiveTerminalReply,
          onDismissInteractiveTerminalPrompt: _dismissInteractiveTerminalPrompt,
          onAskInteractiveTerminalPrompt: () =>
              _askAiAboutInteractiveTerminalPrompt(credentials),
          onReviewCommand: (message) => _reviewAiProposal(
            AiProposal(
              reply: message.content,
              command: message.proposedCommand,
            ),
            workflowId: message.workflowId,
          ),
          onOpenSettings: _openAiSettings,
          onCreateWorkItem: _createAiWorkItem,
          onSetWorkItemStatus: _setAiWorkItemStatus,
          onDeleteWorkItem: _deleteAiWorkItem,
          onSubmitWorkflowInput: (workflowId, response) =>
              _submitAiWorkflowInput(credentials, workflowId, response),
          onContinueWorkflow: (workflowId) =>
              _continueAiWorkflow(credentials, workflowId),
        ),
      ),
    );
  }

  String _policyChangeDescription(AiPolicyChange change) =>
      switch (change.kind) {
        AiPolicyChangeKind.useSafeAutomatic => _ui(
          'تفعيل التنفيذ السريع للأوامر المصنفة محلياً آمنة فقط. الأوامر الأعلى خطراً ستبقى للمراجعة، والمدمرة ستطلب EXECUTE.',
          'Enable fast execution only for locally normal-risk commands. Elevated commands stay in review and destructive ones require EXECUTE.',
        ),
        AiPolicyChangeKind.useReviewEach => _ui(
          'العودة إلى مراجعة كل أمر قبل التنفيذ.',
          'Return to reviewing every command before execution.',
        ),
        AiPolicyChangeKind.useTypedEvery => _ui(
          'طلب كتابة EXECUTE لكل أمر قبل التنفيذ.',
          'Require typing EXECUTE for every command before execution.',
        ),
        AiPolicyChangeKind.addBlock => _ui(
          'حظر أي أمر يحتوي: ${change.pattern}',
          'Block every command containing: ${change.pattern}',
        ),
        AiPolicyChangeKind.removeBlock => _ui(
          'إزالة حظر النمط: ${change.pattern}',
          'Remove the blocked pattern: ${change.pattern}',
        ),
      };

  Future<void> _applyAiPolicyChange(AiPolicyChange change) async {
    final current = _aiSettings;
    if (current == null) return;
    var mode = current.approvalMode;
    final patterns = <String>[...current.blockedCommandPatterns];
    switch (change.kind) {
      case AiPolicyChangeKind.useSafeAutomatic:
        mode = AiApprovalMode.executeSafeAutomatically;
      case AiPolicyChangeKind.useReviewEach:
        mode = AiApprovalMode.reviewEach;
      case AiPolicyChangeKind.useTypedEvery:
        mode = AiApprovalMode.typedForEveryCommand;
      case AiPolicyChangeKind.addBlock:
        final pattern = change.pattern?.trim().toLowerCase();
        if (pattern != null &&
            pattern.isNotEmpty &&
            !patterns.contains(pattern)) {
          patterns.add(pattern);
        }
      case AiPolicyChangeKind.removeBlock:
        final pattern = change.pattern?.trim().toLowerCase();
        if (pattern != null) patterns.remove(pattern);
    }
    await _aiSettingsStore.saveExecutionPolicy(
      approvalMode: mode,
      blockedCommandPatterns: patterns,
      workflowAdvanceMode: current.workflowAdvanceMode,
    );
    await _loadAiSettings();
  }

  Future<bool> _handleAiPolicyChatInstruction(String prompt) async {
    final pending = _pendingAiPolicyChange;
    if (pending != null) {
      switch (parseWorkflowApproval(prompt)) {
        case AiWorkflowApprovalDecision.approved:
          await _applyAiPolicyChange(pending);
          _pendingAiPolicyChange = null;
          await _appendAiAgentMessage(
            AiAgentRole.system,
            '${_ui('تم حفظ سياسة التنفيذ', 'Execution policy saved')}: ${_policyChangeDescription(pending)}',
          );
          return true;
        case AiWorkflowApprovalDecision.declined:
          _pendingAiPolicyChange = null;
          await _appendAiAgentMessage(
            AiAgentRole.system,
            _ui(
              'لم يتغير شيء في سياسة التنفيذ.',
              'No execution policy was changed.',
            ),
          );
          return true;
        case AiWorkflowApprovalDecision.unknown:
          await _appendAiAgentMessage(
            AiAgentRole.agent,
            _ui(
              'هل توافق على التغيير المقترح؟ أجب بنعم أو لا.',
              'Do you approve the proposed change? Reply yes or no.',
            ),
          );
          return true;
      }
    }
    final change = parseAiPolicyChatInstruction(prompt);
    if (change == null) return false;
    _pendingAiPolicyChange = change;
    await _appendAiAgentMessage(
      AiAgentRole.agent,
      '${_ui('تغيير سياسة مقترح', 'Proposed policy change')}: ${_policyChangeDescription(change)}\n\n${_ui('هل توافق؟ أجب بنعم أو لا.', 'Do you approve? Reply yes or no.')}',
    );
    return true;
  }

  Future<void> _requestAiProposal(
    AiCredentials credentials,
    String prompt,
    String? selectedOutput,
  ) async {
    if (_aiBusy) return;
    if (_aiAgentState.stepLimitReached) {
      _showInfo(
        _ui(
          'وصل الوكيل إلى الحد الأقصى: 8 أوامر معتمدة لهذه المهمة. ابدأ مهمة جديدة لمتابعة العمل.',
          'The agent reached the limit of 8 approved commands for this task. Start a new task to continue.',
        ),
      );
      return;
    }
    setState(() => _aiBusy = true);
    try {
      await _appendAiAgentMessage(AiAgentRole.user, prompt);
      if (await _handleAiPolicyChatInstruction(prompt)) return;
      AiModelInfo? selectedModel;
      for (final model in _aiModels) {
        if (model.id == _selectedAiModelId &&
            model.provider == credentials.provider) {
          selectedModel = model;
          break;
        }
      }
      final aiClient = AiClient();
      AiSkillDiscovery skillDiscovery;
      try {
        final discovered = await aiClient.discoverSkills(
          credentials: credentials,
          userGoal: prompt,
          modelId: selectedModel?.testState == AiModelTestState.failed
              ? null
              : selectedModel?.id,
        );
        skillDiscovery = discovered.isEmpty
            ? AiSkillCatalog.fallbackForGoal(prompt)
            : discovered;
      } catch (_) {
        skillDiscovery = AiSkillCatalog.fallbackForGoal(prompt);
      }
      await _replaceAiAgentState(
        _aiAgentState.withSkillDiscovery(
          skillDiscovery.isEmpty ? null : skillDiscovery,
        ),
      );
      unawaited(_recordActivityDiscovery(skillDiscovery));
      final taskContext = <String>[
        _aiAgentState.providerContext,
        skillDiscovery.mainAgentContext,
      ].join('\n\n');
      final proposal = await aiClient.propose(
        credentials: credentials,
        userRequest: prompt,
        selectedTerminalOutput: selectedOutput,
        taskContext: taskContext,
        modelId: selectedModel?.testState == AiModelTestState.failed
            ? null
            : selectedModel?.id,
      );
      final hasWorkflow =
          proposal.workflow.isNotEmpty ||
          proposal.command != null ||
          proposal.inputRequest != null;
      final workflowId = hasWorkflow
          ? await _createAiWorkflow(
              prompt,
              proposal.workflow,
              waitsForApproval:
                  proposal.command != null && proposal.inputRequest == null,
            )
          : null;
      if (proposal.inputRequest != null && workflowId != null) {
        await _replaceAiAgentState(
          _aiAgentState.requestWorkflowInput(
            workflowId,
            proposal.inputRequest!,
          ),
        );
      } else if (proposal.command == null && workflowId != null) {
        await _replaceAiAgentState(
          _aiAgentState.flagWorkflowAttention(workflowId),
        );
        await _appendAiAgentMessage(
          AiAgentRole.system,
          _ui(
            'لم يقدّم الوكيل أمراً قابلاً للتنفيذ أو دليلاً محلياً؛ تبقى المهمة مفتوحة ولا تُعلَّم مكتملة.',
            'The agent did not provide an executable command or local evidence; the task stays open and is not marked complete.',
          ),
          workflowId: workflowId,
        );
      }
      await _appendAiAgentMessage(
        AiAgentRole.agent,
        _auditedAiReply(proposal),
        proposedCommand: proposal.command,
        workflowId: workflowId,
      );
      await _prepareWorkflowCommandApproval(
        proposal.command,
        workflowId: workflowId,
      );
    } catch (error) {
      final message = _friendlyError(error);
      await _appendAiAgentMessage(AiAgentRole.system, message);
      if (mounted) _showError(message);
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _submitAiWorkflowInput(
    AiCredentials credentials,
    String workflowId,
    String response,
  ) async {
    final trimmed = response.trim();
    if (trimmed.isEmpty || _aiBusy) return;
    final steps = _aiAgentState.itemsForWorkflow(workflowId);
    final goal = steps.isEmpty
        ? _ui('مهمة Workflow حالية', 'Current workflow task')
        : (steps.first.workflowGoal ?? steps.first.title);
    setState(() => _aiBusy = true);
    try {
      final pendingApproval = _aiAgentState.pendingWorkflowApproval(workflowId);
      if (pendingApproval != null) {
        await _appendAiAgentMessage(
          AiAgentRole.user,
          '${_ui('رد الموافقة على الأمر', 'Command approval response')}: $trimmed',
          workflowId: workflowId,
        );
        switch (parseWorkflowApproval(trimmed)) {
          case AiWorkflowApprovalDecision.approved:
            final command = pendingApproval.pendingCommand!;
            final review = reviewAiCommand(
              command,
              blockedPatterns:
                  _aiSettings?.blockedCommandPatterns ?? const <String>[],
            );
            if (review.blocked) {
              await _replaceAiAgentState(
                _aiAgentState.declineWorkflowPendingCommand(workflowId),
              );
              await _appendAiAgentMessage(
                AiAgentRole.system,
                '${_ui('لم يُنفذ الأمر لأنه محظور محلياً', 'Command was not run because it is blocked locally')}: ${review.reason}',
                workflowId: workflowId,
              );
            } else if (review.requiresTypedConfirmation) {
              await _reviewAiProposal(
                AiProposal(
                  reply: _ui(
                    'وافقت على الأمر، لكنه مدمر ويحتاج كتابة EXECUTE أخيراً.',
                    'You approved the command, but it is destructive and still needs EXECUTE.',
                  ),
                  command: command,
                ),
                workflowId: workflowId,
              );
            } else {
              await _replaceAiAgentState(
                _aiAgentState.approveWorkflowPendingCommand(workflowId),
              );
              await _sendApprovedAiCommand(command, workflowId: workflowId);
            }
          case AiWorkflowApprovalDecision.declined:
            await _replaceAiAgentState(
              _aiAgentState.declineWorkflowPendingCommand(workflowId),
            );
            await _appendAiAgentMessage(
              AiAgentRole.system,
              _ui(
                'تم رفض تنفيذ الأمر. يمكن للوكيل اقتراح بديل عند متابعة المهمة.',
                'The command was declined. The agent can propose an alternative when you continue the task.',
              ),
              workflowId: workflowId,
            );
          case AiWorkflowApprovalDecision.unknown:
            await _appendAiAgentMessage(
              AiAgentRole.agent,
              _ui(
                'لم أفهم رد الموافقة. اكتب «نعم» للتنفيذ أو «لا» للرفض.',
                'I did not understand the approval. Reply yes to run it or no to decline.',
              ),
              workflowId: workflowId,
            );
        }
        return;
      }
      await _replaceAiAgentState(
        _aiAgentState.submitWorkflowInput(workflowId, trimmed),
      );
      await _appendAiAgentMessage(
        AiAgentRole.user,
        '${_ui('رد المستخدم للـWorkflow', 'User workflow response')}: $trimmed',
        workflowId: workflowId,
      );
      final proposal = await AiClient().propose(
        credentials: credentials,
        userRequest:
            'Continue the existing workflow "$goal". The user answered the pending workflow question: "$trimmed". Use the current workflow state, continue from the active step, do not recreate the workflow, and return the next safe response.',
        taskContext: _aiAgentState.providerContext,
        preferredLanguage: preferredAiReplyLanguage(goal), // Resumed stage.
      );
      if (proposal.inputRequest != null) {
        await _replaceAiAgentState(
          _aiAgentState.requestWorkflowInput(
            workflowId,
            proposal.inputRequest!,
          ),
        );
      } else if (proposal.command != null) {
        await _replaceAiAgentState(
          _aiAgentState.setCurrentWorkflowStatus(
            workflowId,
            AiAgentWorkStatus.waitingForApproval,
          ),
        );
      } else {
        await _replaceAiAgentState(
          _aiAgentState.flagWorkflowAttention(workflowId),
        );
        await _appendAiAgentMessage(
          AiAgentRole.system,
          _ui(
            'لم يصل أمر طرفية أو دليل محلي بعد ردك؛ تبقى هذه الخطوة بحاجة إلى متابعة.',
            'No terminal command or local evidence followed your answer; this step remains under review.',
          ),
          workflowId: workflowId,
        );
      }
      await _appendAiAgentMessage(
        AiAgentRole.agent,
        proposal.reply,
        proposedCommand: proposal.command,
        workflowId: workflowId,
      );
      await _prepareWorkflowCommandApproval(
        proposal.command,
        workflowId: workflowId,
      );
    } catch (error) {
      final message = _friendlyError(error);
      await _replaceAiAgentState(
        _aiAgentState.flagWorkflowAttention(workflowId),
      );
      await _appendAiAgentMessage(
        AiAgentRole.system,
        message,
        workflowId: workflowId,
      );
      if (mounted) _showError(message);
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _maybeAutomaticallyContinueWorkflow(
    AiCredentials credentials,
    String workflowId,
  ) async {
    if (_aiBusy ||
        _aiSettings?.workflowAdvanceMode != AiWorkflowAdvanceMode.automatic) {
      return;
    }
    final items = _aiAgentState.itemsForWorkflow(workflowId);
    if (!shouldAutomaticallyAdvanceWorkflow(
      automaticMode: true,
      agentBusy: false,
      workItems: items,
    )) {
      return;
    }
    await _continueAiWorkflow(credentials, workflowId);
  }

  Future<void> _continueAiWorkflow(
    AiCredentials credentials,
    String workflowId,
  ) async {
    if (_aiBusy) return;
    final before = _aiAgentState.itemsForWorkflow(workflowId);
    final goal = before.isEmpty
        ? _ui('مهمة Workflow حالية', 'Current workflow task')
        : (before.first.workflowGoal ?? before.first.title);
    final next = before
        .where((item) => item.status == AiAgentWorkStatus.queued)
        .toList();
    if (next.isEmpty) return;
    setState(() => _aiBusy = true);
    try {
      await _replaceAiAgentState(
        _aiAgentState.beginNextQueuedWorkflowStep(workflowId),
      );
      final active = _aiAgentState
          .itemsForWorkflow(workflowId)
          .where((item) => item.status == AiAgentWorkStatus.inProgress)
          .toList();
      final step = active.isEmpty ? next.first : active.first;
      await _appendAiAgentMessage(
        AiAgentRole.system,
        '${_ui('بدأت مرحلة Workflow', 'Workflow stage started')}: ${step.title}',
        workflowId: workflowId,
      );
      final proposal = await AiClient().propose(
        credentials: credentials,
        userRequest:
            'Continue the existing workflow "$goal" at stage ${step.order + 1}: "${step.title}". Work only on this active stage. Do not recreate the workflow. If a terminal action is required, return one command; if a fact or decision is missing, ask one focused inputRequest; otherwise report the completed result concisely.',
        taskContext: _aiAgentState.providerContext,
        preferredLanguage: preferredAiReplyLanguage(goal),
      );
      if (proposal.inputRequest != null) {
        await _replaceAiAgentState(
          _aiAgentState.requestWorkflowInput(
            workflowId,
            proposal.inputRequest!,
          ),
        );
      } else if (proposal.command != null) {
        await _replaceAiAgentState(
          _aiAgentState.setCurrentWorkflowStatus(
            workflowId,
            AiAgentWorkStatus.waitingForApproval,
          ),
        );
      } else {
        await _replaceAiAgentState(
          _aiAgentState.flagWorkflowAttention(workflowId),
        );
        await _appendAiAgentMessage(
          AiAgentRole.system,
          _ui(
            'لم تقدم المرحلة أمراً أو دليلاً محلياً؛ تبقى المهمة مفتوحة ولا تُعلَّم مكتملة.',
            'This stage did not provide a command or local evidence; the task stays open and is not marked complete.',
          ),
          workflowId: workflowId,
        );
      }
      await _appendAiAgentMessage(
        AiAgentRole.agent,
        proposal.reply,
        proposedCommand: proposal.command,
        workflowId: workflowId,
      );
      await _prepareWorkflowCommandApproval(
        proposal.command,
        workflowId: workflowId,
      );
    } catch (error) {
      final message = _friendlyError(error);
      await _replaceAiAgentState(
        _aiAgentState.flagWorkflowAttention(workflowId),
      );
      await _appendAiAgentMessage(
        AiAgentRole.system,
        message,
        workflowId: workflowId,
      );
      if (mounted) _showError(message);
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _sendApprovedAiCommand(
    String command, {
    String? workflowId,
    bool automaticSafeMode = false,
  }) async {
    if (workflowId != null) {
      await _replaceAiAgentState(_aiAgentState.beginWorkflowStep(workflowId));
    }
    _beginAgentObservation(command, workflowId: workflowId);
    await _recordApprovedTerminalCommand(command);
    session.write('$command\n');
    await _appendAiAgentMessage(
      AiAgentRole.system,
      'Approved command sent to terminal: $command${automaticSafeMode ? ' (safe execution mode)' : ''}',
      workflowId: workflowId,
    );
    if (mounted) {
      _showInfo(
        automaticSafeMode
            ? _ui(
                'أُرسل أمر مصنف آمناً وفق وضع التنفيذ السريع؛ ستظهر نتيجته في Workflow.',
                'A locally normal-risk command was sent in safe execution mode; its result will appear in the workflow.',
              )
            : _ui(
                'تم إرسال الأمر الذي وافقت عليه إلى الطرفية.',
                'Your approved command was sent to the terminal.',
              ),
      );
    }
  }

  Future<bool> _trySafeAutomaticExecution(
    String? command, {
    String? workflowId,
  }) async {
    if (command == null ||
        _aiSettings?.approvalMode != AiApprovalMode.executeSafeAutomatically) {
      return false;
    }
    final review = reviewAiCommand(
      command,
      blockedPatterns: _aiSettings?.blockedCommandPatterns ?? const <String>[],
    );
    if (review.blocked || review.risk != AiCommandRisk.normal) return false;
    await _sendApprovedAiCommand(
      command,
      workflowId: workflowId,
      automaticSafeMode: true,
    );
    return true;
  }

  Future<void> _prepareWorkflowCommandApproval(
    String? command, {
    required String? workflowId,
  }) async {
    if (command == null || workflowId == null) return;
    final review = reviewAiCommand(
      command,
      blockedPatterns: _aiSettings?.blockedCommandPatterns ?? const <String>[],
    );
    if (review.blocked) {
      await _replaceAiAgentState(
        _aiAgentState.flagWorkflowAttention(workflowId),
      );
      await _appendAiAgentMessage(
        AiAgentRole.system,
        '${_ui('الأمر محظور محلياً', 'Command blocked locally')}: ${review.reason}',
        workflowId: workflowId,
      );
      return;
    }
    if (await _trySafeAutomaticExecution(command, workflowId: workflowId)) {
      return;
    }
    await _replaceAiAgentState(
      _aiAgentState.requestWorkflowApproval(
        workflowId,
        command,
        _ui(
          'هل توافق على تنفيذ الأمر المقترح؟ اكتب «نعم» أو «لا».',
          'Do you approve running the proposed command? Reply yes or no.',
        ),
      ),
    );
    await _appendAiAgentMessage(
      AiAgentRole.system,
      _ui(
        'الوكيل ينتظر موافقتك على الأمر. أجب بنعم أو لا من بطاقة Workflow.',
        'The agent is waiting for your approval. Reply yes or no from the workflow card.',
      ),
      workflowId: workflowId,
    );
  }

  Future<void> _reviewAiProposal(
    AiProposal proposal, {
    String? workflowId,
  }) async {
    final command = proposal.command;
    final review = command == null
        ? null
        : reviewAiCommand(
            command,
            blockedPatterns:
                _aiSettings?.blockedCommandPatterns ?? const <String>[],
          );
    final blocked = review?.blocked == true;
    final needsTypedConfirmation =
        review?.requiresTypedConfirmation == true ||
        _aiSettings?.approvalMode == AiApprovalMode.typedForEveryCommand;
    final confirmationController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final typedConfirmationValid =
              !needsTypedConfirmation ||
              confirmationController.text.trim() == 'EXECUTE';
          return AlertDialog(
            backgroundColor: const Color(0xFF111820),
            title: Text(_ui('اقتراح AI', 'AI proposal')),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SelectableText(
                    proposal.reply,
                    style: const TextStyle(color: Color(0xFFDCE7F0)),
                  ),
                  if (command != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      _ui('الأمر المقترح', 'Proposed command'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9EE9FF),
                      ),
                    ),
                    const SizedBox(height: 5),
                    SelectableText(
                      command,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Color(0xFF7EE787),
                      ),
                    ),
                    if (review?.requiresWarning == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          '${_ui('تحذير', 'Warning')}: ${review!.reason}',
                          style: TextStyle(
                            color: review.risk == AiCommandRisk.destructive
                                ? const Color(0xFFFF7B72)
                                : const Color(0xFFFFD46A),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    if (needsTypedConfirmation)
                      TextField(
                        controller: confirmationController,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          labelText: _ui(
                            'اكتب EXECUTE للتأكيد',
                            'Type EXECUTE to confirm',
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_ui('إغلاق', 'Close')),
              ),
              if (command != null && !blocked)
                FilledButton(
                  onPressed: typedConfirmationValid
                      ? () async {
                          await _sendApprovedAiCommand(
                            command,
                            workflowId: workflowId,
                          );
                          if (context.mounted) Navigator.pop(context);
                        }
                      : null,
                  child: Text(
                    _ui('تنفيذ بعد الموافقة', 'Execute after approval'),
                  ),
                ),
            ],
          );
        },
      ),
    );
    confirmationController.dispose();
  }

  Future<void> _reviewRecordedTerminalCommand(String command) async {
    await _reviewAiProposal(
      AiProposal(
        reply: _ui(
          'هذا أمر محفوظ محلياً من جلسة سابقة. راجع أثره والموافقة المطلوبة قبل إرساله إلى الطرفية الحالية.',
          'This command is saved locally from a previous session. Review its effect and required approval before sending it to the current terminal.',
        ),
        command: command,
      ),
    );
  }

  void _selectAllTerminalText() {
    terminalController.setSelection(
      terminal.buffer.createAnchor(
        0,
        terminal.buffer.height - terminal.viewHeight,
      ),
      terminal.buffer.createAnchor(
        terminal.viewWidth,
        terminal.buffer.height - 1,
      ),
    );
  }

  Future<void> _installArch() async {
    if (!Platform.isAndroid || _setupRunning) return;
    final status = await ArchRuntime.status();
    if (!mounted) return;
    setState(() => runtimeStatus = status);
    final action = decideArchSetupAction(
      notificationsGranted: status['notificationGranted'] == true,
      batteryOptimizationIgnored: status['batteryOptimizationIgnored'] == true,
      publicStorageGranted: status['publicStorageGranted'] == true,
      archInstalled: status['installed'] == true,
      prootAvailable: status['prootAvailable'] == true,
      publicArchivePresent: status['rootfsPublicArchivePresent'] == true,
    );
    if (action == ArchSetupAction.openPermissionGate) {
      setState(() {
        commandsOpen = true;
        _archPermissionGateActive = true;
        statusText = _ui(
          'بوابة إعداد Arch: فعّل الإشعارات والبطارية والوصول للتخزين العام أولاً؛ لن يبدأ التنزيل قبل اكتمالها.',
          'Arch setup gate: enable notifications, battery exemption, and shared storage access first. Download will not start before they are all granted.',
        );
      });
      unawaited(_continueArchPermissionGate(status));
      return;
    }
    // A fresh user request to prepare Arch is the explicit opt-in required to
    // restart a session that was deliberately ended from the notification.
    _manualSessionEndRequested = false;
    if (action == ArchSetupAction.useInstalledRootfs) {
      setState(() {
        commandsOpen = false;
        statusText = _ui(
          'تم العثور على RootFS المثبت محلياً. سيبدأ Arch تلقائياً الآن دون تنزيل.',
          'An installed RootFS was found. Arch will start automatically without downloading.',
        );
      });
      _queueAutomaticSessionStart();
      return;
    }
    setState(() {
      commandsOpen = false;
      statusText = action == ArchSetupAction.reusePublicArchive
          ? _ui(
              'تم العثور على ملف Arch محفوظ في التخزين العام. سيتحقق التطبيق منه ثم يستخرجه دون تنزيل جديد.',
              'A saved Arch file was found in shared storage. It will be verified and extracted without a new download.',
            )
          : _ui(
              'لم يُعثر على ملف Arch محفوظ في التخزين العام. سيبدأ التنزيل ثم التحقق والاستخراج في الخلفية.',
              'No saved Arch file was found in shared storage. Download, verification, and extraction will start in the background.',
            );
    });
    try {
      final result = await ArchRuntime.installArch();
      if (!mounted) return;
      setState(() => runtimeStatus = result);
      unawaited(_refreshStatus());
    } catch (error) {
      if (!mounted) return;
      final message = _friendlyError(error);
      setState(() => statusText = message);
      _showError(message);
    }
  }

  Future<void> _cancelArchDownload() async {
    if (!Platform.isAndroid || !_canCancelArchDownload) return;
    try {
      final result = await ArchRuntime.cancelArchDownload();
      if (!mounted) return;
      setState(() {
        runtimeStatus = <String, Object?>{...runtimeStatus, ...result};
        statusText = _ui(
          'طُلب إيقاف التنزيل. سيُحفظ الجزء المكتمل ويُستأنف عند اختيار تنزيل وإعداد Arch مرة أخرى.',
          'Stopping the download was requested. The completed part is kept and resumes when you select Download and set up Arch again.',
        );
      });
    } catch (error) {
      if (!mounted) return;
      _showError(_friendlyError(error));
    }
  }

  Future<bool> _startSession() async {
    if (session.isRunning || busy || _setupRunning) return false;
    setState(() {
      busy = true;
      commandsOpen = false;
      statusText = Platform.isAndroid
          ? 'جارٍ تشغيل Arch عبر PRoot محلياً…'
          : 'جارٍ تشغيل shell محلي…';
    });
    try {
      if (Platform.isAndroid) {
        final status = await ArchRuntime.status();
        if (status['supported'] != true) {
          throw StateError('Arch/PRoot غير متاح لمعمارية الجهاز الحالية.');
        }
        if (status['setupRunning'] == true) {
          throw StateError('اكتمل إعداد Arch أولاً قبل بدء الجلسة.');
        }
        if (status['installed'] != true || status['prootAvailable'] != true) {
          throw StateError('نزّل وأعِدّ Arch أولاً من لوحة التحكم.');
        }
        final command = await ArchRuntime.prepareArchCommand();
        final rootfsPath = command['rootfsPath']!;
        final prootTmpPath = command['prootTmpPath']!;
        final deviceStorageGranted = command['deviceStorageGranted'] == 'true';
        await session.start(
          executable: command['prootPath']!,
          arguments: buildArchProotArguments(
            rootfsPath: rootfsPath,
            prootTmpPath: prootTmpPath,
            storagePath: command['storagePath']!,
            abi: command['abi']!,
            bindDeviceStorage: deviceStorageGranted,
          ),
          environment: <String, String>{
            'TERM': 'xterm-256color',
            'PROOT_TMP_DIR': prootTmpPath,
          },
          rows: terminal.viewHeight,
          columns: terminal.viewWidth,
        );
        final sessionStatus = await ArchRuntime.startTerminalSessionService();
        if (mounted) {
          setState(
            () => runtimeStatus = <String, Object?>{
              ...runtimeStatus,
              ...sessionStatus,
            },
          );
        }
      } else {
        await session.start(
          executable: ArchRuntime.localShell,
          arguments: ArchRuntime.localShellArguments,
          environment: const <String, String>{'TERM': 'xterm-256color'},
          rows: terminal.viewHeight,
          columns: terminal.viewWidth,
        );
      }
      if (!mounted) return false;
      setState(
        () => statusText = Platform.isAndroid
            ? 'Arch يعمل محلياً عبر PRoot'
            : 'shell يعمل محلياً',
      );
      terminalFocusNode.requestFocus();
      unawaited(_recordTerminalSessionStart());
      _scanAiEnvironment();
      return true;
    } catch (error) {
      if (!mounted) return false;
      final message = _friendlyError(error);
      setState(() => statusText = message);
      _showError(message);
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _reportArm32LaunchExit(int code) async {
    try {
      final diagnostics = await ArchRuntime.archLaunchDiagnostics();
      if (diagnostics['arm32'] != true || !mounted) return;
      final detail = arm32LaunchDiagnosisText(
        diagnostics,
        arabicUi: _isArabicUi,
      );
      setState(() => statusText = detail);
      terminal.write('\r\n\x1b[33m[$detail; exit=$code]\x1b[0m\r\n');
    } catch (_) {
      // The PTY exit status remains visible when optional diagnostics fail.
    }
  }

  void _queueAutomaticSessionStart() {
    if (!Platform.isAndroid ||
        !canQueueAutomaticStart(
          manualEndRequested: _manualSessionEndRequested,
        ) ||
        session.isRunning ||
        busy ||
        _setupRunning ||
        !_permissionsReady ||
        !_archInstalled ||
        !_prootAvailable) {
      return;
    }
    if (!_automaticStartQueue.tryReserve()) return;
    unawaited(
      _startSession().then((started) {
        if (shouldReleaseAutomaticStartReservation(
          startSucceeded: started,
          sessionRunning: session.isRunning,
        )) {
          _automaticStartQueue.release();
        }
      }),
    );
  }

  Future<void> _requestBatteryExemption() async {
    await ArchRuntime.requestBatteryOptimizationExemption();
    if (!mounted) return;
    _showInfo(
      _ui(
        'افتح شاشة النظام واسمح للتطبيق بالعمل دون تحسين البطارية.',
        'Allow unrestricted battery use in the system screen.',
      ),
    );
  }

  Future<void> _setBackgroundProtection(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      final status = await ArchRuntime.setTerminalBackgroundProtection(enabled);
      if (!mounted) return;
      setState(() {
        runtimeStatus = <String, Object?>{...runtimeStatus, ...status};
        statusText = enabled
            ? _ui(
                'وضع حماية الخلفية مفعّل. ستُستخدم الخدمة الأمامية وقفل CPU أثناء جلسة Arch.',
                'Background protection is enabled. The foreground service and CPU wake lock will be used during an Arch session.',
              )
            : _ui(
                'وضع حماية الخلفية متوقف. ستستمر الجلسة الحالية ما دامت الخدمة الأمامية تعمل.',
                'Background protection is disabled. The current session remains available while its foreground service runs.',
              );
      });
      if (!enabled) {
        _showInfo(
          _ui(
            'أُوقف وضع الحماية. لا يقتل التطبيق الجلسة الحالية.',
            'Protection was disabled. The current session was not terminated.',
          ),
        );
        return;
      }
      if (runtimeStatus['notificationGranted'] != true) {
        await _requestNotificationPermission();
      }
      await _refreshStatus();
      if (!mounted) return;
      if (runtimeStatus['batteryOptimizationIgnored'] != true) {
        await _requestBatteryExemption();
      } else {
        _showInfo(
          _ui(
            'الحماية مفعّلة: إشعار مستمر، وقفل CPU للجلسة، واستثناء البطارية جاهز. لا يستطيع أي تطبيق ضمان عدم إيقاف Android أو نظام الشركة المصنعة للعملية نهائياً.',
            'Protection is enabled: ongoing notification, a session CPU wake lock, and battery exemption are ready. No app can guarantee that Android or a device vendor will never reclaim its process.',
          ),
        );
      }
    } catch (error) {
      if (mounted) _showError(_friendlyError(error));
    }
  }

  Future<void> _requestNotificationPermission() async {
    final status = await ArchRuntime.requestNotificationPermission();
    if (!mounted) return;
    setState(() {
      runtimeStatus = <String, Object?>{...runtimeStatus, ...status};
    });
    unawaited(_refreshStatus());
  }

  Future<void> _continueArchPermissionGate(Map<String, Object?> status) async {
    if (!_archPermissionGateActive || _permissionRequestInFlight || !mounted) {
      return;
    }
    final step = nextArchPermissionStep(
      notificationsGranted: status['notificationGranted'] == true,
      batteryOptimizationIgnored: status['batteryOptimizationIgnored'] == true,
      publicStorageGranted: status['publicStorageGranted'] == true,
    );
    if (step == ArchPermissionStep.ready) {
      setState(() {
        _archPermissionGateActive = false;
        commandsOpen = true;
        statusText = status['rootfsPublicArchivePresent'] == true
            ? _ui(
                'اكتملت الصلاحيات. تم العثور على ملف Arch محفوظ وسيجري التحقق منه ثم استخراجه دون تنزيل جديد عند الضغط على الزر.',
                'Permissions are complete. A saved Arch file was found and will be verified then extracted without a new download when you press the button.',
              )
            : _ui(
                'اكتملت الصلاحيات. لم يُعثر على ملف Arch محفوظ؛ سيبدأ التنزيل ثم التحقق والاستخراج عند الضغط على الزر.',
                'Permissions are complete. No saved Arch file was found; download, verification, and extraction will start when you press the button.',
              );
      });
      return;
    }
    _permissionRequestInFlight = true;
    try {
      switch (step) {
        case ArchPermissionStep.notification:
          setState(
            () => statusText = _ui(
              'الخطوة 1 من 3: افتح إذن الإشعارات للتقدم في إعداد Arch.',
              'Step 1 of 3: allow notifications to continue Arch setup.',
            ),
          );
          await _requestNotificationPermission();
        case ArchPermissionStep.battery:
          setState(
            () => statusText = _ui(
              'الخطوة 2 من 3: اسمح للتطبيق بالعمل دون تحسين البطارية.',
              'Step 2 of 3: allow the app to run without battery optimization.',
            ),
          );
          await _requestBatteryExemption();
        case ArchPermissionStep.sharedStorage:
          setState(
            () => statusText = _ui(
              'الخطوة 3 من 3: اسمح بالوصول إلى التخزين العام لفحص ملف Arch المحفوظ.',
              'Step 3 of 3: allow shared storage access to check for a saved Arch file.',
            ),
          );
          await _openRootfsLocation();
        case ArchPermissionStep.ready:
          break;
      }
    } finally {
      if (mounted && step == ArchPermissionStep.notification) {
        _permissionRequestInFlight = false;
        unawaited(_refreshStatus());
      }
    }
  }

  Future<void> _openRootfsLocation() async {
    try {
      final status = await ArchRuntime.status();
      if (status['publicStorageGranted'] != true) {
        final details = await ArchRuntime.requestAllFilesAccess();
        if (!mounted) return;
        setState(
          () => runtimeStatus = <String, Object?>{...runtimeStatus, ...details},
        );
        _showInfo(
          _ui(
            'فعّل إذن الوصول للتخزين العام من شاشة النظام، ثم ارجع للتطبيق؛ سيُفحص مجلد Arch المحفوظ تلقائياً.',
            'Enable shared storage access in system settings, then return to the app. The saved Arch folder will be checked automatically.',
          ),
        );
        return;
      }
      final details = await ArchRuntime.openRootfsLocation();
      if (!mounted) return;
      setState(
        () => runtimeStatus = <String, Object?>{...runtimeStatus, ...details},
      );
      final path = details['rootfsStoragePath']?.toString() ?? '';
      _showInfo(
        details['openedStoragePermission'] == true
            ? 'امنح إذن التخزين أولاً، ثم اضغط «وصول الملفات» مجدداً.'
            : 'مسار ملفات Arch: $path',
      );
    } catch (error) {
      _showError(_friendlyError(error));
    }
  }

  Future<void> _openDeviceFileAccess() async {
    try {
      final status = await ArchRuntime.status();
      if (status['deviceStorageGranted'] != true) {
        final details = await ArchRuntime.requestAllFilesAccess();
        if (!mounted) return;
        setState(
          () => runtimeStatus = <String, Object?>{...runtimeStatus, ...details},
        );
        _showInfo(
          _ui(
            'امنح إذن ملفات الجهاز من شاشة النظام، ثم ارجع وافتح جلسة Arch جديدة لربطها داخل /sdcard.',
            'Grant device-file access in system settings, then return and start a new Arch session to bind it at /sdcard.',
          ),
        );
        return;
      }
      if (!mounted) return;
      setState(
        () => runtimeStatus = <String, Object?>{...runtimeStatus, ...status},
      );
      _showInfo(
        _ui(
          'ملفات الجهاز متاحة في Arch عبر /sdcard. ابدأ جلسة جديدة إذا كانت الجلسة الحالية بدأت قبل منح الإذن.',
          'Device files are available in Arch at /sdcard. Start a new session if the current session began before permission was granted.',
        ),
      );
    } catch (error) {
      _showError(_friendlyError(error));
    }
  }

  Future<void> _openRootfsStorageSettings() async {
    try {
      final details = await ArchRuntime.rootfsStorageSettings();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF111820),
        builder: (context) => RootfsStorageSheet(
          initial: details,
          arabicUi: _isArabicUi,
          onSelect: ArchRuntime.setRootfsStorageMode,
          onRequestPermission: ArchRuntime.requestAllFilesAccess,
          onOpenLocation: ArchRuntime.openRootfsLocation,
        ),
      );
      await _refreshStatus();
    } catch (error) {
      _showError(_friendlyError(error));
    }
  }

  void _clearTerminal() {
    terminal.write('\x1b[2J\x1b[H');
    setState(_inlineImages.clear);
  }

  Future<void> _openDeviceFilePreview(String path) async {
    if (_deviceFilePreviewLoading) return;
    try {
      setState(() => _deviceFilePreviewLoading = true);
      final preview = await ArchRuntime.previewDeviceFile(path);
      if (!mounted) return;
      setState(() {
        _deviceFileContentPreview = preview;
        statusText = _ui(
          'فُتح محتوى الملف محلياً داخل التطبيق ولم يُرسل إلى مزود AI.',
          'The file content was opened locally in the app and was not sent to the AI provider.',
        );
      });
    } catch (error) {
      _showError(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _deviceFilePreviewLoading = false);
    }
  }

  Future<void> _copyDeviceFilePreviewText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      _showInfo(
        _ui(
          'تم نسخ نص المعاينة إلى الحافظة محلياً.',
          'The preview text was copied to the local clipboard.',
        ),
      );
    }
  }

  String _terminalLogText() =>
      withoutInteractivePrompts(terminal.buffer.getText());

  Future<void> _shareTerminalLog() async {
    final text = _terminalLogText();
    if (text.trim().isEmpty) {
      _showInfo(
        _ui(
          'لا يوجد سجل طرفية لتصديره بعد.',
          'There is no terminal log to export yet.',
        ),
      );
      return;
    }
    try {
      await ArchRuntime.shareTerminalLog(text);
    } catch (error) {
      if (mounted) _showError(_friendlyError(error));
    }
  }

  Future<void> _openStartupDiagnostics() async {
    try {
      await ArchRuntime.openStartupDiagnostics();
    } catch (error) {
      if (!mounted) return;
      setState(
        () => statusText = _ui(
          'تعذر فتح سجل تشخيص الإقلاع: $error',
          'Could not open startup diagnostics: $error',
        ),
      );
    }
  }

  void _searchTerminalLog() {
    final text = _terminalLogText();
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final query = controller.text;
          final count = query.isEmpty
              ? 0
              : RegExp(
                  RegExp.escape(query),
                  caseSensitive: false,
                ).allMatches(text).length;
          return AlertDialog(
            backgroundColor: const Color(0xFF111820),
            title: Text(_ui('بحث في سجل الطرفية', 'Search terminal log')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: controller,
                  autofocus: true,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    hintText: _ui('اكتب النص للبحث', 'Type text to search'),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _ui('النتائج: $count', 'Matches: $count'),
                  style: const TextStyle(color: Color(0xFF9EE9FF)),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_ui('إغلاق', 'Close')),
              ),
            ],
          );
        },
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _startNewTerminalSession() async {
    if (busy || _setupRunning) return;
    await _flushDeepTranscript();
    if (session.isRunning) {
      _manualSessionEndRequested = false;
      await session.stop();
      if (Platform.isAndroid) await ArchRuntime.stopTerminalSessionService();
    }
    _clearTerminal();
    if (mounted) {
      setState(
        () => statusText = _ui(
          'جارٍ بدء جلسة طرفية جديدة؛ سجل الجلسة العميقة محفوظ.',
          'Starting a new terminal session; the deep-session transcript is preserved.',
        ),
      );
    }
    await _startSession();
  }

  void _handleTerminalPointerDown(PointerDownEvent _) {
    if (!isMobile) {
      terminalFocusNode.requestFocus();
      return;
    }
    if (_keyboardTapGate.register(DateTime.now())) {
      setState(() {
        statusText = _ui(
          'لوحة المفاتيح جاهزة للإدخال داخل الطرفية.',
          'Keyboard is ready for terminal input.',
        );
      });
      terminalFocusNode.requestFocus();
      terminalViewKey.currentState?.requestKeyboard();
    }
  }

  String _friendlyError(Object error) {
    if (error is PlatformException) {
      return error.message?.split('\n').first.trim() ?? error.code;
    }
    final first = error.toString().split('\n').first.trim();
    return first.length > 180 ? '${first.substring(0, 177)}…' : first;
  }

  void _showError(String message) {
    unawaited(_playSound(AppSoundEvent.error));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFB42318),
        content: Text(message),
      ),
    );
  }

  void _showInfo(String message) {
    unawaited(_playSound(AppSoundEvent.success));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final progress = SetupProgressViewModel.fromStatus(runtimeStatus);
    final panelWidth = MediaQuery.sizeOf(context).width < 540
        ? MediaQuery.sizeOf(context).width
        : 360.0;
    return Directionality(
      textDirection: _isArabicUi ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: <Widget>[
              Column(
                children: <Widget>[
                  _TerminalHeader(
                    running: session.isRunning,
                    arabicUi: _isArabicUi,
                    onClear: _clearTerminal,
                    onOpenActivityHistory: _openLocalActivityHistory,
                    onOpenSettings: () => setState(() => commandsOpen = true),
                  ),
                  Expanded(
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: _handleTerminalPointerDown,
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: const Color(0xFF020405),
                          border: Border.all(color: const Color(0xFF24303B)),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(color: Color(0x66000000), blurRadius: 18),
                          ],
                        ),
                        child: TerminalImageLayer(
                          image: _inlineImages.isEmpty
                              ? null
                              : _inlineImages.last,
                          onClose: _inlineImages.isEmpty
                              ? null
                              : () => setState(_inlineImages.removeLast),
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: TerminalView(
                              terminal,
                              key: terminalViewKey,
                              controller: terminalController,
                              focusNode: terminalFocusNode,
                              autofocus: !isMobile,
                              hardwareKeyboardOnly: !isMobile,
                              requestKeyboardOnTap: !isMobile,
                              deleteDetection: isMobile,
                              cursorType: TerminalCursorType.compactBlock,
                              theme: _terminalTheme,
                              textStyle: TerminalStyle(
                                fontSize: terminalFontSize,
                                height: 1.22,
                                fontFamily: 'monospace',
                                fontFamilyFallback: const <String>[
                                  'Noto Sans Arabic',
                                  'Noto Sans Mono CJK SC',
                                  'Segoe UI Emoji',
                                  'Noto Color Emoji',
                                  'sans-serif',
                                ],
                              ),
                              padding: const EdgeInsets.all(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_deviceFileContentPreview != null)
                Positioned(
                  top: hasSelection ? 106 : 54,
                  left: 16,
                  right: 16,
                  child: DeviceFileContentPreviewCard(
                    preview: _deviceFileContentPreview!,
                    arabicUi: _isArabicUi,
                    onClose: () =>
                        setState(() => _deviceFileContentPreview = null),
                    onCopyText: _copyDeviceFilePreviewText,
                  ),
                ),
              if (_deviceFileContentPreview == null &&
                  _deviceFileSearchPreview != null)
                Positioned(
                  top: hasSelection ? 106 : 54,
                  left: 16,
                  right: 16,
                  child: DeviceFileSearchPreviewCard(
                    preview: _deviceFileSearchPreview!,
                    arabicUi: _isArabicUi,
                    loading: _deviceFilePreviewLoading,
                    onClose: () =>
                        setState(() => _deviceFileSearchPreview = null),
                    onOpen: _openDeviceFilePreview,
                  ),
                ),
              if (commandsOpen)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => setState(() => commandsOpen = false),
                    child: Container(color: Colors.black54),
                  ),
                ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: commandsOpen ? 0 : -panelWidth - 12,
                top: 0,
                bottom: 0,
                width: panelWidth,
                child: _CommandPanel(
                  busy: busy,
                  setupRunning: _setupRunning,
                  isAndroid: Platform.isAndroid,
                  archInstalled: _archInstalled,
                  prootAvailable: _prootAvailable,
                  pacmanSandboxDisabled: _pacmanSandboxDisabled,
                  rootfsDnsConfigured:
                      runtimeStatus['rootfsDnsConfigured'] == true,
                  batteryIgnored:
                      runtimeStatus['batteryOptimizationIgnored'] == true,
                  backgroundProtectionEnabled:
                      runtimeStatus['terminalBackgroundProtectionEnabled'] ==
                      true,
                  notificationsGranted:
                      runtimeStatus['notificationGranted'] == true,
                  persistentStorage:
                      runtimeStatus['rootfsStoragePersistent'] == true,
                  storageReady: _storageReady,
                  publicStorageGranted: _publicStorageGranted,
                  deviceStorageGranted:
                      runtimeStatus['deviceStorageGranted'] == true,
                  publicArchivePresent: _publicArchivePresent,
                  permissionsReady: _permissionsReady,
                  arabicUi: _isArabicUi,
                  terminalFontSize: terminalFontSize,
                  soundEnabled: soundEnabled,
                  soundVolume: soundVolume,
                  statusText: statusText,
                  progress: progress,
                  aiSettings: _aiSettings,
                  onClose: () => setState(() => commandsOpen = false),
                  onInstallArch: _installArch,
                  onCancelDownload: () => unawaited(_cancelArchDownload()),
                  onSearchLog: _searchTerminalLog,
                  onExportLog: () => unawaited(_shareTerminalLog()),
                  onStartupDiagnostics: () =>
                      unawaited(_openStartupDiagnostics()),
                  onNewSession: () => unawaited(_startNewTerminalSession()),
                  onEditSessionName: () => unawaited(_editSessionName()),
                  onAiSettings: () => unawaited(_openAiSettings()),
                  onAiAsk: () => unawaited(_openAiAssistant()),
                  onStorage: _openRootfsLocation,
                  onDeviceFiles: _openDeviceFileAccess,
                  onStorageSettings: _openRootfsStorageSettings,
                  onBattery: _requestBatteryExemption,
                  onBackgroundProtection: () => unawaited(
                    _setBackgroundProtection(
                      runtimeStatus['terminalBackgroundProtectionEnabled'] !=
                          true,
                    ),
                  ),
                  onNotifications: _requestNotificationPermission,
                  onFontSize: _setTerminalFontSize,
                  onSoundEnabled: _setSoundEnabled,
                  onSoundVolume: _setSoundVolume,
                  onSoundPreview: () =>
                      unawaited(_playSound(AppSoundEvent.tap)),
                  onLanguage: _setInterfaceLanguage,
                ),
              ),
              if (hasSelection)
                Positioned(
                  top: 54,
                  left: 16,
                  right: 16,
                  child: _SelectionToolbar(
                    arabicUi: _isArabicUi,
                    onCopy: _copySelection,
                    onSelectAll: _selectAllTerminalText,
                    onDismiss: terminalController.clearSelection,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static const _terminalTheme = TerminalTheme(
    cursor: Color(0xFF62D5FF),
    selection: Color(0x6643A8CC),
    foreground: Color(0xFFDCE7F0),
    background: Color(0xFF020405),
    black: Color(0xFF101820),
    red: Color(0xFFFF7B72),
    green: Color(0xFF7EE787),
    yellow: Color(0xFFE3B341),
    blue: Color(0xFF58A6FF),
    magenta: Color(0xFFD2A8FF),
    cyan: Color(0xFF62D5FF),
    white: Color(0xFFE6EDF3),
    brightBlack: Color(0xFF7D8590),
    brightRed: Color(0xFFFFA198),
    brightGreen: Color(0xFF8EF0A5),
    brightYellow: Color(0xFFFFD46A),
    brightBlue: Color(0xFF79C0FF),
    brightMagenta: Color(0xFFE2C5FF),
    brightCyan: Color(0xFF9EE9FF),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Color(0xFF9E6A03),
    searchHitBackgroundCurrent: Color(0xFFD29922),
    searchHitForeground: Color(0xFFFFFFFF),
  );
}

class DeviceFileSearchPreviewCard extends StatelessWidget {
  const DeviceFileSearchPreviewCard({
    super.key,
    required this.preview,
    required this.arabicUi,
    required this.loading,
    required this.onClose,
    required this.onOpen,
  });

  final DeviceFileSearchPreview preview;
  final bool arabicUi;
  final bool loading;
  final VoidCallback onClose;
  final ValueChanged<String> onOpen;

  String _t(String arabic, String english) => arabicUi ? arabic : english;

  @override
  Widget build(BuildContext context) {
    final title = preview.isEmpty
        ? _t(
            'لم يُعثر على ملفات ضمن نافذة البحث',
            'No files found in the search window',
          )
        : _t(
            'نتائج بحث ملفات الجهاز (${preview.paths.length})',
            'Device file search results (${preview.paths.length})',
          );
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 286),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
        decoration: BoxDecoration(
          color: const Color(0xFF101923).withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF62D5FF)),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Color(0x99000000), blurRadius: 16),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.folder_copy_outlined,
                  color: Color(0xFF62D5FF),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFFE6EDF3),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _t('إغلاق المعاينة', 'Close preview'),
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 19),
                ),
              ],
            ),
            Text(
              _t(
                'هذه النتائج محلية ولم تُرسل إلى مزود AI. اضغط أي نتيجة لمعاينة محتواها محلياً.',
                'These results are local and were not sent to the AI provider. Tap one to preview its content locally.',
              ),
              style: const TextStyle(fontSize: 11, color: Color(0xFF9EABB8)),
            ),
            if (preview.paths.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: preview.paths.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 8, color: Color(0xFF263341)),
                  itemBuilder: (context, index) {
                    final path = preview.paths[index];
                    return InkWell(
                      onTap: loading ? null : () => onOpen(path),
                      borderRadius: BorderRadius.circular(5),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 5,
                        ),
                        child: Row(
                          children: <Widget>[
                            const Icon(
                              Icons.insert_drive_file_outlined,
                              size: 16,
                              color: Color(0xFF7EE787),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                path,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(
                                  color: Color(0xFFDCE7F0),
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            loading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.visibility_outlined,
                                    size: 16,
                                    color: Color(0xFF62D5FF),
                                  ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (preview.truncated)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _t(
                    'اقتُصرت المعاينة على أول 24 نتيجة محلية.',
                    'The preview is limited to the first 24 local results.',
                  ),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFFFFB454),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class DeviceFileContentPreviewCard extends StatelessWidget {
  const DeviceFileContentPreviewCard({
    super.key,
    required this.preview,
    required this.arabicUi,
    required this.onClose,
    this.onCopyText,
  });

  final DeviceFileContentPreview preview;
  final bool arabicUi;
  final VoidCallback onClose;
  final ValueChanged<String>? onCopyText;

  String _t(String arabic, String english) => arabicUi ? arabic : english;

  @override
  Widget build(BuildContext context) {
    final isText = preview.kind == DeviceFileContentKind.text;
    final sizeLabel = preview.sizeBytes < 1024
        ? '${preview.sizeBytes} B'
        : '${(preview.sizeBytes / 1024).toStringAsFixed(1)} KiB';
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 510),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
        decoration: BoxDecoration(
          color: const Color(0xFF101923).withValues(alpha: 0.99),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF7EE787)),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Color(0x99000000), blurRadius: 16),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  isText ? Icons.article_outlined : Icons.image_outlined,
                  color: const Color(0xFF7EE787),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _t('معاينة محلية للملف', 'Local file preview'),
                    style: const TextStyle(
                      color: Color(0xFFE6EDF3),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isText)
                  IconButton(
                    tooltip: _t('نسخ النص', 'Copy text'),
                    onPressed: onCopyText == null
                        ? null
                        : () => onCopyText!(preview.text!),
                    icon: const Icon(Icons.copy_outlined, size: 19),
                  ),
                IconButton(
                  tooltip: _t('إغلاق المعاينة', 'Close preview'),
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 19),
                ),
              ],
            ),
            Text(
              preview.path,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: Color(0xFF9EABB8),
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _t(
                'معاينة محلية فقط • $sizeLabel • لا يرسل التطبيق المحتوى إلى مزود AI.',
                'Local preview only • $sizeLabel • The app does not send content to the AI provider.',
              ),
              style: const TextStyle(fontSize: 10, color: Color(0xFF9EABB8)),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: isText
                  ? Scrollbar(
                      child: SingleChildScrollView(
                        child: SelectableText(
                          preview.text!,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            color: Color(0xFFDCE7F0),
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 4,
                        child: Image.memory(
                          preview.bytes!,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiAgentPage extends StatefulWidget {
  const _AiAgentPage({
    required this.arabicUi,
    required this.stateProvider,
    required this.stateListenable,
    required this.environmentListenable,
    required this.interactivePromptListenable,
    required this.conversations,
    required this.activeConversationId,
    required this.hasTerminalSelection,
    required this.onCreateConversation,
    required this.onOpenConversation,
    required this.onDeleteConversation,
    required this.onRefreshEnvironment,
    required this.onSend,
    required this.onSubmitInteractiveTerminalReply,
    required this.onDismissInteractiveTerminalPrompt,
    required this.onAskInteractiveTerminalPrompt,
    required this.onReviewCommand,
    required this.onOpenSettings,
    required this.onCreateWorkItem,
    required this.onSetWorkItemStatus,
    required this.onDeleteWorkItem,
    required this.onSubmitWorkflowInput,
    required this.onContinueWorkflow,
  });

  final bool arabicUi;
  final AiAgentTaskState Function() stateProvider;
  final ValueListenable<AiAgentTaskState> stateListenable;
  final ValueListenable<AiEnvironmentSnapshot?> environmentListenable;
  final ValueListenable<TerminalInteractivePrompt?> interactivePromptListenable;
  final List<AiAgentConversation> Function() conversations;
  final String? Function() activeConversationId;
  final bool Function() hasTerminalSelection;
  final Future<void> Function() onCreateConversation;
  final Future<void> Function(String id) onOpenConversation;
  final Future<void> Function(String id) onDeleteConversation;
  final VoidCallback onRefreshEnvironment;
  final Future<void> Function(String prompt, bool includeSelection) onSend;
  final Future<void> Function(String response) onSubmitInteractiveTerminalReply;
  final VoidCallback onDismissInteractiveTerminalPrompt;
  final Future<void> Function() onAskInteractiveTerminalPrompt;
  final Future<void> Function(AiAgentMessage message) onReviewCommand;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function(String title, {AiAgentWorkStatus status})
  onCreateWorkItem;
  final Future<void> Function(String id, AiAgentWorkStatus status)
  onSetWorkItemStatus;
  final Future<void> Function(String id) onDeleteWorkItem;
  final Future<void> Function(String workflowId, String response)
  onSubmitWorkflowInput;
  final Future<void> Function(String workflowId) onContinueWorkflow;

  @override
  State<_AiAgentPage> createState() => _AiAgentPageState();
}

class _AiAgentPageState extends State<_AiAgentPage> {
  final _promptController = TextEditingController();
  final _scrollController = ScrollController();
  bool _includeSelection = false;
  bool _sending = false;
  bool _headerExpanded = false;
  bool _taskPanelExpanded = false;
  bool _skillsPanelExpanded = false;

  String _t(String arabic, String english) =>
      widget.arabicUi ? arabic : english;

  TextDirection _promptDirection() =>
      preferredAiReplyLanguage(_promptController.text) == 'Arabic'
      ? TextDirection.rtl
      : TextDirection.ltr;

  @override
  void initState() {
    super.initState();
    _includeSelection = widget.hasTerminalSelection();
    widget.stateListenable.addListener(_scrollToLatest);
    widget.interactivePromptListenable.addListener(
      _scrollToInteractiveTerminalPrompt,
    );
  }

  @override
  void dispose() {
    widget.stateListenable.removeListener(_scrollToLatest);
    widget.interactivePromptListenable.removeListener(
      _scrollToInteractiveTerminalPrompt,
    );
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _scrollToInteractiveTerminalPrompt() {
    if (widget.interactivePromptListenable.value == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _send() async {
    final prompt = _promptController.text.trim();
    final pendingWorkflowInput = pendingWorkflowReply(
      widget.stateProvider().workItems,
    );
    final interactivePrompt = widget.interactivePromptListenable.value;
    if (prompt.isEmpty ||
        _sending ||
        (widget.stateListenable.value.stepLimitReached &&
            pendingWorkflowInput == null &&
            interactivePrompt == null)) {
      return;
    }
    if (interactivePrompt?.kind == TerminalInteractivePromptKind.sensitive) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'لا ترسل قيمة حساسة إلى الوكيل. اكتبها مباشرةً في الطرفية.',
              'Do not send a sensitive value to the agent. Enter it directly in the terminal.',
            ),
          ),
        ),
      );
      return;
    }
    setState(() => _sending = true);
    _promptController.clear();
    if (pendingWorkflowInput != null) {
      await widget.onSubmitWorkflowInput(
        pendingWorkflowInput.workflowId!,
        prompt,
      );
    } else if (interactivePrompt != null) {
      await widget.onSubmitInteractiveTerminalReply(prompt);
    } else {
      await widget.onSend(prompt, _includeSelection);
    }
    if (!mounted) return;
    setState(() => _sending = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _sendSuggestedTerminalReply(String reply) async {
    if (_sending || !isSafeInteractiveTerminalReply(reply)) return;
    setState(() => _sending = true);
    try {
      await widget.onSubmitInteractiveTerminalReply(reply);
      if (mounted) _scrollToLatest();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openWorkBoard(BuildContext context) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => _AiWorkBoardPage(
            arabicUi: widget.arabicUi,
            stateListenable: widget.stateListenable,
            onCreate: widget.onCreateWorkItem,
            onSetStatus: widget.onSetWorkItemStatus,
            onDelete: widget.onDeleteWorkItem,
          ),
        ),
      );

  Future<bool> _confirmDeleteConversation(
    BuildContext context,
    AiAgentConversation conversation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF111820),
        title: Text(_t('حذف المحادثة؟', 'Delete conversation?')),
        content: Text(
          _t(
            'سيُحذف سجل «${conversation.title}» المحلي ومهامه من هذا الجهاز فقط. لا يمكن التراجع عن ذلك.',
            'The local history and tasks for “${conversation.title}” will be removed from this device only. This cannot be undone.',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB42318),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t('حذف', 'Delete')),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TerminalInteractivePrompt?>(
        valueListenable: widget.interactivePromptListenable,
        builder: (context, interactivePrompt, _) =>
            ValueListenableBuilder<AiAgentTaskState>(
              valueListenable: widget.stateListenable,
              builder: (context, task, _) =>
                  _buildPage(context, task, interactivePrompt),
            ),
      );

  Future<void> _openConversationBoard(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111820),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .72,
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              final conversations = widget.conversations();
              final activeId = widget.activeConversationId();
              return Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            _t('المحادثات', 'Conversations'),
                            style: const TextStyle(
                              color: Color(0xFFE6EDF3),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: _t('محادثة جديدة', 'New conversation'),
                          onPressed: () async {
                            await widget.onCreateConversation();
                            if (mounted) setState(() {});
                            setSheetState(() {});
                          },
                          icon: const Icon(Icons.add_comment_outlined),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFF263241)),
                  Expanded(
                    child: ListView.builder(
                      itemCount: conversations.length,
                      itemBuilder: (context, index) {
                        final conversation = conversations[index];
                        final active = conversation.id == activeId;
                        return ListTile(
                          selected: active,
                          selectedTileColor: const Color(0xFF17324A),
                          leading: Icon(
                            active
                                ? Icons.chat_bubble_rounded
                                : Icons.chat_bubble_outline_rounded,
                            color: const Color(0xFF7DD3FC),
                          ),
                          title: Text(
                            conversation.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${conversation.state.openWorkItemCount} ${_t('مهام مفتوحة', 'open tasks')}',
                          ),
                          onTap: () async {
                            await widget.onOpenConversation(conversation.id);
                            if (mounted) setState(() {});
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                          },
                          trailing: IconButton(
                            tooltip: _t('حذف المحادثة', 'Delete conversation'),
                            onPressed: () async {
                              final confirmed =
                                  await _confirmDeleteConversation(
                                    context,
                                    conversation,
                                  );
                              if (!confirmed) return;
                              await widget.onDeleteConversation(
                                conversation.id,
                              );
                              if (mounted) setState(() {});
                              setSheetState(() {});
                            },
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: Color(0xFFFF7B72),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPage(
    BuildContext context,
    AiAgentTaskState task,
    TerminalInteractivePrompt? interactivePrompt,
  ) {
    final pendingWorkflowInput = pendingWorkflowReply(task.workItems);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFF0A0F14),
      appBar: AppBar(
        toolbarHeight: 48,
        backgroundColor: const Color(0xFF111820),
        foregroundColor: const Color(0xFFE6EDF3),
        titleSpacing: 8,
        title: Row(
          children: <Widget>[
            const Icon(Icons.auto_awesome_outlined, color: Color(0xFFD2A8FF)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _t('وكيل Arch', 'Arch agent'),
                style: const TextStyle(fontSize: 17),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            onPressed: () => _openConversationBoard(context),
            tooltip: _t('المحادثات', 'Conversations'),
            icon: const Icon(Icons.forum_outlined, size: 20),
          ),
          IconButton(
            onPressed: () => widget.onOpenSettings(),
            tooltip: _t('إعدادات الوكيل والنماذج', 'Agent and model settings'),
            icon: const Icon(Icons.tune_rounded, size: 20),
          ),
          IconButton(
            onPressed: () async {
              await widget.onCreateConversation();
              if (mounted) setState(() {});
            },
            tooltip: _t('مهمة جديدة', 'New task'),
            icon: const Icon(Icons.add_task_rounded, size: 21),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            InkWell(
              onTap: () => setState(() => _headerExpanded = !_headerExpanded),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                color: const Color(0xFF111820),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.auto_awesome_outlined,
                      color: Color(0xFFD2A8FF),
                      size: 17,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        _t(
                          'وكيل يشرح ويقترح فقط',
                          'Explains and proposes only',
                        ),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFB7C5D3),
                        ),
                      ),
                    ),
                    Text(
                      '${task.approvedCommandCount}/8',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9EE9FF),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _t(
                        '${task.openWorkItemCount} مهام',
                        '${task.openWorkItemCount} tasks',
                      ),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF7EE787),
                      ),
                    ),
                    Icon(
                      _headerExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: const Color(0xFF9EE9FF),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 180),
              firstCurve: Curves.easeOutCubic,
              secondCurve: Curves.easeOutCubic,
              sizeCurve: Curves.easeOutCubic,
              crossFadeState: _headerExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              secondChild: Container(
                color: const Color(0xFF0D151D),
                child: Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
                      child: Text(
                        _t(
                          'يرد الوكيل أولاً ثم يعرض الخطوة المقترحة. لا يُرسل أي أمر للطرفية إلا بعد مراجعتك وموافقتك.',
                          'The agent replies first, then shows its proposed step. No command reaches the terminal without your review and approval.',
                        ),
                        style: const TextStyle(
                          fontSize: 10,
                          height: 1.35,
                          color: Color(0xFFB7C5D3),
                        ),
                      ),
                    ),
                    ValueListenableBuilder<AiEnvironmentSnapshot?>(
                      valueListenable: widget.environmentListenable,
                      builder: (context, environment, _) => _AiEnvironmentCard(
                        arabicUi: widget.arabicUi,
                        environment: environment,
                        onRefresh: widget.onRefreshEnvironment,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (task.workItems.isNotEmpty)
              _AiTaskOverviewCard(
                arabicUi: widget.arabicUi,
                state: task,
                isExpanded: _taskPanelExpanded,
                onToggle: () =>
                    setState(() => _taskPanelExpanded = !_taskPanelExpanded),
                onOpenWorkBoard: () => _openWorkBoard(context),
              ),
            if (task.skillDiscovery != null)
              _AiSkillDiscoveryCard(
                arabicUi: widget.arabicUi,
                discovery: task.skillDiscovery!,
                isExpanded: _skillsPanelExpanded,
                onToggle: () => setState(
                  () => _skillsPanelExpanded = !_skillsPanelExpanded,
                ),
              ),
            Expanded(
              child: task.messages.isEmpty && interactivePrompt == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          _t(
                            'ابدأ بوصف ما تريد تنفيذه في Arch. سيحلل الوكيل المهمة ثم يرد ويقترح الخطوة التالية.',
                            'Describe what you want to do in Arch. The agent will analyze the task, reply, and then suggest the next step.',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF7F91A3),
                            height: 1.45,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      itemCount: task.messages.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, index) {
                        final currentMessage = task.messages[index];
                        final isLatestWorkflowUpdate =
                            currentMessage.workflowId != null &&
                            index ==
                                task.messages.lastIndexWhere(
                                  (candidate) =>
                                      candidate.workflowId ==
                                      currentMessage.workflowId,
                                );
                        final workflowItems =
                            currentMessage.workflowId == null ||
                                !isLatestWorkflowUpdate
                            ? const <AiAgentWorkItem>[]
                            : task.itemsForWorkflow(currentMessage.workflowId!);
                        return _AiAgentMessageCard(
                          message: currentMessage,
                          arabicUi: widget.arabicUi,
                          workflowItems: workflowItems,
                          onReviewCommand: widget.onReviewCommand,
                          onContinueWorkflow: widget.onContinueWorkflow,
                        );
                      },
                    ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF111820),
                border: Border(top: BorderSide(color: Color(0xFF263442))),
              ),
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilterChip(
                      selected: _includeSelection,
                      onSelected: widget.hasTerminalSelection()
                          ? (value) => setState(() => _includeSelection = value)
                          : null,
                      avatar: const Icon(Icons.content_cut_rounded, size: 15),
                      label: Text(
                        _t('النص المحدد فقط', 'Selected text only'),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (interactivePrompt != null) ...<Widget>[
                    _InteractiveTerminalPromptCard(
                      prompt: interactivePrompt,
                      arabicUi: widget.arabicUi,
                      onAskAgent: interactivePrompt.allowsAgentReply
                          ? widget.onAskInteractiveTerminalPrompt
                          : null,
                      onSendSuggestedReply:
                          interactivePrompt.suggestedReply(
                                arabicUi: widget.arabicUi,
                              ) !=
                              null
                          ? _sendSuggestedTerminalReply
                          : null,
                      onDismiss: widget.onDismissInteractiveTerminalPrompt,
                    ),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _promptController,
                          autofocus: true,
                          minLines: 1,
                          maxLines: 3,
                          textDirection: _promptDirection(),
                          textAlign: TextAlign.start,
                          textInputAction: TextInputAction.newline,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0xFF0C151E),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 10,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFF2B465B),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFF62D5FF),
                              ),
                            ),
                            hintText: task.stepLimitReached
                                ? (pendingWorkflowInput == null &&
                                          interactivePrompt == null
                                      ? _t(
                                          'ابدأ مهمة جديدة لمتابعة الوكيل',
                                          'Start a new task to continue the agent',
                                        )
                                      : interactivePrompt?.kind ==
                                                TerminalInteractivePromptKind
                                                    .sensitive &&
                                            pendingWorkflowInput == null
                                      ? _t(
                                          'أدخل القيمة الحساسة مباشرةً في الطرفية…',
                                          'Enter the sensitive value directly in the terminal…',
                                        )
                                      : interactivePrompt != null &&
                                            pendingWorkflowInput == null
                                      ? _t(
                                          'اكتب الرد الذي توافق على إرساله للطرفية…',
                                          'Type the reply you approve sending to the terminal…',
                                        )
                                      : _t(
                                          pendingWorkflowInput
                                                      ?.pendingCommand ==
                                                  null
                                              ? 'اكتب ردك على السؤال هنا…'
                                              : 'اكتب «نعم» للتنفيذ أو «لا» للرفض…',
                                          pendingWorkflowInput
                                                      ?.pendingCommand ==
                                                  null
                                              ? 'Reply to the question here…'
                                              : 'Type yes to run or no to decline…',
                                        ))
                                : (pendingWorkflowInput == null &&
                                          interactivePrompt == null
                                      ? _t(
                                          'اكتب رسالة للوكيل…',
                                          'Message the agent…',
                                        )
                                      : interactivePrompt?.kind ==
                                                TerminalInteractivePromptKind
                                                    .sensitive &&
                                            pendingWorkflowInput == null
                                      ? _t(
                                          'أدخل القيمة الحساسة مباشرةً في الطرفية…',
                                          'Enter the sensitive value directly in the terminal…',
                                        )
                                      : interactivePrompt != null &&
                                            pendingWorkflowInput == null
                                      ? _t(
                                          'اكتب الرد الذي توافق على إرساله للطرفية…',
                                          'Type the reply you approve sending to the terminal…',
                                        )
                                      : _t(
                                          pendingWorkflowInput
                                                      ?.pendingCommand ==
                                                  null
                                              ? 'اكتب ردك على السؤال هنا…'
                                              : 'اكتب «نعم» للتنفيذ أو «لا» للرفض…',
                                          pendingWorkflowInput
                                                      ?.pendingCommand ==
                                                  null
                                              ? 'Reply to the question here…'
                                              : 'Type yes to run or no to decline…',
                                        )),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed:
                            _sending ||
                                (task.stepLimitReached &&
                                    pendingWorkflowInput == null &&
                                    interactivePrompt == null)
                            ? null
                            : _send,
                        tooltip: _t('إرسال', 'Send'),
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeOutCubic,
                          child: _sending
                              ? const SizedBox(
                                  key: ValueKey<String>('sending'),
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.send_rounded,
                                  key: ValueKey<String>('send'),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiSkillDiscoveryCard extends StatelessWidget {
  const _AiSkillDiscoveryCard({
    required this.arabicUi,
    required this.discovery,
    required this.isExpanded,
    required this.onToggle,
  });

  final bool arabicUi;
  final AiSkillDiscovery discovery;
  final bool isExpanded;
  final VoidCallback onToggle;

  String _t(String arabic, String english) => arabicUi ? arabic : english;

  String _title(AiAgentSkill skill) => switch (skill.id) {
    'workflow_planning' => _t('تخطيط المهمة', skill.title),
    'environment_inspection' => _t('فحص البيئة المحلية', skill.title),
    'arch_package_maintenance' => _t('إدارة حزم Arch', skill.title),
    'guarded_terminal_command' => _t('أمر طرفية محروس', skill.title),
    'interactive_terminal_prompt' => _t('سؤال طرفية تفاعلي', skill.title),
    'device_file_discovery' => _t('اكتشاف ملفات الجهاز', skill.title),
    'local_file_preview' => _t('معاينة محلية للملف', skill.title),
    'failure_diagnosis' => _t('تشخيص الفشل', skill.title),
    _ => skill.title,
  };

  String _toolTitle(AiAgentTool tool) => switch (tool.id) {
    'environment_snapshot' => _t('لقطة البيئة', tool.title),
    'guarded_pty_command' => _t('تنفيذ طرفية محروس', tool.title),
    'interactive_prompt_bridge' => _t('جسر السؤال التفاعلي', tool.title),
    'bounded_device_search' => _t('بحث جهاز محدود', tool.title),
    'local_file_renderer' => _t('عارض ملف محلي', tool.title),
    'boot_diagnostic_log' => _t('سجل تشخيص الإقلاع', tool.title),
    _ => tool.title,
  };

  @override
  Widget build(BuildContext context) {
    final selected = discovery.selectedSkills;
    final selectedTools = discovery.selectedTools;
    if (selected.isEmpty && selectedTools.isEmpty) {
      return const SizedBox.shrink();
    }
    final itemCount = selected.length + selectedTools.length;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.fromLTRB(10, 3, 10, 3),
      decoration: BoxDecoration(
        color: isExpanded ? const Color(0xFF142331) : const Color(0xFF111C27),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF315B72)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.hub_outlined,
                    color: Color(0xFF8CE4FF),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _t('أدوات المساعد للمهمة', 'Task assistant tools'),
                          style: const TextStyle(
                            color: Color(0xFFE6EDF3),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _t(
                            '$itemCount عناصر اختيرت تلقائياً للمهمة',
                            '$itemCount items selected automatically for this task',
                          ),
                          style: const TextStyle(
                            color: Color(0xFF8FA7BA),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: const Color(0xFF8CE4FF),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            firstCurve: Curves.easeOutCubic,
            secondCurve: Curves.easeOutCubic,
            sizeCurve: Curves.easeOutCubic,
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Divider(height: 1, color: Color(0xFF2C4A5F)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: selected
                        .map(
                          (skill) => Chip(
                            label: Text(_title(skill)),
                            labelStyle: const TextStyle(fontSize: 10),
                            side: const BorderSide(color: Color(0xFF356A84)),
                            backgroundColor: const Color(0xFF162F40),
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .followedBy(
                          selectedTools.map(
                            (tool) => Chip(
                              avatar: const Icon(
                                Icons.build_outlined,
                                size: 14,
                                color: Color(0xFFFFC857),
                              ),
                              label: Text(_toolTitle(tool)),
                              labelStyle: const TextStyle(fontSize: 10),
                              side: const BorderSide(color: Color(0xFF7A6030)),
                              backgroundColor: const Color(0xFF332712),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _t(
                      'هذه العناصر تساعد الوكيل على التخطيط، لكنها لا تنفذ أي أمر ولا تمنح وصولاً إضافياً.',
                      'These items guide planning only; they do not run commands or grant extra access.',
                    ),
                    style: const TextStyle(
                      color: Color(0xFF9DB0C2),
                      fontSize: 10,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiTaskOverviewCard extends StatelessWidget {
  const _AiTaskOverviewCard({
    required this.arabicUi,
    required this.state,
    required this.isExpanded,
    required this.onToggle,
    required this.onOpenWorkBoard,
  });

  final bool arabicUi;
  final AiAgentTaskState state;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onOpenWorkBoard;

  String _t(String arabic, String english) => arabicUi ? arabic : english;

  @override
  Widget build(BuildContext context) {
    final items = <AiAgentWorkItem>[...state.workItems]
      ..sort((left, right) => left.updatedAt.compareTo(right.updatedAt));
    final active = items.where(
      (item) =>
          item.status == AiAgentWorkStatus.inProgress ||
          item.status == AiAgentWorkStatus.waitingForApproval ||
          item.status == AiAgentWorkStatus.waitingForUserInput,
    );
    final current = active.isEmpty
        ? items.firstWhere(
            (item) => item.status != AiAgentWorkStatus.completed,
            orElse: () => items.last,
          )
        : active.first;
    final completed = state.completedWorkItemCount;
    final isComplete = completed == items.length;
    final goal = items
        .map((item) => item.workflowGoal?.trim() ?? '')
        .firstWhere((item) => item.isNotEmpty, orElse: () => state.taskSummary)
        .trim();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(10, 9, 10, 3),
      decoration: BoxDecoration(
        color: const Color(0xFF101B27),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isComplete ? const Color(0xFF2F8C64) : const Color(0xFF2E5874),
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 10, 10),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: isComplete
                          ? const Color(0xFF173A2D)
                          : const Color(0xFF153044),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      isComplete
                          ? Icons.task_alt_rounded
                          : Icons.account_tree_outlined,
                      size: 18,
                      color: isComplete
                          ? const Color(0xFF7EE787)
                          : const Color(0xFF8CE4FF),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _t('المهمة الحالية', 'Current task'),
                          style: const TextStyle(
                            color: Color(0xFF9DB0C2),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          goal.isEmpty
                              ? _t('خطة تنفيذ الوكيل', 'Agent execution plan')
                              : goal,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFF0F6FC),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onOpenWorkBoard,
                    tooltip: _t('لوحة المهام', 'Task board'),
                    icon: const Icon(Icons.list_alt_rounded, size: 18),
                    color: const Color(0xFF8CE4FF),
                    visualDensity: VisualDensity.compact,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isComplete
                          ? const Color(0xFF16362A)
                          : const Color(0xFF192E40),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      isComplete
                          ? _t('مكتملة', 'Done')
                          : '$completed/${items.length}',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        color: isComplete
                            ? const Color(0xFFBFF3D0)
                            : const Color(0xFF9EE9FF),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: const Color(0xFF9EE9FF),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Divider(height: 1, color: const Color(0xFF29435A)),
                  const SizedBox(height: 9),
                  if (!isComplete)
                    _AiTaskNowLine(arabicUi: arabicUi, item: current),
                  if (!isComplete) const SizedBox(height: 8),
                  ...items
                      .take(3)
                      .map(
                        (item) =>
                            _AiTaskStepLine(arabicUi: arabicUi, item: item),
                      ),
                  if (items.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        _t(
                          '+ ${items.length - 3} خطوات إضافية في لوحة المهام',
                          '+ ${items.length - 3} more steps in the task board',
                        ),
                        style: const TextStyle(
                          color: Color(0xFF8DA2B5),
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
            firstCurve: Curves.easeOutCubic,
            secondCurve: Curves.easeOutCubic,
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    );
  }
}

class _AiTaskNowLine extends StatelessWidget {
  const _AiTaskNowLine({required this.arabicUi, required this.item});

  final bool arabicUi;
  final AiAgentWorkItem item;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: const Color(0xFF132D3F),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: const Color(0xFF286888)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(
          Icons.play_circle_outline_rounded,
          size: 16,
          color: Color(0xFF63D3FF),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                arabicUi ? 'يجري الآن' : 'Now',
                style: const TextStyle(
                  color: Color(0xFF9EE9FF),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                item.title,
                style: const TextStyle(
                  color: Color(0xFFE7F3FB),
                  fontSize: 11,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AiTaskStepLine extends StatelessWidget {
  const _AiTaskStepLine({required this.arabicUi, required this.item});

  final bool arabicUi;
  final AiAgentWorkItem item;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          _workflowStepIcon(item.status),
          size: 16,
          color: _workItemStatusColor(item.status),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            '${item.order + 1}. ${item.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFD8E6F0),
              fontSize: 11,
              height: 1.25,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _workItemStatusLabel(item.status, arabicUi),
          style: TextStyle(
            color: _workItemStatusColor(item.status),
            fontSize: 9,
          ),
        ),
      ],
    ),
  );
}

class _InteractiveTerminalPromptCard extends StatelessWidget {
  const _InteractiveTerminalPromptCard({
    required this.prompt,
    required this.arabicUi,
    required this.onAskAgent,
    required this.onSendSuggestedReply,
    required this.onDismiss,
  });

  final TerminalInteractivePrompt prompt;
  final bool arabicUi;
  final Future<void> Function()? onAskAgent;
  final Future<void> Function(String reply)? onSendSuggestedReply;
  final VoidCallback onDismiss;

  String _t(String arabic, String english) => arabicUi ? arabic : english;

  @override
  Widget build(BuildContext context) {
    final suggestedReply = prompt.suggestedReply(arabicUi: arabicUi);
    return Card(
      color: const Color(0xFF12232A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF2A7A86)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.question_answer_outlined,
                  color: Color(0xFF62D5FF),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _t('سؤال تفاعلي من الطرفية', 'Interactive terminal prompt'),
                    style: const TextStyle(
                      color: Color(0xFFE6EDF3),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              prompt.summary(arabicUi: arabicUi),
              style: const TextStyle(color: Color(0xFFB7C5D3), height: 1.35),
            ),
            if (prompt.assistantExplanation != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                prompt.assistantExplanation!,
                style: const TextStyle(color: Color(0xFFE6EDF3), height: 1.35),
              ),
            ],
            if (suggestedReply != null) ...<Widget>[
              const SizedBox(height: 7),
              Text(
                _t(
                  'الرد المقترح: $suggestedReply. اختر الموافقة لإرساله إلى الطرفية؛ لن يُرسل من دون ضغطك على الزر.',
                  'Suggested reply: $suggestedReply. Choose approve to send it to the terminal; it is never sent without your tap.',
                ),
                style: const TextStyle(color: Color(0xFFFFD46A), fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            if (suggestedReply != null && onSendSuggestedReply != null)
              FilledButton.icon(
                onPressed: prompt.analysisInProgress
                    ? null
                    : () => onSendSuggestedReply!(suggestedReply),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  _t(
                    'أوافق وأرسل $suggestedReply للطرفية',
                    'Approve and send $suggestedReply to terminal',
                  ),
                ),
              ),
            if (onAskAgent != null)
              OutlinedButton.icon(
                onPressed: prompt.analysisInProgress
                    ? null
                    : () => onAskAgent!(),
                icon: prompt.analysisInProgress
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_outlined, size: 18),
                label: Text(
                  prompt.analysisInProgress
                      ? _t('يفهم المساعد السؤال…', 'Assistant is analyzing…')
                      : _t(
                          'دع المساعد يفهم السؤال',
                          'Let the assistant understand it',
                        ),
                ),
              )
            else
              Text(
                _t(
                  'لا يقرأ الوكيل كلمات المرور أو الأسرار. أدخل القيمة مباشرةً في الطرفية.',
                  'The agent does not read passwords or secrets. Enter the value directly in the terminal.',
                ),
                style: const TextStyle(color: Color(0xFFFFB454), fontSize: 12),
              ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: onDismiss,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(_t('أجبت في الطرفية', 'I answered in terminal')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiAgentMessageCard extends StatelessWidget {
  const _AiAgentMessageCard({
    required this.message,
    required this.arabicUi,
    required this.workflowItems,
    required this.onReviewCommand,
    required this.onContinueWorkflow,
  });
  final AiAgentMessage message;
  final bool arabicUi;
  final List<AiAgentWorkItem> workflowItems;
  final Future<void> Function(AiAgentMessage message) onReviewCommand;
  final Future<void> Function(String workflowId) onContinueWorkflow;

  String _t(String arabic, String english) => arabicUi ? arabic : english;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AiAgentRole.user;
    final isAgent = message.role == AiAgentRole.agent;
    final isObservation = message.role == AiAgentRole.observation;
    final color = isUser
        ? const Color(0xFF173047)
        : isObservation
        ? const Color(0xFF1C2936)
        : const Color(0xFF18222D);
    final label = isUser
        ? _t('أنت', 'You')
        : isObservation
        ? _t('شرح محلي لمخرجات الطرفية', 'Local terminal explanation')
        : isAgent
        ? _t('وكيل Arch', 'Arch agent')
        : _t('حالة الوكيل', 'Agent status');
    final icon = isUser
        ? Icons.person_outline_rounded
        : isObservation
        ? Icons.terminal_rounded
        : isAgent
        ? Icons.auto_awesome_outlined
        : Icons.info_outline_rounded;
    final stamp =
        '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: isUser
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isAgent ? const Color(0xFF344456) : Colors.transparent,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          icon,
                          size: 15,
                          color: isObservation
                              ? const Color(0xFF9EE9FF)
                              : isUser
                              ? const Color(0xFF8CE4FF)
                              : const Color(0xFFD2A8FF),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFB7C5D3),
                            ),
                          ),
                        ),
                        Text(
                          stamp,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            fontSize: 9,
                            color: Color(0xFF7F91A3),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      message.content,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFE2EDF6),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (workflowItems.isNotEmpty) ...<Widget>[
              const SizedBox(height: 7),
              _AiWorkflowProgressCard(
                arabicUi: arabicUi,
                items: workflowItems,
                onContinueWorkflow: onContinueWorkflow,
              ),
            ],
            if (message.localResultPaths.isNotEmpty) ...<Widget>[
              const SizedBox(height: 7),
              _AiLocalResultCard(
                arabicUi: arabicUi,
                paths: message.localResultPaths,
              ),
            ],
            if (isAgent &&
                message.proposedCommand != null &&
                message.workflowId == null) ...<Widget>[
              const SizedBox(height: 7),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF132638),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2F88AD)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        _t(
                          'الخطوة المقترحة بعد الرد',
                          'Suggested next step after the reply',
                        ),
                        style: const TextStyle(
                          color: Color(0xFF9EE9FF),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      SelectableText(
                        message.proposedCommand!,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Color(0xFF7EE787),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: OutlinedButton.icon(
                          onPressed: () => onReviewCommand(message),
                          icon: const Icon(Icons.shield_outlined, size: 17),
                          label: Text(
                            _t('مراجعة وتنفيذ', 'Review and execute'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AiLocalResultCard extends StatelessWidget {
  const _AiLocalResultCard({required this.arabicUi, required this.paths});

  final bool arabicUi;
  final List<String> paths;

  String _t(String arabic, String english) => arabicUi ? arabic : english;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF102B25),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF2D8262)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.folder_copy_outlined,
                size: 17,
                color: Color(0xFF7EE787),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _t('النتيجة المحلية', 'Local result'),
                  style: const TextStyle(
                    color: Color(0xFFC9F4D7),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '${paths.length}',
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: Color(0xFF9EE9FF), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _t(
              'هذه الأسماء والمسارات معروضة محلياً فقط ولم تُرسل إلى مزود AI.',
              'These names and paths are shown locally only and were not sent to the AI provider.',
            ),
            style: const TextStyle(
              color: Color(0xFFA8C9B7),
              fontSize: 10,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 7),
          ...paths.map(
            (path) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SelectableText(
                path,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: Color(0xFFE2F7E9),
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _AiWorkflowProgressCard extends StatelessWidget {
  const _AiWorkflowProgressCard({
    required this.arabicUi,
    required this.items,
    required this.onContinueWorkflow,
  });

  final bool arabicUi;
  final List<AiAgentWorkItem> items;
  final Future<void> Function(String workflowId) onContinueWorkflow;

  String _t(String arabic, String english) => arabicUi ? arabic : english;

  @override
  Widget build(BuildContext context) {
    final completed = items
        .where((item) => item.status == AiAgentWorkStatus.completed)
        .length;
    final waitingForInput = items
        .where((item) => item.status == AiAgentWorkStatus.waitingForUserInput)
        .toList();
    final inputItem = waitingForInput.isEmpty ? null : waitingForInput.first;
    final hasActiveStep = items.any(
      (item) =>
          item.status == AiAgentWorkStatus.inProgress ||
          item.status == AiAgentWorkStatus.waitingForApproval ||
          item.status == AiAgentWorkStatus.waitingForUserInput,
    );
    final nextQueued = items
        .where((item) => item.status == AiAgentWorkStatus.queued)
        .toList();
    final goal = items.first.workflowGoal;
    final isComplete = completed == items.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF10232B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF245362)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.account_tree_outlined,
                  color: Color(0xFF8CE4FF),
                  size: 17,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _t('خطة العمل', 'Workflow'),
                    style: const TextStyle(
                      color: Color(0xFFB4EEFF),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '$completed/${items.length}',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9EE9FF),
                  ),
                ),
                if (isComplete) ...<Widget>[
                  const SizedBox(width: 7),
                  const Icon(
                    Icons.verified_rounded,
                    size: 16,
                    color: Color(0xFF7EE787),
                  ),
                ],
              ],
            ),
            if (goal != null && goal.isNotEmpty) ...<Widget>[
              const SizedBox(height: 5),
              Text(
                goal,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFD4E7EF),
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (isComplete)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF16362A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF2F8C64)),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.task_alt_rounded,
                      size: 16,
                      color: Color(0xFF7EE787),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _t(
                          'اكتملت الخطة. راجع النتيجة المحلية أو ملخص الأمر في هذه الرسالة.',
                          'Plan complete. Review the local result or command summary in this message.',
                        ),
                        style: const TextStyle(
                          color: Color(0xFFC7F3D8),
                          fontSize: 10,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      _workflowStepIcon(item.status),
                      size: 17,
                      color: _workItemStatusColor(item.status),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${item.order + 1}. ${item.title}',
                            style: const TextStyle(
                              color: Color(0xFFE1EFF4),
                              fontSize: 11,
                              height: 1.25,
                            ),
                          ),
                          if (item.detail.isNotEmpty)
                            Text(
                              item.detail,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF9EB6C0),
                                fontSize: 10,
                                height: 1.25,
                              ),
                            ),
                          if (item.inputRequest != null &&
                              item.inputRequest!.isNotEmpty)
                            Text(
                              '${_t('المطلوب: ', 'Needed: ')}${item.inputRequest}',
                              style: const TextStyle(
                                color: Color(0xFFFFD46A),
                                fontSize: 10,
                                height: 1.25,
                              ),
                            ),
                          if (item.pendingCommand != null &&
                              item.pendingCommand!.isNotEmpty)
                            SelectableText(
                              '${_t('الأمر بانتظار الموافقة: ', 'Command awaiting approval: ')}${item.pendingCommand}',
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                color: Color(0xFF7EE787),
                                fontFamily: 'monospace',
                                fontSize: 10,
                                height: 1.25,
                              ),
                            ),
                          if (item.inputResponse != null &&
                              item.inputResponse!.isNotEmpty)
                            Text(
                              '${_t('ردك: ', 'Your response: ')}${item.inputResponse}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF8CE4FF),
                                fontSize: 10,
                                height: 1.25,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      _workItemStatusLabel(item.status, arabicUi),
                      style: TextStyle(
                        color: _workItemStatusColor(item.status),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (inputItem != null) ...<Widget>[
              const SizedBox(height: 3),
              Text(
                _t(
                  inputItem.pendingCommand == null
                      ? 'اكتب ردك مباشرةً في حقل الدردشة أسفل الشاشة ثم أرسله.'
                      : 'اكتب «نعم» أو «لا» مباشرةً في حقل الدردشة أسفل الشاشة.',
                  inputItem.pendingCommand == null
                      ? 'Reply directly in the chat field below, then send it.'
                      : 'Type yes or no directly in the chat field below.',
                ),
                style: const TextStyle(
                  color: Color(0xFF8CE4FF),
                  fontSize: 10,
                  height: 1.3,
                ),
              ),
            ],
            if (inputItem == null && !hasActiveStep && nextQueued.isNotEmpty)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: nextQueued.first.workflowId == null
                      ? null
                      : () => onContinueWorkflow(nextQueued.first.workflowId!),
                  icon: const Icon(Icons.play_arrow_rounded, size: 17),
                  label: Text(
                    _t('متابعة المرحلة التالية', 'Continue next stage'),
                  ),
                ),
              ),
            Text(
              _t(
                'الخطة توضح النية والتقدم فقط؛ لا يُنفّذ أمر في الطرفية إلا بعد موافقتك.',
                'The workflow shows intent and progress only; no terminal command runs without your approval.',
              ),
              style: const TextStyle(
                color: Color(0xFF8FB0BA),
                fontSize: 9,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _workflowStepIcon(AiAgentWorkStatus status) => switch (status) {
  AiAgentWorkStatus.queued => Icons.circle_outlined,
  AiAgentWorkStatus.inProgress => Icons.sync_rounded,
  AiAgentWorkStatus.waitingForApproval => Icons.pending_actions_rounded,
  AiAgentWorkStatus.waitingForUserInput => Icons.question_answer_outlined,
  AiAgentWorkStatus.completed => Icons.check_circle_rounded,
  AiAgentWorkStatus.needsAttention => Icons.error_outline_rounded,
};

class _AiEnvironmentCard extends StatelessWidget {
  const _AiEnvironmentCard({
    required this.arabicUi,
    required this.environment,
    required this.onRefresh,
  });

  final bool arabicUi;
  final AiEnvironmentSnapshot? environment;
  final VoidCallback onRefresh;

  String _t(String arabic, String english) => arabicUi ? arabic : english;

  @override
  Widget build(BuildContext context) {
    final snapshot = environment;
    final scannedAt = snapshot?.scannedAt.toLocal().toString().split('.').first;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 9, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: const Color(0xFF10232B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF245362)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.memory_outlined,
              color: Color(0xFF8CE4FF),
              size: 19,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: snapshot == null
                ? Text(
                    _t(
                      'بيئة Arch لم تُفحص بعد. شغّل جلسة ثم حدّث البيئة.',
                      'Arch environment has not been scanned yet. Start a session, then refresh it.',
                    ),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFD4E7EF),
                      height: 1.35,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _t('بيئة Arch المحلية', 'Local Arch environment'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          color: Color(0xFFB4EEFF),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        snapshot.conciseSummary,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFE1EFF4),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _t(
                          'المساحة الحرة: ${snapshot.rootFreeText} · آخر فحص: $scannedAt',
                          'Free space: ${snapshot.rootFreeText} · Last scan: $scannedAt',
                        ),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF9EB6C0),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        snapshot.repositoryConfigured
                            ? _t(
                                'المستودعات: ${snapshot.repositorySummary} · المرآة: ${snapshot.repositoryMirror.isEmpty ? 'محلية' : snapshot.repositoryMirror}',
                                'Repositories: ${snapshot.repositorySummary} · Mirror: ${snapshot.repositoryMirror.isEmpty ? 'local' : snapshot.repositoryMirror}',
                              )
                            : _t(
                                'المستودعات: لم يُكتشف إعداد pacman بعد',
                                'Repositories: no pacman configuration detected yet',
                              ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF8CE4FF),
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _t(
                          'الفحص يقرأ الإعداد وقواعد المزامنة محلياً فقط؛ لا يزامن أو يعدّل الحزم. يُرسل الملخص فقط عند إرسال رسالة للوكيل.',
                          'The probe only reads local configuration and sync databases; it does not synchronize or modify packages. The summary is sent only when you message the agent.',
                        ),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF8FB0BA),
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
          ),
          IconButton(
            onPressed: onRefresh,
            tooltip: _t('تحديث البيئة', 'Refresh environment'),
            color: const Color(0xFF8CE4FF),
            icon: const Icon(Icons.refresh_rounded, size: 19),
          ),
        ],
      ),
    );
  }
}

class _AiWorkBoardPage extends StatefulWidget {
  const _AiWorkBoardPage({
    required this.arabicUi,
    required this.stateListenable,
    required this.onCreate,
    required this.onSetStatus,
    required this.onDelete,
  });

  final bool arabicUi;
  final ValueListenable<AiAgentTaskState> stateListenable;
  final Future<void> Function(String title, {AiAgentWorkStatus status})
  onCreate;
  final Future<void> Function(String id, AiAgentWorkStatus status) onSetStatus;
  final Future<void> Function(String id) onDelete;

  @override
  State<_AiWorkBoardPage> createState() => _AiWorkBoardPageState();
}

class _AiWorkBoardPageState extends State<_AiWorkBoardPage> {
  AiAgentWorkStatus? _filter;

  String _t(String arabic, String english) =>
      widget.arabicUi ? arabic : english;

  Future<void> _addWorkItem() async {
    final controller = TextEditingController();
    var status = AiAgentWorkStatus.queued;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF111820),
          title: Text(_t('إضافة مهمة', 'Add task')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 280,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: _t('وصف المهمة', 'Task description'),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<AiAgentWorkStatus>(
                initialValue: status,
                decoration: InputDecoration(labelText: _t('الحالة', 'Status')),
                items: AiAgentWorkStatus.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(
                          _workItemStatusLabel(value, widget.arabicUi),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => status = value ?? status),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_t('إلغاء', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_t('إضافة محلياً', 'Add locally')),
            ),
          ],
        ),
      ),
    );
    final title = controller.text.trim();
    controller.dispose();
    if (accepted == true && title.isNotEmpty) {
      await widget.onCreate(title, status: status);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<AiAgentTaskState>(
    valueListenable: widget.stateListenable,
    builder: (context, task, _) {
      final visible = task.workItems.reversed
          .where((item) => _filter == null || item.status == _filter)
          .toList();
      return Scaffold(
        backgroundColor: const Color(0xFF0A0F14),
        appBar: AppBar(
          backgroundColor: const Color(0xFF111820),
          foregroundColor: const Color(0xFFE6EDF3),
          title: Text(_t('إدارة مهام الوكيل', 'Agent task manager')),
          actions: <Widget>[
            IconButton(
              onPressed: _addWorkItem,
              tooltip: _t('إضافة مهمة', 'Add task'),
              icon: const Icon(Icons.add_task_rounded),
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              color: const Color(0xFF111820),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _t(
                      'كل المهام محفوظة محلياً على الجهاز. يحلل الوكيل رسالة الدردشة إلى خطوات صغيرة تظهر هنا وفي المحادثة؛ عدّل الحالة يدوياً عند الحاجة.',
                      'All tasks are saved locally on this device. The agent turns a chat request into small steps shown here and in the conversation; adjust a status manually when needed.',
                    ),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFB7C5D3),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: <Widget>[
                      ChoiceChip(
                        label: Text(
                          _t(
                            'الكل ${task.workItems.length}',
                            'All ${task.workItems.length}',
                          ),
                        ),
                        selected: _filter == null,
                        onSelected: (_) => setState(() => _filter = null),
                      ),
                      ...AiAgentWorkStatus.values.map(
                        (status) => ChoiceChip(
                          label: Text(
                            '${_workItemStatusLabel(status, widget.arabicUi)} ${task.workItems.where((item) => item.status == status).length}',
                          ),
                          selected: _filter == status,
                          onSelected: (_) => setState(() => _filter = status),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          _filter == null
                              ? _t(
                                  'لا توجد مهام بعد. أرسل رسالة للوكيل أو أضف مهمة من زر +.',
                                  'No tasks yet. Send the agent a message or add a task with +.',
                                )
                              : _t(
                                  'لا توجد مهام بهذه الحالة.',
                                  'No tasks have this status.',
                                ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF7F91A3),
                            height: 1.4,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final item = visible[index];
                        final color = _workItemStatusColor(item.status);
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFF151E28),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: color.withValues(alpha: 0.48),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 7, 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Icon(
                                  _workflowStepIcon(item.status),
                                  color: color,
                                  size: 19,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      SelectableText(
                                        item.title,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFFE2EDF6),
                                          height: 1.35,
                                        ),
                                      ),
                                      if (item.workflowGoal != null &&
                                          item.workflowGoal!.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                          ),
                                          child: Text(
                                            _t(
                                              'الهدف: ${item.workflowGoal}',
                                              'Goal: ${item.workflowGoal}',
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Color(0xFF8CE4FF),
                                              height: 1.25,
                                            ),
                                          ),
                                        ),
                                      if (item.detail.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 3,
                                          ),
                                          child: Text(
                                            item.detail,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Color(0xFF9EB6C0),
                                              height: 1.25,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 7),
                                      DropdownButtonHideUnderline(
                                        child:
                                            DropdownButton<AiAgentWorkStatus>(
                                              value: item.status,
                                              isDense: true,
                                              dropdownColor: const Color(
                                                0xFF1B2631,
                                              ),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: color,
                                              ),
                                              items: AiAgentWorkStatus.values
                                                  .map(
                                                    (
                                                      status,
                                                    ) => DropdownMenuItem(
                                                      value: status,
                                                      child: Text(
                                                        _workItemStatusLabel(
                                                          status,
                                                          widget.arabicUi,
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: (value) {
                                                if (value != null) {
                                                  unawaited(
                                                    widget.onSetStatus(
                                                      item.id,
                                                      value,
                                                    ),
                                                  );
                                                }
                                              },
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () =>
                                      unawaited(widget.onDelete(item.id)),
                                  tooltip: _t('حذف المهمة', 'Delete task'),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 19,
                                  ),
                                  color: const Color(0xFFB7C5D3),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}

String _workItemStatusLabel(AiAgentWorkStatus status, bool arabicUi) =>
    switch (status) {
      AiAgentWorkStatus.queued => arabicUi ? 'بانتظار البدء' : 'Queued',
      AiAgentWorkStatus.inProgress => arabicUi ? 'قيد التنفيذ' : 'In progress',
      AiAgentWorkStatus.waitingForApproval =>
        arabicUi ? 'بانتظار موافقتك' : 'Waiting for approval',
      AiAgentWorkStatus.waitingForUserInput =>
        arabicUi ? 'بانتظار ردّك' : 'Waiting for your reply',
      AiAgentWorkStatus.completed => arabicUi ? 'مكتملة' : 'Completed',
      AiAgentWorkStatus.needsAttention =>
        arabicUi ? 'تحتاج انتباهك' : 'Needs attention',
    };

Color _workItemStatusColor(AiAgentWorkStatus status) => switch (status) {
  AiAgentWorkStatus.queued => const Color(0xFF9EE9FF),
  AiAgentWorkStatus.inProgress => const Color(0xFFD2A8FF),
  AiAgentWorkStatus.waitingForApproval => const Color(0xFFFFD46A),
  AiAgentWorkStatus.waitingForUserInput => const Color(0xFFFFB454),
  AiAgentWorkStatus.completed => const Color(0xFF7EE787),
  AiAgentWorkStatus.needsAttention => const Color(0xFFFF7B72),
};

class _TerminalHeader extends StatelessWidget {
  const _TerminalHeader({
    required this.running,
    required this.arabicUi,
    required this.onClear,
    required this.onOpenActivityHistory,
    required this.onOpenSettings,
  });
  final bool running;
  final bool arabicUi;
  final VoidCallback onClear;
  final VoidCallback onOpenActivityHistory;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFF202A34))),
    ),
    child: Row(
      children: <Widget>[
        const Icon(Icons.terminal_rounded, color: Color(0xFF62D5FF), size: 20),
        const SizedBox(width: 6),
        const Text(
          'ARCH TERMINAL',
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontFamily: 'monospace',
            letterSpacing: 0.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        _LiveDot(active: running),
        const SizedBox(width: 4),
        Text(
          running ? 'SESSION' : 'IDLE',
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: Color(0xFF9FB0C0),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 38, height: 40),
          padding: EdgeInsets.zero,
          tooltip: arabicUi ? 'سجل الجلسات والنشاط' : 'Sessions and activity',
          onPressed: onOpenActivityHistory,
          icon: const Icon(Icons.history_rounded, size: 20),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 38, height: 40),
          padding: EdgeInsets.zero,
          tooltip: arabicUi ? 'الإعدادات والأوامر' : 'Settings and commands',
          onPressed: onOpenSettings,
          icon: const Icon(Icons.settings_outlined, size: 20),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 38, height: 40),
          padding: EdgeInsets.zero,
          tooltip: arabicUi ? 'مسح الطرفية' : 'Clear terminal',
          onPressed: onClear,
          icon: const Icon(Icons.cleaning_services_outlined, size: 19),
        ),
      ],
    ),
  );
}

class _LocalActivityHistoryPage extends StatelessWidget {
  const _LocalActivityHistoryPage({
    required this.arabicUi,
    required this.historyListenable,
    required this.onToggleFavorite,
    required this.onDeleteSession,
    required this.onRerunCommand,
  });

  final bool arabicUi;
  final ValueListenable<LocalActivityHistory> historyListenable;
  final Future<void> Function(LocalCapabilityActivity item) onToggleFavorite;
  final Future<void> Function(String id) onDeleteSession;
  final Future<void> Function(String command) onRerunCommand;

  String _t(String arabic, String english) => arabicUi ? arabic : english;

  String _time(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  String _sessionStatus(LocalTerminalSessionRecord item) =>
      switch (item.status) {
        LocalTerminalSessionStatus.active => _t('نشطة', 'Active'),
        LocalTerminalSessionStatus.ended => _t('انتهت', 'Ended'),
        LocalTerminalSessionStatus.failed => _t(
          'تحتاج انتباهاً',
          'Needs attention',
        ),
      };

  Color _sessionColor(LocalTerminalSessionRecord item) => switch (item.status) {
    LocalTerminalSessionStatus.active => const Color(0xFF8CE4FF),
    LocalTerminalSessionStatus.ended => const Color(0xFF7EE787),
    LocalTerminalSessionStatus.failed => const Color(0xFFFF7B72),
  };

  String _capabilityTitle(LocalCapabilityActivity item) {
    final skill = item.kind == LocalCapabilityKind.skill
        ? AiSkillCatalog.byId(item.id)
        : null;
    final tool = item.kind == LocalCapabilityKind.tool
        ? AiSkillCatalog.toolById(item.id)
        : null;
    return (skill?.title ?? tool?.title ?? item.id).replaceAll('_', ' ');
  }

  String _capabilitySummary(LocalCapabilityActivity item) {
    final skill = item.kind == LocalCapabilityKind.skill
        ? AiSkillCatalog.byId(item.id)
        : null;
    final tool = item.kind == LocalCapabilityKind.tool
        ? AiSkillCatalog.toolById(item.id)
        : null;
    return skill?.summary ?? tool?.summary ?? '';
  }

  void _showSessionDetail(
    BuildContext context,
    LocalTerminalSessionRecord item,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF121B24),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                item.label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 10),
              _HistoryDetailLine(
                label: _t('بدأت', 'Started'),
                value: _time(item.startedAt),
              ),
              if (item.endedAt != null)
                _HistoryDetailLine(
                  label: _t('انتهت', 'Ended'),
                  value: _time(item.endedAt!),
                ),
              _HistoryDetailLine(
                label: _t('الحالة', 'Status'),
                value: _sessionStatus(item),
              ),
              if (item.exitCode != null)
                _HistoryDetailLine(
                  label: _t('رمز الخروج', 'Exit code'),
                  value: '${item.exitCode}',
                ),
              const SizedBox(height: 10),
              Text(
                _t('الأوامر المعتمدة', 'Approved commands'),
                style: const TextStyle(
                  color: Color(0xFF8CE4FF),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              if (item.commands.isEmpty)
                Text(
                  _t(
                    'لا توجد أوامر معتمدة محفوظة لهذه الجلسة.',
                    'No approved commands are stored for this session.',
                  ),
                  style: const TextStyle(
                    color: Color(0xFF9CB0C1),
                    fontSize: 12,
                  ),
                )
              else
                ...item.commands.map(
                  (entry) => Card(
                    color: const Color(0xFF0C131A),
                    margin: const EdgeInsets.only(bottom: 7),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: SelectableText(
                              entry.command,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Color(0xFFDCE7F0),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: _t('نسخ الأمر', 'Copy command'),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: entry.command),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _t(
                                        'نُسخ الأمر محلياً.',
                                        'Command copied locally.',
                                      ),
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.copy_outlined, size: 19),
                          ),
                          IconButton(
                            tooltip: _t('إعادة الاقتراح', 'Review and rerun'),
                            onPressed: () async {
                              Navigator.pop(sheetContext);
                              await onRerunCommand(entry.command);
                            },
                            icon: const Icon(Icons.replay_rounded, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                _t(
                  'تُحفظ الأوامر المعتمدة محلياً فقط. زر إعادة الاقتراح يمر عبر الحارس والموافقة من جديد، ولا يعرض السجل مخرجات الطرفية أو يرسلها.',
                  'Approved commands are stored locally only. Review and rerun passes through the guard and approval again; terminal output is not shown or sent.',
                ),
                style: const TextStyle(
                  color: Color(0xFF9CB0C1),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: Text(_t('سجل النشاط المحلي', 'Local activity history')),
        bottom: TabBar(
          tabs: <Widget>[
            Tab(text: _t('الجلسات', 'Sessions')),
            Tab(text: _t('الأخيرة', 'Recent')),
            Tab(text: _t('المفضلة', 'Favorites')),
          ],
        ),
      ),
      body: ValueListenableBuilder<LocalActivityHistory>(
        valueListenable: historyListenable,
        builder: (context, history, _) => TabBarView(
          children: <Widget>[
            _buildSessions(context, history),
            _buildCapabilities(history, favoritesOnly: false),
            _buildCapabilities(history, favoritesOnly: true),
          ],
        ),
      ),
    ),
  );

  Widget _buildSessions(BuildContext context, LocalActivityHistory history) {
    if (history.sessions.isEmpty) {
      return _HistoryEmptyState(
        icon: Icons.terminal_rounded,
        title: _t('لا توجد جلسات مسجلة بعد', 'No recorded sessions yet'),
        detail: _t(
          'يُضاف سجل عند بدء جلسة طرفية ناجحة.',
          'A record is added after a terminal session starts successfully.',
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: history.sessions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = history.sessions[index];
        return Card(
          color: const Color(0xFF111A23),
          child: ListTile(
            onTap: () => _showSessionDetail(context, item),
            leading: CircleAvatar(
              backgroundColor: _sessionColor(item).withValues(alpha: 0.16),
              child: Icon(Icons.terminal_rounded, color: _sessionColor(item)),
            ),
            title: Text(item.label),
            subtitle: Text(
              '${_sessionStatus(item)} · ${_time(item.startedAt)}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: IconButton(
              tooltip: _t('حذف السجل', 'Delete record'),
              onPressed: () => onDeleteSession(item.id),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCapabilities(
    LocalActivityHistory history, {
    required bool favoritesOnly,
  }) {
    final entries = history.capabilities
        .where((item) => !favoritesOnly || history.isFavorite(item))
        .toList();
    if (entries.isEmpty) {
      return _HistoryEmptyState(
        icon: favoritesOnly ? Icons.star_outline_rounded : Icons.hub_outlined,
        title: favoritesOnly
            ? _t('لا توجد عناصر مفضلة', 'No favorite items')
            : _t(
                'لم تُكتشف مهارات أو أدوات بعد',
                'No skills or tools discovered yet',
              ),
        detail: favoritesOnly
            ? _t(
                'احفظ عنصراً من القائمة الأخيرة ليظهر هنا.',
                'Save an item from Recent to show it here.',
              )
            : _t(
                'أرسل هدفاً للوكيل ليختار العناصر المناسبة تلقائياً.',
                'Send a goal to the agent to select relevant items automatically.',
              ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = entries[index];
        final favorite = history.isFavorite(item);
        return Card(
          color: const Color(0xFF111A23),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: item.kind == LocalCapabilityKind.skill
                  ? const Color(0xFF153044)
                  : const Color(0xFF332712),
              child: Icon(
                item.kind == LocalCapabilityKind.skill
                    ? Icons.auto_awesome_outlined
                    : Icons.build_outlined,
                color: item.kind == LocalCapabilityKind.skill
                    ? const Color(0xFF8CE4FF)
                    : const Color(0xFFFFC857),
              ),
            ),
            title: Text(_capabilityTitle(item)),
            subtitle: Text(
              '${item.kind == LocalCapabilityKind.skill ? _t('مهارة', 'Skill') : _t('أداة', 'Tool')} · ${_time(item.lastUsedAt)}\n${_capabilitySummary(item)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: favorite
                  ? _t('إزالة من المفضلة', 'Remove favorite')
                  : _t('حفظ في المفضلة', 'Save favorite'),
              onPressed: () => onToggleFavorite(item),
              icon: Icon(
                favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                color: favorite ? const Color(0xFFFFC857) : null,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HistoryDetailLine extends StatelessWidget {
  const _HistoryDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(
      children: <Widget>[
        SizedBox(
          width: 88,
          child: Text(label, style: const TextStyle(color: Color(0xFF8FA7BA))),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: const Color(0xFF8CE4FF), size: 38),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF92A6B8), fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class SetupProgressViewModel {
  const SetupProgressViewModel({
    required this.running,
    required this.phase,
    required this.message,
    required this.percent,
    required this.downloaded,
    required this.total,
    required this.speed,
    this.extractedFiles = 0,
    this.totalFiles = 0,
    this.filesPerSecond = 0,
    this.secondsRemaining,
    this.archiveSource,
    this.failureDetail,
  });
  factory SetupProgressViewModel.fromStatus(Map<String, Object?> raw) =>
      SetupProgressViewModel(
        running: raw['setupRunning'] == true,
        phase: raw['setupPhase']?.toString() ?? 'idle',
        message: raw['setupMessage']?.toString() ?? '',
        percent: (raw['setupPercent'] as num?)?.toInt(),
        downloaded: (raw['setupBytesDownloaded'] as num?)?.toInt() ?? 0,
        total: (raw['setupTotalBytes'] as num?)?.toInt() ?? -1,
        speed: (raw['setupBytesPerSecond'] as num?)?.toInt() ?? 0,
        extractedFiles: (raw['setupExtractedFiles'] as num?)?.toInt() ?? 0,
        totalFiles: (raw['setupTotalFiles'] as num?)?.toInt() ?? 0,
        filesPerSecond: (raw['setupFilesPerSecond'] as num?)?.toInt() ?? 0,
        secondsRemaining: (raw['setupSecondsRemaining'] as num?)?.toInt(),
        archiveSource: raw['setupArchiveSource']?.toString(),
        failureDetail: raw['setupFailureDetail']?.toString(),
      );
  final bool running;
  final String phase;
  final String message;
  final int? percent;
  final int downloaded;
  final int total;
  final int speed;
  final int extractedFiles;
  final int totalFiles;
  final int filesPerSecond;
  final int? secondsRemaining;
  final String? archiveSource;
  final String? failureDetail;
  bool get isTerminalState => phase == 'complete' || phase == 'error';
  bool get hasExtractionDetails => phase == 'extracting' && totalFiles > 0;
}

class SetupProgressBanner extends StatelessWidget {
  const SetupProgressBanner({
    super.key,
    required this.progress,
    required this.arabicUi,
  });
  final SetupProgressViewModel progress;
  final bool arabicUi;

  String _t(String arabic, String english) => arabicUi ? arabic : english;

  String? get _resumeHint {
    if (progress.phase == 'downloading' && progress.downloaded > 0) {
      return _t(
        'سيُستأنف التنزيل من الجزء المحفوظ إذا أُغلق التطبيق أو اخترت الإلغاء.',
        'Downloading resumes from the saved part if the app closes or you cancel.',
      );
    }
    if ((progress.phase == 'counting' || progress.phase == 'extracting') &&
        progress.archiveSource != null) {
      return _t(
        'يُستخدم الأرشيف المحفوظ الآن؛ تُحفظ الملفات المكتملة للاستئناف عند إعادة الفتح.',
        'The saved archive is in use; completed entries are kept for resume after reopening.',
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final error = progress.phase == 'error';
    final color = error
        ? const Color(0xFFFF7B72)
        : progress.phase == 'complete'
        ? const Color(0xFF7EE787)
        : const Color(0xFF62D5FF);
    final phaseLabel = _phaseLabel(progress.phase, arabicUi);
    final label = progress.percent == null
        ? _t('جارٍ $phaseLabel', '$phaseLabel in progress')
        : '${progress.percent}% — $phaseLabel';
    final stableFileRate =
        progress.filesPerSecond > 0 && progress.filesPerSecond <= 100000;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                error
                    ? Icons.error_outline
                    : progress.phase == 'complete'
                    ? Icons.verified_outlined
                    : Icons.downloading_rounded,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              if (progress.running)
                Icon(Icons.fiber_manual_record_rounded, color: color, size: 11),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            progress.message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.start,
            style: const TextStyle(
              fontSize: 12,
              height: 1.35,
              color: Color(0xFFC2CEDA),
            ),
          ),
          if (progress.archiveSource != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                switch (progress.archiveSource) {
                  'public' => _t(
                    'المصدر: ملف محفوظ في التخزين العام',
                    'Source: saved file in shared storage',
                  ),
                  'local' => _t(
                    'المصدر: ملف محفوظ محلياً داخل التطبيق',
                    'Source: locally saved file in the app',
                  ),
                  _ => _t(
                    'المصدر: تنزيل جديد من مستودع Arch',
                    'Source: new download from the Arch repository',
                  ),
                },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xFF9EE9FF)),
              ),
            ),
          if (_resumeHint != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF0B2635),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 5,
                  ),
                  child: Text(
                    _resumeHint!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      height: 1.3,
                      color: Color(0xFF9EE9FF),
                    ),
                  ),
                ),
              ),
            ),
          if (error && progress.failureDetail != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SelectableText(
                    _t(
                      'التفصيل: ${progress.failureDetail}',
                      'Detail: ${progress.failureDetail}',
                    ),
                    key: const Key('setup-failure-detail'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: Color(0xFFFFB4AE),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    setupFailureGuidance(
                          phase: progress.phase,
                          detail: progress.failureDetail!,
                          arabicUi: arabicUi,
                        ) ??
                        '',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFFFFD46A),
                    ),
                  ),
                ],
              ),
            ),
          if (progress.running) ...<Widget>[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress.percent == null ? null : progress.percent! / 100,
              minHeight: 4,
              color: color,
              backgroundColor: const Color(0xFF1B2732),
            ),
            if (progress.hasExtractionDetails)
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runAlignment: WrapAlignment.spaceBetween,
                  spacing: 10,
                  runSpacing: 4,
                  children: <Widget>[
                    Text(
                      _t(
                        'الملفات: ${progress.extractedFiles} من ${progress.totalFiles}',
                        'Files: ${progress.extractedFiles} of ${progress.totalFiles}',
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFD5E2EC),
                      ),
                    ),
                    Text(
                      progress.secondsRemaining == null
                          ? _t('جارٍ حساب الوقت…', 'Calculating time…')
                          : _t(
                              'المتبقي: ${_duration(progress.secondsRemaining!)}',
                              'Remaining: ${_duration(progress.secondsRemaining!, arabicUi)}',
                            ),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9FB0C0),
                      ),
                    ),
                    if (stableFileRate)
                      Text(
                        _t(
                          'السرعة: ${progress.filesPerSecond} ملف/ث',
                          'Speed: ${progress.filesPerSecond} files/s',
                        ),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF9FB0C0),
                        ),
                      ),
                    if (progress.filesPerSecond > 100000)
                      Text(
                        _t(
                          'جارٍ معايرة سرعة الاستخراج…',
                          'Calibrating extraction speed…',
                        ),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF9FB0C0),
                        ),
                      ),
                  ],
                ),
              ),
            if (progress.downloaded > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${_bytes(progress.downloaded)}${progress.total > 0 ? ' / ${_bytes(progress.total)}' : ''}${progress.speed > 0 ? '  •  ${_bytes(progress.speed)}/ث' : ''}',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: Color(0xFF9FB0C0),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CommandPanel extends StatelessWidget {
  const _CommandPanel({
    required this.busy,
    required this.setupRunning,
    required this.isAndroid,
    required this.archInstalled,
    required this.prootAvailable,
    required this.pacmanSandboxDisabled,
    required this.rootfsDnsConfigured,
    required this.batteryIgnored,
    required this.backgroundProtectionEnabled,
    required this.notificationsGranted,
    required this.persistentStorage,
    required this.storageReady,
    required this.publicStorageGranted,
    required this.deviceStorageGranted,
    required this.publicArchivePresent,
    required this.permissionsReady,
    required this.arabicUi,
    required this.terminalFontSize,
    required this.soundEnabled,
    required this.soundVolume,
    required this.statusText,
    required this.progress,
    required this.aiSettings,
    required this.onClose,
    required this.onInstallArch,
    required this.onCancelDownload,
    required this.onSearchLog,
    required this.onExportLog,
    required this.onStartupDiagnostics,
    required this.onNewSession,
    required this.onEditSessionName,
    required this.onAiSettings,
    required this.onAiAsk,
    required this.onStorage,
    required this.onDeviceFiles,
    required this.onStorageSettings,
    required this.onBattery,
    required this.onBackgroundProtection,
    required this.onNotifications,
    required this.onFontSize,
    required this.onSoundEnabled,
    required this.onSoundVolume,
    required this.onSoundPreview,
    required this.onLanguage,
  });
  final bool busy,
      setupRunning,
      isAndroid,
      archInstalled,
      prootAvailable,
      pacmanSandboxDisabled,
      rootfsDnsConfigured,
      batteryIgnored,
      backgroundProtectionEnabled,
      notificationsGranted,
      persistentStorage,
      storageReady,
      publicStorageGranted,
      deviceStorageGranted,
      publicArchivePresent,
      permissionsReady;
  final bool arabicUi;
  final double terminalFontSize;
  final bool soundEnabled;
  final double soundVolume;
  final String statusText;
  final SetupProgressViewModel progress;
  final AiSettings? aiSettings;
  final VoidCallback onClose,
      onInstallArch,
      onCancelDownload,
      onSearchLog,
      onExportLog,
      onStartupDiagnostics,
      onNewSession,
      onEditSessionName,
      onAiSettings,
      onAiAsk,
      onStorage,
      onDeviceFiles,
      onStorageSettings,
      onBattery,
      onBackgroundProtection,
      onNotifications;
  final ValueChanged<double> onFontSize;
  final ValueChanged<bool> onSoundEnabled;
  final ValueChanged<double> onSoundVolume;
  final VoidCallback onSoundPreview;
  final ValueChanged<InterfaceLanguage> onLanguage;

  String _t(String arabic, String english) => arabicUi ? arabic : english;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF111820),
    elevation: 18,
    child: Listener(
      onPointerDown: (_) => onSoundPreview(),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 8, 10),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.keyboard_command_key_rounded,
                    color: Color(0xFF62D5FF),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _t('الإعدادات والأوامر', 'Settings and commands'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: onClose,
                    tooltip: _t('إغلاق', 'Close'),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF263442)),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _AppearanceSettings(
                      arabicUi: arabicUi,
                      fontSize: terminalFontSize,
                      soundEnabled: soundEnabled,
                      soundVolume: soundVolume,
                      onFontSize: onFontSize,
                      onSoundEnabled: onSoundEnabled,
                      onSoundVolume: onSoundVolume,
                      onSoundPreview: onSoundPreview,
                      onLanguage: onLanguage,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Text(
                        _t('حالة النظام', 'SYSTEM STATUS'),
                        style: const TextStyle(
                          color: Color(0xFF8294A7),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        statusText,
                        style: const TextStyle(
                          color: Color(0xFFB7C5D3),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 9, 16, 6),
                      child: Wrap(
                        spacing: 7,
                        runSpacing: 5,
                        children: <Widget>[
                          if (isAndroid)
                            _StatusChip(
                              label: archInstalled
                                  ? 'ARCH READY'
                                  : 'ARCH MISSING',
                              color: archInstalled
                                  ? const Color(0xFF7EE787)
                                  : const Color(0xFFFFB454),
                            ),
                          if (isAndroid)
                            _StatusChip(
                              label: prootAvailable ? 'PROOT OK' : 'PROOT ?',
                              color: prootAvailable
                                  ? const Color(0xFF7EE787)
                                  : const Color(0xFFFF7B72),
                            ),
                          if (isAndroid && archInstalled)
                            _StatusChip(
                              label: rootfsDnsConfigured
                                  ? 'DNS READY'
                                  : 'DNS CHECK',
                              color: rootfsDnsConfigured
                                  ? const Color(0xFF7EE787)
                                  : const Color(0xFFFFB454),
                            ),
                          if (isAndroid && archInstalled)
                            _StatusChip(
                              label: pacmanSandboxDisabled
                                  ? 'PACMAN PROOT OK'
                                  : 'PACMAN CHECK',
                              color: pacmanSandboxDisabled
                                  ? const Color(0xFF7EE787)
                                  : const Color(0xFFFFB454),
                            ),
                          if (isAndroid)
                            _StatusChip(
                              label: batteryIgnored
                                  ? 'BATTERY FREE'
                                  : 'BATTERY MANAGED',
                              color: batteryIgnored
                                  ? const Color(0xFF62D5FF)
                                  : const Color(0xFFFFB454),
                            ),
                        ],
                      ),
                    ),
                    if (setupRunning || progress.isTerminalState)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
                        child: SetupProgressBanner(
                          progress: progress,
                          arabicUi: arabicUi,
                        ),
                      ),
                    if (isAndroid &&
                        setupRunning &&
                        const <String>{
                          'connecting',
                          'downloading',
                          'verifying',
                          'cancelling',
                        }.contains(progress.phase))
                      _CommandTile(
                        icon: Icons.cancel_outlined,
                        label: _t(
                          'إلغاء التنزيل مع حفظ التقدم',
                          'Cancel download and keep progress',
                        ),
                        detail: _t(
                          'سيبقى ملف الجزء المكتمل للاستئناف عند المتابعة.',
                          'The completed partial file remains available when you continue.',
                        ),
                        enabled: progress.phase != 'cancelling',
                        onTap: onCancelDownload,
                        accent: const Color(0xFFFFB454),
                      ),
                    const Divider(height: 20, color: Color(0xFF263442)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                      child: Text(
                        _t('السجل والجلسة', 'LOG AND SESSION'),
                        style: const TextStyle(
                          color: Color(0xFF8294A7),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _CommandTile(
                      icon: Icons.search_rounded,
                      label: _t('بحث في سجل الطرفية', 'Search terminal log'),
                      detail: _t(
                        'يعرض عدد التطابقات في النص الظاهر حالياً.',
                        'Shows the number of matches in currently visible terminal text.',
                      ),
                      enabled: true,
                      onTap: onSearchLog,
                      accent: const Color(0xFF62D5FF),
                    ),
                    if (isAndroid)
                      _CommandTile(
                        icon: Icons.ios_share_rounded,
                        label: _t('تصدير سجل الطرفية', 'Export terminal log'),
                        detail: _t(
                          'يفتح قائمة مشاركة Android كنص فقط؛ لا يحتاج خادماً.',
                          'Opens Android share as plain text; no server is used.',
                        ),
                        enabled: true,
                        onTap: onExportLog,
                        accent: const Color(0xFF7EE787),
                      ),
                    if (isAndroid)
                      _CommandTile(
                        icon: Icons.bug_report_outlined,
                        label: _t('تشخيص إقلاع التطبيق', 'Startup diagnostics'),
                        detail: _t(
                          'يعرض سجل إقلاع محلياً مستقلاً مع نسخ أو مشاركة؛ لا يحتاج ADB أو خادماً.',
                          'Opens an independent local startup log with copy and share; no ADB or server is needed.',
                        ),
                        enabled: true,
                        onTap: onStartupDiagnostics,
                        accent: const Color(0xFFFFB454),
                      ),
                    _CommandTile(
                      icon: Icons.edit_note_rounded,
                      label: _t('تسمية الجلسة', 'Name session'),
                      detail: _t(
                        'احفظ اسماً قصيراً للجلسة المحلية الحالية.',
                        'Save a short name for the current local session.',
                      ),
                      enabled: true,
                      onTap: onEditSessionName,
                      accent: const Color(0xFFD2A8FF),
                    ),
                    _CommandTile(
                      icon: Icons.restart_alt_rounded,
                      label: _t('بدء جلسة جديدة', 'Start a new session'),
                      detail: _t(
                        'يعيد فتح الطرفية ويحفظ سجل الجلسة العميقة.',
                        'Restarts the terminal while preserving the deep-session transcript.',
                      ),
                      enabled: !busy && !setupRunning,
                      onTap: onNewSession,
                      accent: const Color(0xFFFFB454),
                    ),
                    _CommandTile(
                      icon: Icons.smart_toy_outlined,
                      label: _t('إعداد مساعد AI', 'Configure AI assistant'),
                      detail: aiSettings?.isReady == true
                          ? _t(
                              'المزود: ${aiSettings!.provider!.label} — المفتاح محفوظ محلياً.',
                              'Provider: ${aiSettings!.provider!.label} — key stored locally.',
                            )
                          : _t(
                              'اختياري؛ اختر مزوداً وأدخل مفتاحك محلياً أولاً.',
                              'Optional; choose a provider and enter your key locally first.',
                            ),
                      enabled: true,
                      onTap: onAiSettings,
                      accent: aiSettings?.isReady == true
                          ? const Color(0xFF7EE787)
                          : const Color(0xFF62D5FF),
                    ),
                    _CommandTile(
                      icon: Icons.auto_awesome_outlined,
                      label: _t('اسأل مساعد AI', 'Ask AI assistant'),
                      detail: _t(
                        'يعرض اقتراحاً ثم يطلب موافقتك قبل إرسال أي أمر للطرفية.',
                        'Shows a proposal, then requests approval before any command reaches the terminal.',
                      ),
                      enabled:
                          aiSettings?.isReady == true && !busy && !setupRunning,
                      onTap: onAiAsk,
                      accent: const Color(0xFFD2A8FF),
                    ),
                    const Divider(height: 20, color: Color(0xFF263442)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                      child: Text(
                        _t('صلاحيات واستمرارية', 'PERMISSIONS AND PERSISTENCE'),
                        style: const TextStyle(
                          color: Color(0xFF8294A7),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (isAndroid)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          permissionsReady
                              ? _t(
                                  'الصلاحيات المطلوبة جاهزة. ستبدأ جلسة Arch تلقائياً بعد الإعداد.',
                                  'Required permissions are ready. Arch starts automatically after setup.',
                                )
                              : _t(
                                  'هذه بوابة إلزامية: لن يبدأ التنزيل قبل تفعيل كل العناصر التالية.',
                                  'This is a required gate: downloading cannot start until every item below is enabled.',
                                ),
                          style: TextStyle(
                            fontSize: 11,
                            color: permissionsReady
                                ? const Color(0xFF7EE787)
                                : const Color(0xFFFFD46A),
                          ),
                        ),
                      ),
                    if (isAndroid)
                      _CommandTile(
                        icon: backgroundProtectionEnabled
                            ? Icons.shield_rounded
                            : Icons.shield_outlined,
                        label: backgroundProtectionEnabled
                            ? _t(
                                'حماية جلسة Arch بالخلفية مفعّلة',
                                'Arch background protection enabled',
                              )
                            : _t(
                                'تفعيل حماية جلسة Arch بالخلفية',
                                'Enable Arch background protection',
                              ),
                        detail: backgroundProtectionEnabled
                            ? _t(
                                'خدمة أمامية وإشعار مستمر وقفل CPU أثناء الجلسة. قد يطلب Android أو النظام المصنّع إيقاف التطبيق رغم ذلك.',
                                'Foreground service, ongoing notification, and a CPU wake lock while the session runs. Android or the device vendor may still reclaim the app.',
                              )
                            : _t(
                                'يزيد فرصة بقاء جلسة Arch عند الانتقال للخلفية. سيطلب الإشعارات واستثناء البطارية عند الحاجة، ويستهلك طاقة أكثر.',
                                'Improves the chance that an Arch session survives in the background. It requests notifications and battery exemption when needed, and uses more power.',
                              ),
                        enabled: true,
                        onTap: onBackgroundProtection,
                        accent: backgroundProtectionEnabled
                            ? const Color(0xFF7EE787)
                            : const Color(0xFF62D5FF),
                      ),
                    if (isAndroid)
                      _CommandTile(
                        icon: batteryIgnored
                            ? Icons.battery_full_rounded
                            : Icons.battery_saver_outlined,
                        label: batteryIgnored
                            ? _t(
                                'تحسين البطارية متوقف',
                                'Battery optimization disabled',
                              )
                            : _t(
                                'السماح بالعمل دون تحسين البطارية',
                                'Allow unrestricted battery use',
                              ),
                        detail: batteryIgnored
                            ? _t(
                                'التنزيل الطويل أقل عرضة للإيقاف',
                                'Long downloads are less likely to stop',
                              )
                            : _t(
                                'موصى به لإعداد Arch في الخلفية',
                                'Recommended for background setup',
                              ),
                        enabled: !batteryIgnored,
                        onTap: onBattery,
                        accent: batteryIgnored
                            ? const Color(0xFF7EE787)
                            : const Color(0xFFFFB454),
                      ),
                    if (isAndroid)
                      _CommandTile(
                        icon: notificationsGranted
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_off_outlined,
                        label: notificationsGranted
                            ? _t(
                                'إشعار التقدم مفعّل',
                                'Progress notification enabled',
                              )
                            : _t(
                                'السماح بإشعار التقدم',
                                'Allow progress notification',
                              ),
                        detail: _t(
                          'يبقى التقدم ظاهراً أثناء العمل بالخلفية',
                          'Progress remains visible in background',
                        ),
                        enabled: !notificationsGranted,
                        onTap: onNotifications,
                      ),
                    if (isAndroid)
                      _CommandTile(
                        icon: Icons.save_alt_outlined,
                        label: _t('إعداد حفظ Arch', 'Arch storage setting'),
                        detail: persistentStorage
                            ? _t(
                                'حفظ عام يبقى بعد حذف التطبيق',
                                'Shared storage survives uninstall',
                              )
                            : _t(
                                'حفظ داخلي خاص بالتطبيق',
                                'Private app storage',
                              ),
                        enabled: true,
                        onTap: onStorageSettings,
                        accent: persistentStorage
                            ? const Color(0xFF7EE787)
                            : const Color(0xFF62D5FF),
                      ),
                    if (isAndroid)
                      _CommandTile(
                        icon: deviceStorageGranted
                            ? Icons.folder_open_outlined
                            : Icons.folder_off_outlined,
                        label: deviceStorageGranted
                            ? _t(
                                'ملفات الجهاز داخل Arch: /sdcard',
                                'Device files in Arch: /sdcard',
                              )
                            : _t(
                                'السماح بملفات الجهاز في Arch',
                                'Allow device files in Arch',
                              ),
                        detail: deviceStorageGranted
                            ? _t(
                                'يمكن للطرفية الوصول إليها؛ لا يرسل المساعد محتوى ملفاتك تلقائياً.',
                                'The terminal can access them; the assistant does not send file contents automatically.',
                              )
                            : _t(
                                'امنح الإذن من Android ثم افتح جلسة جديدة لربط /sdcard.',
                                'Grant Android access, then open a new session to bind /sdcard.',
                              ),
                        enabled: true,
                        onTap: onDeviceFiles,
                        accent: deviceStorageGranted
                            ? const Color(0xFF7EE787)
                            : const Color(0xFFFFB454),
                      ),
                    if (isAndroid)
                      _CommandTile(
                        icon: publicStorageGranted
                            ? Icons.folder_open_outlined
                            : Icons.folder_off_outlined,
                        label: publicStorageGranted
                            ? _t(
                                'وصول التخزين العام مفعّل',
                                'Shared storage access enabled',
                              )
                            : _t(
                                'السماح بوصول التخزين العام',
                                'Allow shared storage access',
                              ),
                        detail: publicStorageGranted
                            ? _t(
                                'سيُفحص مجلد Arch المحفوظ قبل أي تنزيل',
                                'The saved Arch folder will be checked before any download',
                              )
                            : _t(
                                'مطلوب لفحص النسخة المحفوظة قبل التنزيل',
                                'Required to check for a saved copy before downloading',
                              ),
                        enabled: !publicStorageGranted,
                        onTap: onStorage,
                      ),
                    if (isAndroid &&
                        publicArchivePresent &&
                        !(archInstalled && prootAvailable))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 5, 16, 0),
                        child: Text(
                          _t(
                            'تم العثور على ملف Arch محفوظ؛ سيتحقق التطبيق منه ويستخرجه بدلاً من تنزيل جديد.',
                            'A saved Arch file was found; it will be verified and extracted instead of downloaded again.',
                          ),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF7EE787),
                          ),
                        ),
                      ),
                    if (isAndroid)
                      _CommandTile(
                        icon: setupRunning
                            ? Icons.downloading_rounded
                            : !permissionsReady
                            ? Icons.admin_panel_settings_outlined
                            : publicArchivePresent
                            ? Icons.inventory_2_outlined
                            : Icons.cloud_download_outlined,
                        label: setupRunning
                            ? _t(
                                'الإعداد يعمل في الخلفية',
                                'Setup runs in background',
                              )
                            : !permissionsReady
                            ? _t(
                                'فتح بوابة صلاحيات Arch',
                                'Open Arch permission gate',
                              )
                            : archInstalled && prootAvailable
                            ? _t(
                                'Arch جاهز للتشغيل التلقائي',
                                'Arch is ready for automatic start',
                              )
                            : publicArchivePresent
                            ? _t(
                                'التحقق وإعداد Arch المحفوظ',
                                'Verify and set up saved Arch',
                              )
                            : _t(
                                'تنزيل وإعداد Arch',
                                'Download and set up Arch',
                              ),
                        detail: setupRunning
                            ? _t(
                                'راجع إشعار النظام أو شريط التقدم',
                                'See the notification or progress bar',
                              )
                            : !permissionsReady
                            ? _t(
                                'اعرض الصلاحيات الناقصة أولاً؛ لن يبدأ التنزيل',
                                'View missing permissions first; download will not start',
                              )
                            : archInstalled && prootAvailable
                            ? _t(
                                'لن يُعاد التنزيل؛ ستبدأ الجلسة تلقائياً',
                                'Nothing will be downloaded; the session starts automatically',
                              )
                            : publicArchivePresent
                            ? _t(
                                'تحقق ثم استخراج بلا تنزيل جديد عند سلامة الملف',
                                'Verify then extract without downloading again if valid',
                              )
                            : _t(
                                'سيبدأ التنزيل ثم التحقق والاستخراج تلقائياً',
                                'Download, verification, and extraction start automatically',
                              ),
                        enabled: !busy && !setupRunning,
                        onTap: onInstallArch,
                        accent: const Color(0xFF62D5FF),
                      ),
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'ARCH TERMINAL / LOCAL RUNTIME',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: Color(0xFF64778A),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AppearanceSettings extends StatelessWidget {
  const _AppearanceSettings({
    required this.arabicUi,
    required this.fontSize,
    required this.soundEnabled,
    required this.soundVolume,
    required this.onFontSize,
    required this.onSoundEnabled,
    required this.onSoundVolume,
    required this.onSoundPreview,
    required this.onLanguage,
  });
  final bool arabicUi;
  final double fontSize;
  final bool soundEnabled;
  final double soundVolume;
  final ValueChanged<double> onFontSize;
  final ValueChanged<bool> onSoundEnabled;
  final ValueChanged<double> onSoundVolume;
  final VoidCallback onSoundPreview;
  final ValueChanged<InterfaceLanguage> onLanguage;

  String _t(String arabic, String english) => arabicUi ? arabic : english;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF17212B),
        border: Border.all(color: const Color(0xFF2A4255)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              _t('الواجهة والطرفية', 'INTERFACE AND TERMINAL'),
              style: const TextStyle(
                color: Color(0xFF62D5FF),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _t('لغة الواجهة', 'Interface language'),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 5),
            SegmentedButton<InterfaceLanguage>(
              segments: const <ButtonSegment<InterfaceLanguage>>[
                ButtonSegment(
                  value: InterfaceLanguage.arabic,
                  label: Text('العربية'),
                  icon: Icon(Icons.language_rounded, size: 16),
                ),
                ButtonSegment(
                  value: InterfaceLanguage.english,
                  label: Text('English'),
                  icon: Icon(Icons.translate_rounded, size: 16),
                ),
              ],
              selected: <InterfaceLanguage>{
                arabicUi ? InterfaceLanguage.arabic : InterfaceLanguage.english,
              },
              onSelectionChanged: (value) => onLanguage(value.first),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
            const SizedBox(height: 11),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _t('حجم خط الطرفية', 'Terminal font size'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Text(
                  '${fontSize.toStringAsFixed(0)} px',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFF9EE9FF),
                  ),
                ),
              ],
            ),
            Slider(
              value: fontSize,
              min: TerminalPreferences.minFontSize,
              max: TerminalPreferences.maxFontSize,
              divisions: 13,
              label: '${fontSize.toStringAsFixed(0)} px',
              onChanged: onFontSize,
            ),
            Text(
              _t(
                'الافتراضي 12px؛ يمكن خفضه حتى 7px للشاشات ذات المساحة المحدودة.',
                'Default 12px; it can go down to 7px for space-constrained screens.',
              ),
              style: const TextStyle(fontSize: 10, color: Color(0xFF9FB0C0)),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.volume_up_outlined,
                  size: 18,
                  color: Color(0xFF62D5FF),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _t('أصوات التفاعل', 'Interaction sounds'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Switch.adaptive(value: soundEnabled, onChanged: onSoundEnabled),
              ],
            ),
            Text(
              _t(
                'نقرة هادئة للتفاعل، نغمة نجاح للنتائج، وتنبيه للأخطاء. لا تُسجل الأصوات ولا تُرسل خارج الجهاز.',
                'A soft interaction tone, a success tone for results, and an error alert. Sounds are not recorded or sent off-device.',
              ),
              style: const TextStyle(fontSize: 10, color: Color(0xFF9FB0C0)),
            ),
            if (soundEnabled) ...<Widget>[
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Slider(
                      value: soundVolume,
                      min: 0,
                      max: 1,
                      divisions: 10,
                      label: '${(soundVolume * 100).round()}%',
                      onChanged: onSoundVolume,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: soundVolume > 0 ? onSoundPreview : null,
                    icon: const Icon(Icons.play_arrow_rounded, size: 17),
                    label: Text(_t('تجربة', 'Test')),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              _t(
                'اضغط مطولاً على النص لتحديده، ثم استخدم شريط النسخ.',
                'Long-press text to select it, then use the copy toolbar.',
              ),
              style: const TextStyle(fontSize: 10, color: Color(0xFF9FB0C0)),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({
    required this.arabicUi,
    required this.onCopy,
    required this.onSelectAll,
    required this.onDismiss,
  });
  final bool arabicUi;
  final Future<void> Function() onCopy;
  final VoidCallback onSelectAll;
  final VoidCallback onDismiss;

  String _t(String arabic, String english) => arabicUi ? arabic : english;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF1B2A36),
    elevation: 8,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextButton.icon(
            onPressed: onCopy,
            icon: const Icon(Icons.copy_outlined, size: 17),
            label: Text(_t('نسخ', 'Copy')),
          ),
          TextButton.icon(
            onPressed: onSelectAll,
            icon: const Icon(Icons.select_all_rounded, size: 17),
            label: Text(_t('تحديد الكل', 'Select all')),
          ),
          IconButton(
            tooltip: _t('إلغاء التحديد', 'Dismiss selection'),
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    ),
  );
}

class _CommandTile extends StatelessWidget {
  const _CommandTile({
    required this.icon,
    required this.label,
    required this.detail,
    required this.enabled,
    required this.onTap,
    this.accent = const Color(0xFFE6EDF3),
  });
  final IconData icon;
  final String label, detail;
  final bool enabled;
  final VoidCallback onTap;
  final Color accent;
  @override
  Widget build(BuildContext context) => ListTile(
    enabled: enabled,
    onTap: enabled ? onTap : null,
    leading: Icon(icon, color: enabled ? accent : const Color(0xFF566574)),
    title: Text(label, style: const TextStyle(fontSize: 14)),
    subtitle: Text(detail, style: const TextStyle(fontSize: 11)),
    trailing: const Icon(Icons.chevron_left_rounded, size: 18),
  );
}

class TerminalImageLayer extends StatelessWidget {
  const TerminalImageLayer({
    super.key,
    required this.child,
    required this.image,
    this.onClose,
  });

  final Widget child;
  final TerminalInlineImage? image;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        child,
        if (image != null && onClose != null)
          Positioned(
            right: 12,
            bottom: 12,
            child: InlineImagePreview(image: image!, onClose: onClose!),
          ),
      ],
    );
  }
}

class InlineImagePreview extends StatelessWidget {
  const InlineImagePreview({
    super.key,
    required this.image,
    required this.onClose,
  });

  final TerminalInlineImage image;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xEE10151C),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220, maxHeight: 220),
        child: SizedBox(
          key: const Key('inline-image-preview-viewport'),
          width: 160,
          height: 160,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Image.memory(
                  image.bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Inline image could not be decoded'),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                  tooltip: 'Close image preview',
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      border: Border.all(color: color.withValues(alpha: 0.35)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Text(
        label,
        textDirection: TextDirection.ltr,
        style: TextStyle(fontFamily: 'monospace', color: color, fontSize: 9),
      ),
    ),
  );
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(
      color: active ? const Color(0xFF7EE787) : const Color(0xFF657485),
      shape: BoxShape.circle,
      boxShadow: active
          ? const <BoxShadow>[
              BoxShadow(color: Color(0xFF7EE787), blurRadius: 8),
            ]
          : null,
    ),
  );
}

String _phaseLabel(String phase, bool arabicUi) {
  final arabic = switch (phase) {
    'connecting' => 'الاتصال',
    'downloading' => 'التنزيل',
    'verifying' => 'التحقق',
    'verified' => 'تم التحقق',
    'counting' => 'عدّ الأرشيف',
    'extracting' => 'الاستخراج',
    'configuring' => 'التهيئة',
    'complete' => 'جاهز',
    'error' => 'خطأ',
    _ => 'الإعداد',
  };
  final english = switch (phase) {
    'connecting' => 'Connecting',
    'downloading' => 'Downloading',
    'verifying' => 'Verifying',
    'verified' => 'Verified',
    'counting' => 'Counting archive',
    'extracting' => 'Extracting',
    'configuring' => 'Configuring',
    'complete' => 'Ready',
    'error' => 'Error',
    _ => 'Setup',
  };
  return arabicUi ? arabic : english;
}

String _bytes(int value) {
  if (value < 1024) return '$value B';
  if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
  if (value < 1024 * 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String _duration(int seconds, [bool arabicUi = true]) {
  if (seconds <= 0) return arabicUi ? 'لحظات' : 'moments';
  if (seconds < 60) return arabicUi ? '$seconds ثانية' : '$seconds sec';
  if (seconds < 3600) {
    return arabicUi ? '${seconds ~/ 60} دقيقة' : '${seconds ~/ 60} min';
  }
  return arabicUi
      ? '${seconds ~/ 3600} ساعة و${(seconds % 3600) ~/ 60} دقيقة'
      : '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
}

String arm32LaunchDiagnosisText(
  Map<String, Object?> values, {
  required bool arabicUi,
}) {
  final proot = values['prootReady'] == true;
  final tmp = values['prootTmpWritable'] == true;
  final env = values['guestEnvReady'] == true;
  final loader =
      values['guestLoaderReady'] == true &&
      values['guestLoaderViaLibReady'] == true;
  final rootfs = values['rootfsPath']?.toString() ?? '?';
  final prootPath = values['prootPath']?.toString() ?? '?';
  final tmpPath = values['prootTmpPath']?.toString() ?? '?';
  final envPath = values['guestEnvPath']?.toString() ?? '?';
  final loaderPath =
      values['guestLoaderViaLibPath']?.toString() ??
      values['guestLoaderPath']?.toString() ??
      '?';
  return arabicUi
      ? 'تشخيص ARM32: RootFS=$rootfs\nPRoot=${proot ? 'جاهز' : 'مفقود'}: $prootPath\ntmp=${tmp ? 'قابل للكتابة' : 'غير صالح'}: $tmpPath\nenv=${env ? 'جاهز' : 'مفقود'}: $envPath\nld-linux=${loader ? 'جاهز' : 'مفقود'}: $loaderPath'
      : 'ARM32 diagnosis: RootFS=$rootfs\nPRoot=${proot ? 'ready' : 'missing'}: $prootPath\ntmp=${tmp ? 'writable' : 'invalid'}: $tmpPath\nenv=${env ? 'ready' : 'missing'}: $envPath\nld-linux=${loader ? 'ready' : 'missing'}: $loaderPath';
}

/// Builds PRoot arguments without overriding Arch's usr-merge links. The
/// dedicated temporary directory is supplied before PRoot performs its F2FS
/// probe. The guest executable is launched directly so PRoot can translate
/// its PT_INTERP dynamic-loader lookup inside the guest rootfs.
List<String> buildArchProotArguments({
  required String rootfsPath,
  required String prootTmpPath,
  required String storagePath,
  required String abi,
  bool bindDeviceStorage = true,
}) {
  return <String>[
    '-0',
    '-r',
    rootfsPath,
    '-b',
    '$prootTmpPath:/tmp',
    '-b',
    '/dev',
    '-b',
    '/proc',
    '-b',
    '/sys',
    if (bindDeviceStorage) ...<String>['-b', '$storagePath:/sdcard'],
    '-w',
    '/root',
    '/usr/bin/env',
    '-i',
    'HOME=/root',
    'TERM=xterm-256color',
    'LANG=C.UTF-8',
    'LC_ALL=C.UTF-8',
    'PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/sbin:/bin',
    '/bin/bash',
    '--login',
  ];
}
