import 'package:arch_terminal/terminal/ai_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes only supported user-selectable providers', () {
    expect(
      AiProvider.fromWireName('google_ai_studio'),
      AiProvider.googleAiStudio,
    );
    expect(AiProvider.fromWireName('openrouter'), AiProvider.openRouter);
    expect(AiProvider.fromWireName('grok'), AiProvider.grok);
    expect(AiProvider.fromWireName('unknown'), isNull);
  });

  test('requires provider key and explicit selected-output consent before AI is ready', () {
    const missingConsent = AiSettings(
      provider: AiProvider.openRouter,
      hasApiKey: true,
      consentToSendSelectedOutput: false,
    );
    const ready = AiSettings(
      provider: AiProvider.openRouter,
      hasApiKey: true,
      consentToSendSelectedOutput: true,
    );

    expect(missingConsent.isReady, isFalse);
    expect(ready.isReady, isTrue);
  });

  test(
    'uses review-each-command by default and recognizes strict typed approval',
    () {
      const settings = AiSettings(
        provider: AiProvider.grok,
        hasApiKey: true,
        consentToSendSelectedOutput: true,
      );

      expect(settings.approvalMode, AiApprovalMode.reviewEach);
      expect(
        AiApprovalMode.fromWireName('typed_every_command'),
        AiApprovalMode.typedForEveryCommand,
      );
      expect(
        AiApprovalMode.fromWireName('execute_safe_automatically'),
        AiApprovalMode.executeSafeAutomatically,
      );
      expect(AiApprovalMode.fromWireName('unknown'), AiApprovalMode.reviewEach);
    },
  );

  test('keeps a local blocked-command policy alongside the execution mode', () {
    const settings = AiSettings(
      provider: AiProvider.googleAiStudio,
      hasApiKey: true,
      consentToSendSelectedOutput: true,
      approvalMode: AiApprovalMode.executeSafeAutomatically,
      blockedCommandPatterns: <String>['pacman -syy', 'rm -rf'],
    );

    expect(settings.approvalMode, AiApprovalMode.executeSafeAutomatically);
    expect(settings.blockedCommandPatterns, contains('pacman -syy'));
  });

  test(
    'defaults workflow progress to manual and recognizes automatic progress',
    () {
      const settings = AiSettings(
        provider: AiProvider.googleAiStudio,
        hasApiKey: true,
        consentToSendSelectedOutput: true,
      );

      expect(settings.workflowAdvanceMode, AiWorkflowAdvanceMode.manual);
      expect(
        AiWorkflowAdvanceMode.fromWireName('automatic'),
        AiWorkflowAdvanceMode.automatic,
      );
      expect(
        AiWorkflowAdvanceMode.fromWireName('unexpected'),
        AiWorkflowAdvanceMode.manual,
      );
    },
  );

  test('parses narrow local policy instructions from Arabic chat', () {
    expect(
      parseAiPolicyChatInstruction('وافق دائماً على الأوامر الآمنة')?.kind,
      AiPolicyChangeKind.useSafeAutomatic,
    );
    final block = parseAiPolicyChatInstruction('لا تنفذ pacman -Syy');
    expect(block?.kind, AiPolicyChangeKind.addBlock);
    expect(block?.pattern, 'pacman -syy');
    expect(
      parseAiPolicyChatInstruction('راجع كل أمر')?.kind,
      AiPolicyChangeKind.useReviewEach,
    );
  });
}
