import 'dart:convert';

import 'package:flutter/services.dart';

class AiConfig {
  const AiConfig({
    required this.apiKey,
    required this.model,
    required this.baseUrl,
    this.enableThinking = true,
    this.reasoningEffort = 'low',
  });

  static const assetPath = 'config/ai.json';

  static const defaults = AiConfig(
    apiKey: '',
    model: 'qwen3.8-flash',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
  );

  final String apiKey;
  final String model;
  final String baseUrl;
  final bool enableThinking;
  final String reasoningEffort;

  bool get hasApiKey => apiKey.isNotEmpty;

  factory AiConfig.fromJson(Map<String, dynamic> json) {
    final effort = (json['reasoning_effort'] ?? json['reasoningEffort'] ?? defaults.reasoningEffort)
        .toString()
        .trim();
    return AiConfig(
      apiKey: _string(json, const ['api_key', 'apiKey']),
      model: _string(json, const ['model'], fallback: defaults.model),
      baseUrl: _string(json, const ['base_url', 'baseUrl'], fallback: defaults.baseUrl),
      enableThinking: json['enable_thinking'] as bool? ?? json['enableThinking'] as bool? ?? true,
      reasoningEffort: effort.isEmpty ? defaults.reasoningEffort : effort,
    );
  }

  Map<String, dynamic> toJson() => {
    'api_key': apiKey,
    'model': model,
    'base_url': baseUrl,
    'enable_thinking': enableThinking,
    'reasoning_effort': reasoningEffort,
  };

  static Future<AiConfig> load() async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return AiConfig.fromJson(decoded);
      if (decoded is Map) return AiConfig.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {}
    return defaults;
  }

  static String _string(Map<String, dynamic> json, List<String> keys, {String fallback = ''}) {
    for (final key in keys) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return fallback;
  }
}
