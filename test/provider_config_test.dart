import 'package:flutter_test/flutter_test.dart';
import 'package:openchat/src/models/provider_config.dart';

void main() {
  test('initial provider config defaults to the OpenAI preset', () {
    final ProviderConfig config = ProviderConfig.initial();

    expect(config.presetId, 'openai');
    expect(config.label, 'OpenAI');
    expect(config.baseUrl, 'https://api.openai.com/v1');
  });

  test('fromJson uses the preset label when one is not stored', () {
    final ProviderConfig config = ProviderConfig.fromJson(<String, dynamic>{
      'presetId': 'groq',
      'baseUrl': 'https://api.groq.com/openai/v1',
      'apiKey': 'test-key',
      'model': 'llama-3.3-70b-versatile',
      'systemPrompt': '',
      'temperature': 1.0,
      'streamResponses': true,
    });

    expect(config.label, 'Groq');
  });
}
