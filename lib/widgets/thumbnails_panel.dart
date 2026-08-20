import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class ThumbnailsPanel extends StatelessWidget {
  const ThumbnailsPanel({
    super.key,
    required this.documentRef,
    required this.controller,
    required this.onItemSelected,
  });

  final PdfDocumentRef? documentRef;
  final PdfViewerController controller;
  final VoidCallback onItemSelected;

  @override
  Widget build(BuildContext context) {
    if (documentRef == null) {
      return const Center(child: Text('文档尚未加载'));
    }

    return PdfDocumentViewBuilder(
      documentRef: documentRef!,
      builder: (context, document) {
        final pageCount = document?.pages.length ?? 0;
        if (pageCount == 0) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: pageCount,
          itemBuilder: (context, index) {
            final pageNumber = index + 1;
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    if (controller.isReady) {
                      controller.goToPage(pageNumber: pageNumber, anchor: PdfPageAnchor.top);
                    }
                    onItemSelected();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 160,
                          child: PdfPageView(
                            document: document,
                            pageNumber: pageNumber,
                            alignment: Alignment.center,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('第 $pageNumber 页'),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
