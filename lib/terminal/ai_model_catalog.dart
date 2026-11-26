import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ai_settings.dart';

enum AiModelPriceTier { free, economic, paid }

enum AiModelTestState { untested, working, failed }

class AiModelInfo {
  const AiModelInfo({
    required this.provider,
    required this.id,
    required this.name,
    required this.priceTier,
    required this.priceAvailable,
    required this.inputUsdPerMillion,
    required this.outputUsdPerMillion,
    this.testState = AiModelTestState.untested,
    this.lastTestedAt,
    this.testMessage,
  });

  final AiProvider provider;
  final String id;
  final String name;
  final AiModelPriceTier priceTier;
  final bool priceAvailable;
  final double? inputUsdPerMillion;
  final double? outputUsdPerMillion;
  final AiModelTestState testState;
  final DateTime? lastTestedAt;
  final String? testMessage;

  AiModelInfo tested({required bool working, required String message}) =>
      AiModelInfo(
        provider: provider,
        id: id,
        name: name,
        priceTier: priceTier,
        priceAvailable: priceAvailable,
        inputUsdPerMillion: inputUsdPerMillion,
        outputUsdPerMillion: outputUsdPerMillion,
        testState: working ? AiModelTestState.working : AiModelTestState.failed,
        lastTestedAt: DateTime.now(),
        testMessage: message,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'provider': provider.wireName,
    'id': id,
    'name': name,
    'priceTier': priceTier.name,
    'priceAvailable': priceAvailable,
    'inputUsdPerMillion': inputUsdPerMillion,
    'outputUsdPerMillion': outputUsdPerMillion,
    'testState': testState.name,
    'lastTestedAt': lastTestedAt?.toUtc().toIso8601String(),
    'testMessage': testMessage,
  };

  static AiModelInfo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final provider = AiProvider.fromWireName(raw['provider']?.toString());
    final tier = AiModelPriceTier.values.cast<AiModelPriceTier?>().firstWhere(
      (item) => item?.name == raw['priceTier'],
      orElse: () => AiModelPriceTier.paid,
    );
    final testState = AiModelTestState.values
        .cast<AiModelTestState?>()
        .firstWhere(
          (item) => item?.name == raw['testState'],
          orElse: () => AiModelTestState.untested,
        );
    final id = raw['id']?.toString().trim();
    final name = raw['name']?.toString().trim();
    if (provider == null ||
        id == null ||
        id.isEmpty ||
        name == null ||
        name.isEmpty) {
      return null;
    }
    return AiModelInfo(
      provider: provider,
      id: id,
      name: name,
      priceTier: tier ?? AiModelPriceTier.paid,
      priceAvailable: raw['priceAvailable'] == true,
      inputUsdPerMillion: (raw['inputUsdPerMillion'] as num?)?.toDouble(),
      outputUsdPerMillion: (raw['outputUsdPerMillion'] as num?)?.toDouble(),
      testState: testState ?? AiModelTestState.untested,
      lastTestedAt: DateTime.tryParse(raw['lastTestedAt']?.toString() ?? '')
          ?.toLocal(),
      testMessage: raw['testMessage']?.toString(),
    );
  }
}

AiModelPriceTier tierForPrices({
  required double? inputUsdPerMillion,
  required double? outputUsdPerMillion,
}) {
  if (inputUsdPerMillion == null || outputUsdPerMillion == null) {
    return AiModelPriceTier.paid;
  }
  if (inputUsdPerMillion == 0 && outputUsdPerMillion == 0) {
    return AiModelPriceTier.free;
  }
  return (inputUsdPerMillion + outputUsdPerMillion) / 2 <= 5
      ? AiModelPriceTier.economic
      : AiModelPriceTier.paid;
}

class AiModelCatalogStore {
  AiModelCatalogStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          FlutterSecureStorage(
            aOptions: AndroidOptions(migrateWithBackup: true),
          );

  static const _modelsKey = 'arch_terminal.ai.model_catalog.v1';
  static const _selectedKey = 'arch_terminal.ai.selected_model.v1';
  final FlutterSecureStorage _storage;

  Future<List<AiModelInfo>> load() async {
    try {
      final raw = await _storage.read(key: _modelsKey);
      final decoded = raw == null ? null : jsonDecode(raw);
      return decoded is List
          ? decoded.map(AiModelInfo.fromJson).whereType<AiModelInfo>().toList()
          : <AiModelInfo>[];
    } catch (_) {
      return <AiModelInfo>[];
    }
  }

  Future<void> save(List<AiModelInfo> models) => _storage.write(
    key: _modelsKey,
    value: jsonEncode(models.map((model) => model.toJson()).toList()),
  );
  Future<String?> selectedModelId() => _storage.read(key: _selectedKey);
  Future<void> selectModel(String id) =>
      _storage.write(key: _selectedKey, value: id);
}

class AiModelCatalogClient {
  AiModelCatalogClient({HttpClient Function()? httpClientFactory})
    : _httpClientFactory = httpClientFactory ?? HttpClient.new;
  final HttpClient Function() _httpClientFactory;

  Future<List<AiModelInfo>> discover(AiCredentials credentials) async {
    final client = _httpClientFactory();
    try {
      return await switch (credentials.provider) {
        AiProvider.googleAiStudio => _google(client, credentials.apiKey),
        AiProvider.openRouter => _openRouter(client, credentials.apiKey),
        AiProvider.grok => _grok(client, credentials.apiKey),
      };
    } finally {
      client.close(force: true);
    }
  }

  Future<List<AiModelInfo>> _google(HttpClient client, String key) async {
    final json = await _getJson(
      client,
      Uri.https(
        'generativelanguage.googleapis.com',
        '/v1beta/models',
        <String, String>{'key': key},
      ),
      const <String, String>{},
    );
    final values = json['models'];
    if (values is! List) return <AiModelInfo>[];
    return values
        .whereType<Map>()
        .where(
          (item) =>
              (item['supportedGenerationMethods'] as List?)?.contains(
                'generateContent',
              ) ==
              true,
        )
        .map((item) {
          final id =
              item['baseModelId']?.toString() ??
              item['name']?.toString().replaceFirst('models/', '') ??
              '';
          return AiModelInfo(
            provider: AiProvider.googleAiStudio,
            id: id,
            name: item['displayName']?.toString() ?? id,
            priceTier: AiModelPriceTier.paid,
            priceAvailable: false,
            inputUsdPerMillion: null,
            outputUsdPerMillion: null,
          );
        })
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  Future<List<AiModelInfo>> _openRouter(HttpClient client, String key) async {
    final json = await _getJson(
      client,
      Uri.parse('https://openrouter.ai/api/v1/models?output_modality=text'),
      <String, String>{'Authorization': 'Bearer $key'},
    );
    final values = json['data'];
    if (values is! List) return <AiModelInfo>[];
    return values
        .whereType<Map>()
        .map((item) {
          final pricing = item['pricing'] as Map?;
          final input = double.tryParse(pricing?['prompt']?.toString() ?? '');
          final output = double.tryParse(
            pricing?['completion']?.toString() ?? '',
          );
          final inputPerMillion = input == null ? null : input * 1000000;
          final outputPerMillion = output == null ? null : output * 1000000;
          return AiModelInfo(
            provider: AiProvider.openRouter,
            id: item['id']?.toString() ?? '',
            name: item['name']?.toString() ?? item['id']?.toString() ?? '',
            priceTier: tierForPrices(
              inputUsdPerMillion: inputPerMillion,
              outputUsdPerMillion: outputPerMillion,
            ),
            priceAvailable: inputPerMillion != null && outputPerMillion != null,
            inputUsdPerMillion: inputPerMillion,
            outputUsdPerMillion: outputPerMillion,
          );
        })
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  Future<List<AiModelInfo>> _grok(HttpClient client, String key) async {
    final json = await _getJson(
      client,
      Uri.parse('https://api.x.ai/v1/language-models'),
      <String, String>{'Authorization': 'Bearer $key'},
    );
    final values = json['models'];
    if (values is! List) return <AiModelInfo>[];
    return values
        .whereType<Map>()
        .where(
          (item) =>
              (item['output_modalities'] as List?)?.contains('text') == true,
        )
        .map((item) {
          // xAI reports USD cents per 100 million tokens; convert to USD per million.
          final inputCents = (item['prompt_text_token_price'] as num?)
              ?.toDouble();
          final outputCents = (item['completion_text_token_price'] as num?)
              ?.toDouble();
          final inputPerMillion = inputCents == null
              ? null
              : inputCents / 10000;
          final outputPerMillion = outputCents == null
              ? null
              : outputCents / 10000;
          return AiModelInfo(
            provider: AiProvider.grok,
            id: item['id']?.toString() ?? '',
            name: item['id']?.toString() ?? '',
            priceTier: tierForPrices(
              inputUsdPerMillion: inputPerMillion,
              outputUsdPerMillion: outputPerMillion,
            ),
            priceAvailable: inputPerMillion != null && outputPerMillion != null,
            inputUsdPerMillion: inputPerMillion,
            outputUsdPerMillion: outputPerMillion,
          );
        })
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  Future<Map<String, dynamic>> _getJson(
    HttpClient client,
    Uri uri,
    Map<String, String> headers,
  ) async {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 20));
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 30));
    final raw = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'فشل اكتشاف النماذج (${response.statusCode}). تحقق من المفتاح أو المزود.',
        uri: uri,
      );
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const HttpException('استجابة كتالوج النماذج غير صالحة.');
    }
    return decoded;
  }
}
