import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_reader/config/ai_config.dart';
import 'package:pdf_reader/services/ai_client.dart';

void main() {
  test('SseBuffer 解析 data 事件', () {
    final buffer = SseBuffer();
    final events = buffer
        .add('data: {"type":"response.output_text.delta","delta":"你好"}\n\n')
        .toList();
    expect(events, ['{"type":"response.output_text.delta","delta":"你好"}']);
  });

  test('chunkFromSseEvent 解析思考与答案增量', () {
    final reasoning = chunkFromSseEvent({
      'type': 'response.reasoning_summary_text.delta',
      'delta': '先比较小数',
    });
    final output = chunkFromSseEvent({
      'type': 'response.output_text.delta',
      'delta': '9.9更大',
    });
    expect(reasoning?.reasoningDelta, '先比较小数');
    expect(output?.outputDelta, '9.9更大');
  });

  test('parseCompletedResponse 解析 reasoning + message', () {
    final chunks = parseCompletedResponse({
      'id': 'resp_1',
      'output': [
        {
          'type': 'reasoning',
          'summary': [
            {'type': 'summary_text', 'text': '思考摘要'},
          ],
        },
        {
          'type': 'message',
          'content': [
            {'type': 'output_text', 'text': '最终答案'},
          ],
        },
      ],
    });
    expect(chunks.map((c) => c.reasoningDelta).whereType<String>().toList(), ['思考摘要']);
    expect(chunks.map((c) => c.outputDelta).whereType<String>().toList(), ['最终答案']);
    expect(chunks.last.done, isTrue);
    expect(chunks.last.responseId, 'resp_1');
  });

  test('AiConfig.fromJson 读取配置文件字段', () {
    final config = AiConfig.fromJson({
      'api_key': 'sk-test',
      'model': 'qwen3.8-flash',
      'base_url': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      'enable_thinking': false,
      'reasoning_effort': 'medium',
    });
    expect(config.apiKey, 'sk-test');
    expect(config.model, 'qwen3.8-flash');
    expect(config.enableThinking, isFalse);
    expect(config.reasoningEffort, 'medium');
  });

  test('buildPdfAskInput 包含原文和问题', () {
    final input = buildPdfAskInput(
      documentName: 'demo.pdf',
      quote: '重力加速度 g',
      question: '这是什么意思？',
    );
    expect(input.first['role'], 'system');
    expect(input.last['content'], contains('重力加速度 g'));
    expect(input.last['content'], contains('这是什么意思？'));
  });
}
