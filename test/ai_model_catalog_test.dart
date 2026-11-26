import 'package:arch_terminal/terminal/ai_model_catalog.dart';
import 'package:arch_terminal/terminal/ai_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classifies a zero-price model as free', () {
    expect(
      tierForPrices(inputUsdPerMillion: 0, outputUsdPerMillion: 0),
      AiModelPriceTier.free,
    );
  });

  test(
    'classifies low known prices as economic and unknown prices as paid',
    () {
      expect(
        tierForPrices(inputUsdPerMillion: 1.25, outputUsdPerMillion: 2.5),
        AiModelPriceTier.economic,
      );
      expect(
        tierForPrices(inputUsdPerMillion: null, outputUsdPerMillion: null),
        AiModelPriceTier.paid,
      );
    },
  );

  test('keeps discovery test result and time in the model record', () {
    const model = AiModelInfo(
      provider: AiProvider.grok,
      id: 'grok-test',
      name: 'Grok Test',
      priceTier: AiModelPriceTier.economic,
      priceAvailable: true,
      inputUsdPerMillion: 1,
      outputUsdPerMillion: 2,
    );
    final tested = model.tested(working: true, message: 'OK');
    expect(tested.testState, AiModelTestState.working);
    expect(tested.lastTestedAt, isNotNull);
  });

  test('restores model metadata and recorded test status from JSON', () {
    const model = AiModelInfo(
      provider: AiProvider.openRouter,
      id: 'provider/model',
      name: 'Provider Model',
      priceTier: AiModelPriceTier.free,
      priceAvailable: true,
      inputUsdPerMillion: 0,
      outputUsdPerMillion: 0,
    );
    final restored = AiModelInfo.fromJson(
      model.tested(working: true, message: 'OK').toJson(),
    );
    expect(restored?.id, 'provider/model');
    expect(restored?.priceTier, AiModelPriceTier.free);
    expect(restored?.testState, AiModelTestState.working);
  });
}
