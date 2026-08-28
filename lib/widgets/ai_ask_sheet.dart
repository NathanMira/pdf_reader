import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ai_client.dart';
import '../services/library_store.dart';
import 'ai_settings_dialog.dart';

Future<void> showAiAskSheet({
  required BuildContext context,
  required LibraryStore store,
  required String documentName,
  String quote = '',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.78,
          child: AiAskSheet(
            store: store,
            documentName: documentName,
            quote: quote,
          ),
        ),
      );
    },
  );
}

class AiAskSheet extends StatefulWidget {
  const AiAskSheet({
    super.key,
    required this.store,
    required this.documentName,
    this.quote = '',
  });

  final LibraryStore store;
  final String documentName;
  final String quote;

  @override
  State<AiAskSheet> createState() => _AiAskSheetState();
}

class _AiAskSheetState extends State<AiAskSheet> {
  static const _quickActions = <(String, String)>[
    ('解释', '请解释这段原文的含义，并补充必要背景。'),
    ('翻译', '请把这段原文翻译成通顺的简体中文。如果已经是中文，请翻译成英文。'),
    ('总结', '请用条目总结这段原文的要点。'),
    ('概念', '请列出这段原文中的关键概念，并各用一句话说明。'),
  ];

  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <_ChatMessage>[];
  final _client = AiClient();

  String? _previousResponseId;
  bool _sending = false;
  bool _quoteExpanded = false;

  LibraryStore get store => widget.store;
  String get quote => widget.quote.trim();

  @override
  void dispose() {
    _client.close();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _ensureApiKey() async {
    if (store.hasAiApiKey) return;
    await showAiSettingsDialog(context, store);
  }

  Future<void> _send(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || _sending) return;

    await _ensureApiKey();
    if (!mounted) return;
    if (!store.hasAiApiKey) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先配置 DashScope API Key')));
      return;
    }

    _inputController.clear();
    final isFollowUp = _previousResponseId != null;
    final userText = (!isFollowUp && quote.isNotEmpty) ? '基于选中原文：$trimmed' : trimmed;

    setState(() {
      _sending = true;
      _messages.add(_ChatMessage(role: _ChatRole.user, text: userText));
      _messages.add(_ChatMessage(role: _ChatRole.assistant, streaming: true));
    });
    _scrollToEnd();

    final input = isFollowUp
        ? trimmed
        : buildPdfAskInput(
            documentName: widget.documentName,
            quote: quote,
            question: trimmed,
          );

    try {
      final stream = _client.streamAsk(
        AiAskRequest(
          apiKey: store.effectiveAiApiKey,
          baseUrl: store.aiBaseUrl,
          model: store.aiModel,
          input: input,
          previousResponseId: _previousResponseId,
          enableThinking: store.aiEnableThinking,
          reasoningEffort: store.aiReasoningEffort,
        ),
      );
      await for (final chunk in stream) {
        if (!mounted) return;
        _applyChunk(chunk);
      }
    } catch (error) {
      if (!mounted) return;
      _fail(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          if (_messages.isNotEmpty && _messages.last.role == _ChatRole.assistant) {
            _messages.last.streaming = false;
            if (_messages.last.text.isEmpty && _messages.last.error == null) {
              _messages.last.error = '没有收到模型回复';
            }
          }
        });
      }
    }
  }

  void _applyChunk(AiStreamChunk chunk) {
    if (_messages.isEmpty || _messages.last.role != _ChatRole.assistant) return;
    final message = _messages.last;
    var changed = false;
    if (chunk.reasoningDelta != null && chunk.reasoningDelta!.isNotEmpty) {
      message.reasoning += chunk.reasoningDelta!;
      message.reasoningExpanded = true;
      changed = true;
    }
    if (chunk.outputDelta != null && chunk.outputDelta!.isNotEmpty) {
      message.text += chunk.outputDelta!;
      if (message.reasoning.isNotEmpty) message.reasoningExpanded = false;
      changed = true;
    }
    if (chunk.responseId != null && chunk.responseId!.isNotEmpty) {
      _previousResponseId = chunk.responseId;
    }
    if (changed) {
      setState(() {});
      _scrollToEnd();
    }
  }

  void _fail(String error) {
    if (_messages.isNotEmpty && _messages.last.role == _ChatRole.assistant) {
      _messages.last
        ..streaming = false
        ..error = error;
    } else {
      _messages.add(_ChatMessage(role: _ChatRole.assistant, error: error));
    }
    setState(() {});
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, color: scheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('问 AI', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                tooltip: 'AI 设置',
                onPressed: () => showAiSettingsDialog(context, store),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
        ),
        if (quote.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _QuoteCard(
              quote: quote,
              expanded: _quoteExpanded,
              onToggle: () => setState(() => _quoteExpanded = !_quoteExpanded),
            ),
          ),
        if (_messages.isEmpty && quote.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in _quickActions)
                  ActionChip(
                    label: Text(action.$1),
                    onPressed: _sending ? null : () => _send(action.$2),
                  ),
              ],
            ),
          ),
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Text(
                    quote.isEmpty ? '输入问题，或先在 PDF 中选中一段文字' : '点上方快捷操作，或直接输入问题',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) => _MessageBubble(message: _messages[index]),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    hintText: quote.isEmpty ? '向 AI 提问' : '针对选中原文提问',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: _sending ? null : _send,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: '发送',
                onPressed: _sending ? null : () => _send(_inputController.text),
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _ChatRole { user, assistant }

class _ChatMessage {
  _ChatMessage({
    required this.role,
    this.text = '',
    this.streaming = false,
    this.error,
  });

  final _ChatRole role;
  String text;
  String reasoning = '';
  bool streaming;
  String? error;
  bool reasoningExpanded = false;
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({
    required this.quote,
    required this.expanded,
    required this.onToggle,
  });

  final String quote;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('选中原文', style: Theme.of(context).textTheme.labelMedium),
                  const Spacer(),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                quote,
                maxLines: expanded ? 12 : 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.role == _ChatRole.user;
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final color = isUser ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final error = message.error;

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.86),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isUser && message.reasoning.isNotEmpty)
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        initiallyExpanded: message.reasoningExpanded,
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          message.streaming && message.text.isEmpty ? '正在思考…' : '思考过程',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: SelectableText(
                              message.reasoning,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (error != null)
                    Text(error, style: TextStyle(color: scheme.error))
                  else if (message.text.isNotEmpty)
                    SelectableText(message.text)
                  else if (message.streaming)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  if (!isUser && message.text.isNotEmpty && !message.streaming)
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: '复制回答',
                        visualDensity: VisualDensity.compact,
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: message.text));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已复制回答')),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_outlined, size: 18),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
