import 'package:flutter/material.dart';

import '../services/library_store.dart';

Future<bool> showAiSettingsDialog(BuildContext context, LibraryStore store) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => _AiSettingsDialog(store: store),
  );
  return result == true;
}

class _AiSettingsDialog extends StatefulWidget {
  const _AiSettingsDialog({required this.store});

  final LibraryStore store;

  @override
  State<_AiSettingsDialog> createState() => _AiSettingsDialogState();
}

class _AiSettingsDialogState extends State<_AiSettingsDialog> {
  late final TextEditingController _keyController;
  late final TextEditingController _modelController;
  late final TextEditingController _baseUrlController;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(text: widget.store.effectiveAiApiKey);
    _modelController = TextEditingController(text: widget.store.aiModel);
    _baseUrlController = TextEditingController(text: widget.store.aiBaseUrl);
  }

  @override
  void dispose() {
    _keyController.dispose();
    _modelController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.store.saveAiSettings(
      apiKey: _keyController.text,
      model: _modelController.text,
      baseUrl: _baseUrlController.text,
    );
    if (mounted) Navigator.of(context).pop(widget.store.hasAiApiKey);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('AI 设置'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '默认读取项目里的 config/ai.json。这里的修改只覆盖本机当前值，不会写回配置文件。',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _keyController,
                obscureText: _obscure,
                autofocus: !widget.store.hasAiApiKey,
                decoration: InputDecoration(
                  labelText: 'DashScope API Key',
                  hintText: 'sk-...',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? '显示' : '隐藏',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _modelController,
                decoration: const InputDecoration(
                  labelText: '模型',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _baseUrlController,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
