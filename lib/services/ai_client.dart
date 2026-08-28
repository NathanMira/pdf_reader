import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class AiException implements Exception {
  AiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiStreamChunk {
  const AiStreamChunk({
    this.reasoningDelta,
    this.outputDelta,
    this.responseId,
    this.done = false,
  });

  final String? reasoningDelta;
  final String? outputDelta;
  final String? responseId;
  final bool done;
}

class AiAskRequest {
  const AiAskRequest({
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    required this.input,
    this.previousResponseId,
    this.enableThinking = true,
    this.reasoningEffort = 'low',
  });

  final String apiKey;
  final String baseUrl;
  final String model;
  final Object input;
  final String? previousResponseId;
  final bool enableThinking;
  final String reasoningEffort;
}

/// OpenAI-compatible Responses API client for DashScope (Qwen).
class AiClient {
  AiClient({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  final http.Client _httpClient;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) _httpClient.close();
  }

  Stream<AiStreamChunk> streamAsk(AiAskRequest request, {Duration timeout = const Duration(seconds: 90)}) async* {
    if (request.apiKey.isEmpty) {
      throw AiException('尚未配置 DashScope API Key');
    }

    final uri = _responsesUri(request.baseUrl);
    final body = <String, dynamic>{
      'model': request.model,
      'input': request.input,
      'stream': true,
      'enable_thinking': request.enableThinking,
    };
    if (request.enableThinking) {
      body['reasoning'] = {'effort': request.reasoningEffort};
    }
    final previous = request.previousResponseId?.trim();
    if (previous != null && previous.isNotEmpty) {
      body['previous_response_id'] = previous;
    }

    final httpRequest = http.Request('POST', uri)
      ..headers.addAll({
        'Authorization': 'Bearer ${request.apiKey}',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = jsonEncode(body);

    late final http.StreamedResponse response;
    try {
      response = await _httpClient.send(httpRequest).timeout(timeout);
    } on TimeoutException {
      throw AiException('请求超时，请稍后重试');
    } on http.ClientException catch (error) {
      throw AiException('网络错误：${error.message}');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final raw = await response.stream.bytesToString();
      throw AiException(_errorMessage(response.statusCode, raw));
    }

    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.contains('event-stream') && !contentType.contains('text/event')) {
      final raw = await response.stream.bytesToString();
      yield* Stream.fromIterable(_chunksFromCompletedJson(raw));
      return;
    }

    final decoder = SseBuffer();
    await for (final piece in response.stream.transform(utf8.decoder)) {
      for (final data in decoder.add(piece)) {
        if (data == '[DONE]') {
          yield const AiStreamChunk(done: true);
          return;
        }
        Map<String, dynamic> event;
        try {
          event = jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        final chunk = chunkFromSseEvent(event);
        if (chunk != null) yield chunk;
        if (chunk?.done == true) return;
      }
    }
    yield const AiStreamChunk(done: true);
  }

  static Uri _responsesUri(String baseUrl) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$trimmed/responses');
  }

  static String _errorMessage(int statusCode, String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is Map) {
        final error = json['error'];
        if (error is Map && error['message'] is String) {
          return error['message'] as String;
        }
        if (json['message'] is String) return json['message'] as String;
      }
    } catch (_) {}
    if (statusCode == 401 || statusCode == 403) {
      return 'API Key 无效或没有权限，请在设置中检查';
    }
    if (raw.trim().isEmpty) return '请求失败（HTTP $statusCode）';
    return '请求失败（HTTP $statusCode）：${raw.length > 240 ? raw.substring(0, 240) : raw}';
  }

  static Iterable<AiStreamChunk> _chunksFromCompletedJson(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic>) {
      throw AiException('无法解析模型响应');
    }
    if (json['error'] is Map) {
      final message = (json['error'] as Map)['message'];
      throw AiException(message is String ? message : '模型返回错误');
    }
    return parseCompletedResponse(json);
  }
}

class SseBuffer {
  String _buffer = '';

  Iterable<String> add(String chunk) sync* {
    _buffer += chunk.replaceAll('\r\n', '\n');
    while (true) {
      final index = _buffer.indexOf('\n\n');
      if (index < 0) break;
      final block = _buffer.substring(0, index);
      _buffer = _buffer.substring(index + 2);
      final data = _dataFromBlock(block);
      if (data != null) yield data;
    }
  }

  static String? _dataFromBlock(String block) {
    final lines = <String>[];
    for (final rawLine in block.split('\n')) {
      final line = rawLine.trimRight();
      if (line.startsWith('data:')) {
        lines.add(line.substring(5).trimLeft());
      }
    }
    if (lines.isEmpty) return null;
    return lines.join('\n');
  }
}

AiStreamChunk? chunkFromSseEvent(Map<String, dynamic> event) {
  final type = event['type'] as String? ?? '';
  switch (type) {
    case 'response.reasoning_text.delta':
    case 'response.reasoning_summary_text.delta':
      final delta = event['delta'] as String? ?? '';
      if (delta.isEmpty) return null;
      return AiStreamChunk(reasoningDelta: delta);
    case 'response.output_text.delta':
      final delta = event['delta'] as String? ?? '';
      if (delta.isEmpty) return null;
      return AiStreamChunk(outputDelta: delta);
    case 'response.completed':
      final response = event['response'];
      String? id;
      if (response is Map && response['id'] is String) {
        id = response['id'] as String;
      }
      return AiStreamChunk(responseId: id, done: true);
    case 'response.failed':
    case 'error':
      throw AiException(_sseErrorMessage(event));
    default:
      return null;
  }
}

List<AiStreamChunk> parseCompletedResponse(Map<String, dynamic> json) {
  final chunks = <AiStreamChunk>[];
  final output = json['output'];
  if (output is List) {
    for (final item in output) {
      if (item is! Map) continue;
      final type = item['type'] as String? ?? '';
      if (type == 'reasoning') {
        final summary = item['summary'];
        if (summary is List) {
          final text = summary
              .whereType<Map>()
              .map((part) => part['text'])
              .whereType<String>()
              .join('\n');
          if (text.isNotEmpty) chunks.add(AiStreamChunk(reasoningDelta: text));
        }
      } else if (type == 'message') {
        final content = item['content'];
        if (content is List) {
          final text = content
              .whereType<Map>()
              .map((part) => part['text'])
              .whereType<String>()
              .join();
          if (text.isNotEmpty) chunks.add(AiStreamChunk(outputDelta: text));
        }
      }
    }
  }
  final id = json['id'] as String?;
  chunks.add(AiStreamChunk(responseId: id, done: true));
  return chunks;
}

String _sseErrorMessage(Map<String, dynamic> event) {
  final error = event['error'];
  if (error is Map && error['message'] is String) {
    return error['message'] as String;
  }
  if (event['message'] is String) return event['message'] as String;
  return '模型请求失败';
}

List<Map<String, String>> buildPdfAskInput({
  required String documentName,
  required String quote,
  required String question,
}) {
  final quoteBlock = quote.trim();
  final questionBlock = question.trim();
  final user = StringBuffer();
  if (quoteBlock.isNotEmpty) {
    user
      ..writeln('【选中原文】')
      ..writeln(quoteBlock)
      ..writeln()
      ..writeln('【问题】')
      ..write(questionBlock);
  } else {
    user.write(questionBlock);
  }

  return [
    {
      'role': 'system',
      'content':
          '你是 PDF 阅读助手，正在帮助用户阅读《$documentName》。'
          '请基于用户提供的原文回答，使用简体中文，简洁准确。'
          '不要编造原文没有的信息；如果原文不足以回答，请明确说明。',
    },
    {
      'role': 'user',
      'content': user.toString(),
    },
  ];
}
