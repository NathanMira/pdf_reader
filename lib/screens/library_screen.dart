import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/recent_document.dart';
import '../services/library_store.dart';
import '../utils/format.dart';
import 'reader_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.store});

  final LibraryStore store;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const _samplePdfUrl = 'https://mozilla.github.io/pdf.js/web/compressed.tracemonkey-pldi-09.pdf';

  bool _busy = false;

  LibraryStore get store => widget.store;

  Future<void> _openPickedFile() async {
    final file = await FilePicker.pickFile(
      dialogTitle: '选择 PDF 文件',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (file == null) return;

    setState(() => _busy = true);
    try {
      Uint8List? bytes;
      if (kIsWeb) {
        bytes = await file.readAsBytes();
      }
      final document = await store.importPickedFile(file);
      if (!mounted) return;
      await _openReader(document, bytes: bytes);
    } catch (error) {
      if (!mounted) return;
      _showError('无法打开文件：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openUrl({String? initial}) async {
    final controller = TextEditingController(text: initial ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('打开网络 PDF'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'https://example.com/file.pdf',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('打开')),
          ],
        );
      },
    );
    controller.dispose();
    if (result == null) return;

    final text = result.trim();
    if (text.isEmpty) return;
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
      _showError('请输入以 http 或 https 开头的有效链接');
      return;
    }

    setState(() => _busy = true);
    try {
      final document = await store.importUrl(uri);
      if (!mounted) return;
      await _openReader(document);
    } catch (error) {
      if (!mounted) return;
      _showError('无法打开链接：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRecent(RecentDocument document) async {
    setState(() => _busy = true);
    try {
      final readable = await store.isReadable(document);
      if (!readable) {
        await store.remove(document);
        if (!mounted) return;
        _showError('原文件已不存在，已从最近阅读中移除');
        return;
      }
      final updated = document.copyWith(openedAt: DateTime.now());
      await store.upsert(updated);
      if (!mounted) return;
      await _openReader(updated);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openReader(RecentDocument document, {Uint8List? bytes}) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderScreen(store: store, document: document, bytes: bytes),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('PDF阅读'),
            actions: [
              IconButton(
                tooltip: store.nightMode ? '关闭夜间模式' : '开启夜间模式',
                onPressed: () => store.setNightMode(!store.nightMode),
                icon: Icon(store.nightMode ? Icons.dark_mode : Icons.dark_mode_outlined),
              ),
            ],
          ),
          body: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  Text('打开文档', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _ActionCard(
                        icon: Icons.folder_open,
                        title: '打开文件',
                        subtitle: '从本地选择 PDF',
                        onTap: _busy ? null : _openPickedFile,
                      ),
                      _ActionCard(
                        icon: Icons.link,
                        title: '打开链接',
                        subtitle: '阅读网络 PDF',
                        onTap: _busy ? null : () => _openUrl(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Text('最近阅读', style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      if (store.documents.isNotEmpty)
                        Text('${store.documents.length} 份', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (store.documents.isEmpty)
                    _EmptyLibrary(
                      color: scheme.surfaceContainerHighest,
                      onOpenSample: _busy ? null : () => _openUrl(initial: _samplePdfUrl),
                    )
                  else
                    ...store.documents.map(
                      (document) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _RecentTile(
                          document: document,
                          onOpen: _busy ? null : () => _openRecent(document),
                          onDelete: _busy ? null : () => store.remove(document),
                        ),
                      ),
                    ),
                ],
              ),
              if (_busy)
                const ColoredBox(
                  color: Color(0x33000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 220,
      child: Material(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, size: 32, color: scheme.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.color, required this.onOpenSample});

  final Color color;
  final VoidCallback? onOpenSample;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          const Icon(Icons.menu_book_outlined, size: 48),
          const SizedBox(height: 12),
          const Text('还没有阅读记录'),
          const SizedBox(height: 4),
          const Text('打开本地 PDF，或从网络链接开始阅读'),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onOpenSample,
            icon: const Icon(Icons.science_outlined),
            label: const Text('打开示例文档'),
          ),
        ],
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({
    required this.document,
    required this.onOpen,
    required this.onDelete,
  });

  final RecentDocument document;
  final VoidCallback? onOpen;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final size = formatBytes(document.sizeBytes);
    final meta = [
      formatOpenedAt(document.openedAt),
      formatPageProgress(document.lastPage, document.pageCount),
      if (size.isNotEmpty) size,
    ].join(' · ');

    return Dismissible(
      key: ValueKey(document.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete?.call(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.error, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: ListTile(
        onTap: onOpen,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        leading: CircleAvatar(
          child: Icon(document.isUrl ? Icons.cloud_outlined : Icons.picture_as_pdf_outlined),
        ),
        title: Text(document.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(meta, maxLines: 2),
        trailing: IconButton(
          tooltip: '删除',
          onPressed: onDelete,
          icon: const Icon(Icons.close),
        ),
      ),
    );
  }
}
