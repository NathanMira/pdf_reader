import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class OutlinePanel extends StatelessWidget {
  const OutlinePanel({
    super.key,
    required this.outline,
    required this.controller,
    required this.onItemSelected,
  });

  final List<PdfOutlineNode>? outline;
  final PdfViewerController controller;
  final VoidCallback onItemSelected;

  @override
  Widget build(BuildContext context) {
    final items = _flatten(outline, 0).toList();
    if (items.isEmpty) {
      return const Center(child: Text('这份文档没有目录'));
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.only(left: 16.0 + item.level * 16, right: 16),
          title: Text(item.node.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () {
            if (item.node.dest != null && controller.isReady) {
              controller.goToDest(item.node.dest);
            }
            onItemSelected();
          },
        );
      },
    );
  }

  Iterable<({PdfOutlineNode node, int level})> _flatten(List<PdfOutlineNode>? nodes, int level) sync* {
    if (nodes == null) return;
    for (final node in nodes) {
      yield (node: node, level: level);
      yield* _flatten(node.children, level + 1);
    }
  }
}
