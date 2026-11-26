import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum AiProvider {
  googleAiStudio('google_ai_studio', 'Google AI Studio'),
  openRouter('openrouter', 'OpenRouter'),
  grok('grok', 'Grok');

  const AiProvider(this.wireName, this.label);
  final String wireName;
  final String label;

  static AiProvider? fromWireName(String? value) {
    for (final provider in AiProvider.values) {
      if (provider.wireName == value) return provider;
    }
    return null;
  }
}

enum AiApprovalMode {
  reviewEach('review_each'),
  typedForEveryCommand('typed_every_command'),
  executeSafeAutomatically('execute_safe_automatically');

  const AiApprovalMode(this.wireName);
  final String wireName;

  static AiApprovalMode fromWireName(String? value) {
    for (final mode in AiApprovalMode.values) {
      if (mode.wireName == value) return mode;
    }
    return AiApprovalMode.reviewEach;
  }
}

enum AiWorkflowAdvanceMode {
  manual('manual'),
  automatic('automatic');

  const AiWorkflowAdvanceMode(this.wireName);
  final String wireName;

  static AiWorkflowAdvanceMode fromWireName(String? value) {
    for (final mode in AiWorkflowAdvanceMode.values) {
      if (mode.wireName == value) return mode;
    }
    return AiWorkflowAdvanceMode.manual;
  }
}

enum AiPolicyChangeKind {
  useSafeAutomatic,
  useReviewEach,
  useTypedEvery,
  addBlock,
  removeBlock,
}

class AiPolicyChange {
  const AiPolicyChange(this.kind, {this.pattern});
  final AiPolicyChangeKind kind;
  final String? pattern;
}

/// Parses only narrow local policy instructions. A separate explicit reply is
/// required before any returned change is saved.
AiPolicyChange? parseAiPolicyChatInstruction(String raw) {
  final value = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (RegExp(
    r'(وافق.*دائم|نف.?ذ.*تلقائ|auto.?approve|always.?approve|auto.?run)',
  ).hasMatch(value)) {
    return const AiPolicyChange(AiPolicyChangeKind.useSafeAutomatic);
  }
  if (RegExp(r'(راجع.*كل|مراجعة.*كل|review.?each)').hasMatch(value)) {
    return const AiPolicyChange(AiPolicyChangeKind.useReviewEach);
  }
  if (RegExp(r'(execute.*دائم|اكتب.*execute|type.?execute)').hasMatch(value)) {
    return const AiPolicyChange(AiPolicyChangeKind.useTypedEvery);
  }
  final block = RegExp(r'(?:لا\s+تنف.?ذ|امنع|احظر|block)\s+(.+)')
      .firstMatch(value);
  if (block != null) {
    final pattern = block.group(1)?.trim();
    if (pattern != null && pattern.isNotEmpty) {
      return AiPolicyChange(AiPolicyChangeKind.addBlock, pattern: pattern);
    }
  }
  final remove = RegExp(r'(?:اسمح\s+ب|ارفع\s+الحظر\s+عن|unblock)\s+(.+)')
      .firstMatch(value);
  if (remove != null) {
    final pattern = remove.group(1)?.trim();
    if (pattern != null && pattern.isNotEmpty) {
      return AiPolicyChange(AiPolicyChangeKind.removeBlock, pattern: pattern);
    }
  }
  return null;
}

class AiSettings {
  const AiSettings({
    required this.provider,
    required this.hasApiKey,
    required this.consentToSendSelectedOutput,
    this.approvalMode = AiApprovalMode.reviewEach,
    this.blockedCommandPatterns = const <String>[],
    this.workflowAdvanceMode = AiWorkflowAdvanceMode.manual,
  });

  final AiProvider? provider;
  final bool hasApiKey;
  final bool consentToSendSelectedOutput;
  final AiApprovalMode approvalMode;
  final List<String> blockedCommandPatterns;
  final AiWorkflowAdvanceMode workflowAdvanceMode;

  bool get isReady =>
      provider != null && hasApiKey && consentToSendSelectedOutput;
}

class AiCredentials {
  const AiCredentials({required this.provider, required this.apiKey});
  final AiProvider provider;
  final String apiKey;
}

/// Stores only user-entered credentials on the device. It never contacts a
/// provider; network access is introduced separately after the user enables it.
class AiSettingsStore {
  AiSettingsStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          FlutterSecureStorage(
            aOptions: AndroidOptions(migrateWithBackup: true),
          );

  static const _providerKey = 'arch_terminal.ai.provider';
  static const _consentKey = 'arch_terminal.ai.selected_output_consent';
  static const _approvalModeKey = 'arch_terminal.ai.approval_mode';
  static const _blockedCommandPatternsKey =
      'arch_terminal.ai.blocked_command_patterns';
  static const _workflowAdvanceModeKey =
      'arch_terminal.ai.workflow_advance_mode';
  final FlutterSecureStorage _storage;

  Future<AiSettings> load() async {
    final provider = AiProvider.fromWireName(
      await _storage.read(key: _providerKey),
    );
    final key = provider == null
        ? null
        : await _storage.read(key: _apiKeyStorageKey(provider));
    final consent = await _storage.read(key: _consentKey) == 'true';
    final approvalMode = AiApprovalMode.fromWireName(
      await _storage.read(key: _approvalModeKey),
    );
    final blockedPatterns = _decodePatterns(
      await _storage.read(key: _blockedCommandPatternsKey),
    );
    final workflowAdvanceMode = AiWorkflowAdvanceMode.fromWireName(
      await _storage.read(key: _workflowAdvanceModeKey),
    );
    return AiSettings(
      provider: provider,
      hasApiKey: key?.trim().isNotEmpty == true,
      consentToSendSelectedOutput: consent,
      approvalMode: approvalMode,
      blockedCommandPatterns: blockedPatterns,
      workflowAdvanceMode: workflowAdvanceMode,
    );
  }

  Future<AiCredentials?> readCredentials() async {
    final provider = AiProvider.fromWireName(
      await _storage.read(key: _providerKey),
    );
    if (provider == null) return null;
    final apiKey = await _storage.read(key: _apiKeyStorageKey(provider));
    if (apiKey == null || apiKey.trim().isEmpty) return null;
    final consent = await _storage.read(key: _consentKey) == 'true';
    return consent
        ? AiCredentials(provider: provider, apiKey: apiKey.trim())
        : null;
  }

  Future<void> save({
    required AiProvider provider,
    required String apiKey,
    required bool consentToSendSelectedOutput,
    AiApprovalMode approvalMode = AiApprovalMode.reviewEach,
    List<String> blockedCommandPatterns = const <String>[],
    AiWorkflowAdvanceMode workflowAdvanceMode = AiWorkflowAdvanceMode.manual,
  }) async {
    final normalized = apiKey.trim();
    if (normalized.isEmpty) throw ArgumentError('An API key is required.');
    await _storage.write(key: _providerKey, value: provider.wireName);
    await _storage.write(key: _apiKeyStorageKey(provider), value: normalized);
    await _storage.write(
      key: _consentKey,
      value: consentToSendSelectedOutput.toString(),
    );
    await _storage.write(key: _approvalModeKey, value: approvalMode.wireName);
    await _storage.write(
      key: _blockedCommandPatternsKey,
      value: _encodePatterns(blockedCommandPatterns),
    );
    await _storage.write(
      key: _workflowAdvanceModeKey,
      value: workflowAdvanceMode.wireName,
    );
  }

  Future<void> deleteCurrentKey() async {
    final provider = AiProvider.fromWireName(
      await _storage.read(key: _providerKey),
    );
    if (provider != null) {
      await _storage.delete(key: _apiKeyStorageKey(provider));
    }
    await _storage.delete(key: _consentKey);
    await _storage.delete(key: _approvalModeKey);
    await _storage.delete(key: _blockedCommandPatternsKey);
    await _storage.delete(key: _workflowAdvanceModeKey);
  }

  Future<void> saveExecutionPolicy({
    required AiApprovalMode approvalMode,
    required List<String> blockedCommandPatterns,
    required AiWorkflowAdvanceMode workflowAdvanceMode,
  }) async {
    await _storage.write(key: _approvalModeKey, value: approvalMode.wireName);
    await _storage.write(
      key: _blockedCommandPatternsKey,
      value: _encodePatterns(blockedCommandPatterns),
    );
    await _storage.write(
      key: _workflowAdvanceModeKey,
      value: workflowAdvanceMode.wireName,
    );
  }

  static String _apiKeyStorageKey(AiProvider provider) =>
      'arch_terminal.ai.key.${provider.wireName}';

  static List<String> _decodePatterns(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <String>[];
    return raw
        .split('\n')
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .take(20)
        .toList();
  }

  static String _encodePatterns(List<String> patterns) => patterns
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .take(20)
      .join('\n');
}
