import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/recent_document.dart';
import '../services/library_store.dart';
import '../widgets/ai_ask_sheet.dart';
import '../widgets/ai_settings_dialog.dart';
import '../widgets/outline_panel.dart';
import '../widgets/password_dialog.dart';
import '../widgets/thumbnails_panel.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.store,
    required this.document,
    this.bytes,
  });

  final LibraryStore store;
  final RecentDocument document;
  final Uint8List? bytes;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  static const _invertColors = ColorFilter.matrix(<double>[
    -1, 0, 0, 0, 255,
    0, -1, 0, 0, 255,
    0, 0, -1, 0, 255,
    0, 0, 0, 1, 0,
  ]);

  final _controller = PdfViewerController();
  final _searchController = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  PdfTextSearcher? _textSearcher;
  List<PdfOutlineNode>? _outline;
  PdfDocumentRef? _documentRef;
  bool _searchOpen = false;
  bool _horizontal = false;
  int _currentPage = 1;
  int _pageCount = 0;

  RecentDocument get document => widget.document;
  LibraryStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _currentPage = math.max(1, document.lastPage);
    _pageCount = document.pageCount;
    _controller.addListener(_onViewerChanged);
  }

  @override
  void dispose() {
    _saveProgress();
    _controller.removeListener(_onViewerChanged);
    _textSearcher?.removeListener(_onSearchChanged);
    _textSearcher?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onViewerChanged() {
    if (!_controller.isReady || !mounted) return;
    final page = _controller.pageNumber ?? _currentPage;
    final count = _controller.pageCount;
    if (page != _currentPage || count != _pageCount) {
      setState(() {
        _currentPage = page;
        _pageCount = count;
      });
    }
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _saveProgress() async {
    if (document.source == DocumentSource.memory) return;
    final page = _controller.isReady ? (_controller.pageNumber ?? _currentPage) : _currentPage;
    final count = _controller.isReady ? _controller.pageCount : _pageCount;
    await store.updateProgress(document.id, lastPage: page, pageCount: count);
  }

  Future<String?> _passwordProvider() async {
    if (!mounted) return null;
    return showPasswordDialog(context);
  }

  Widget _buildViewer() {
    final initialPage = math.max(1, document.lastPage);
    final params = PdfViewerParams(
      backgroundColor: store.nightMode ? Colors.black : const Color(0xFF3C3C3C),
      pageAnchor: _horizontal ? PdfPageAnchor.left : PdfPageAnchor.top,
      pageAnchorEnd: _horizontal ? PdfPageAnchor.right : PdfPageAnchor.bottom,
      scrollHorizontallyByMouseWheel: _horizontal,
      layoutPages: _horizontal ? _horizontalLayout : null,
      textSelectionParams: const PdfTextSelectionParams(enabled: true),
      customizeContextMenuItems: _customizeContextMenuItems,
      keyHandlerParams: const PdfViewerKeyHandlerParams(autofocus: true),
      sizeDelegateProvider: const PdfViewerSizeDelegateProviderLegacy(
        useAlternativeFitScaleAsMinScale: false,
        maxScale: 8,
      ),
      pagePaintCallbacks: [
        if (_textSearcher != null) _textSearcher!.pageTextMatchPaintCallback,
      ],
      loadingBannerBuilder: (context, downloaded, total) => Center(
        child: CircularProgressIndicator(value: total == null || total == 0 ? null : downloaded / total),
      ),
      errorBannerBuilder: (context, error, stack, ref) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('无法打开文档\n$error', textAlign: TextAlign.center),
        ),
      ),
      linkHandlerParams: PdfLinkHandlerParams(
        onLinkTap: (link) async {
          if (link.url != null) {
            await _openExternalUrl(link.url!);
          } else if (link.dest != null && _controller.isReady) {
            await _controller.goToDest(link.dest);
          }
        },
      ),
      viewerOverlayBuilder: (context, size, handleLinkTap) => [
        PdfViewerScrollThumb(
          controller: _controller,
          orientation: ScrollbarOrientation.right,
          thumbSize: const Size(36, 28),
          thumbBuilder: (context, thumbSize, pageNumber, controller) => DecoratedBox(
            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
            child: Center(
              child: Text('${pageNumber ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
        ),
      ],
      onViewerReady: (pdfDocument, controller) async {
        _documentRef = controller.documentRef;
        _outline = await pdfDocument.loadOutline();
        _textSearcher?.removeListener(_onSearchChanged);
        _textSearcher?.dispose();
        _textSearcher = PdfTextSearcher(controller)..addListener(_onSearchChanged);
        if (!mounted) return;
        setState(() {
          _pageCount = pdfDocument.pages.length;
          _currentPage = controller.pageNumber ?? initialPage;
        });
        await store.updateProgress(document.id, lastPage: _currentPage, pageCount: _pageCount);
      },
      onPageChanged: (pageNumber) {
        if (pageNumber == null || !mounted) return;
        setState(() => _currentPage = pageNumber);
      },
    );

    if (document.source == DocumentSource.url) {
      return PdfViewer.uri(
        Uri.parse(document.path),
        controller: _controller,
        passwordProvider: _passwordProvider,
        initialPageNumber: initialPage,
        params: params,
      );
    }
    if (document.source == DocumentSource.memory) {
      return PdfViewer.data(
        widget.bytes ?? Uint8List(0),
        sourceName: document.name,
        controller: _controller,
        passwordProvider: _passwordProvider,
        initialPageNumber: initialPage,
        params: params,
      );
    }
    return PdfViewer.file(
      document.path,
      controller: _controller,
      passwordProvider: _passwordProvider,
      initialPageNumber: initialPage,
      params: params,
    );
  }

  PdfPageLayout _horizontalLayout(List<PdfPage> pages, PdfViewerParams params) {
    final height = pages.fold<double>(0, (prev, page) => math.max(prev, page.height)) + params.margin * 2;
    final layouts = <Rect>[];
    var x = params.margin;
    for (final page in pages) {
      layouts.add(Rect.fromLTWH(x, (height - page.height) / 2, page.width, page.height));
      x += page.width + params.margin;
    }
    return PdfPageLayout(pageLayouts: layouts, documentSize: Size(x, height));
  }

  Future<void> _openExternalUrl(Uri url) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('打开链接'),
        content: Text(url.toString()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('打开')),
        ],
      ),
    );
    if (confirmed == true) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _goToPage(int page) {
    if (!_controller.isReady) return;
    final target = page.clamp(1, math.max(1, _pageCount)).toInt();
    _controller.goToPage(pageNumber: target);
  }

  Future<void> _jumpToPage() async {
    final controller = TextEditingController(text: '$_currentPage');
    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('跳转到页码'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: '1 - $_pageCount',
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.pop(context, int.tryParse(value)),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(context, int.tryParse(controller.text)),
              child: const Text('跳转'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result != null) _goToPage(result);
  }

  void _runSearch(String query) {
    _textSearcher?.startTextSearch(query, caseInsensitive: true);
  }

  void _customizeContextMenuItems(
    PdfViewerContextMenuBuilderParams params,
    List<ContextMenuButtonItem> items,
  ) {
    if (!params.isTextSelectionEnabled || !params.textSelectionDelegate.hasSelectedText) {
      return;
    }
    items.insert(
      0,
      ContextMenuButtonItem(
        label: '问 AI',
        type: ContextMenuButtonType.custom,
        onPressed: () async {
          final text = await params.textSelectionDelegate.getSelectedText();
          params.dismissContextMenu();
          if (!mounted) return;
          await _openAiAsk(quote: text);
        },
      ),
    );
  }

  Future<void> _openAiAsk({String quote = ''}) async {
    if (!store.hasAiApiKey) {
      final configured = await showAiSettingsDialog(context, store);
      if (configured != true || !mounted) return;
    }
    if (!mounted) return;
    await showAiAskSheet(
      context: context,
      store: store,
      documentName: document.name,
      quote: quote,
    );
  }

  @override
  Widget build(BuildContext context) {
    final night = store.nightMode;
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _saveProgress();
      },
      child: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: Text(document.name, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: '问 AI',
              onPressed: () async {
                var quote = '';
                try {
                  if (_controller.isReady) {
                    quote = await _controller.textSelectionDelegate.getSelectedText();
                  }
                } catch (_) {}
                if (!mounted) return;
                await _openAiAsk(quote: quote);
              },
              icon: const Icon(Icons.auto_awesome),
            ),
            IconButton(
              tooltip: '搜索',
              onPressed: () => setState(() => _searchOpen = !_searchOpen),
              icon: const Icon(Icons.search),
            ),
            IconButton(
              tooltip: night ? '关闭夜间模式' : '夜间模式',
              onPressed: () => store.setNightMode(!night),
              icon: Icon(night ? Icons.wb_sunny_outlined : Icons.dark_mode_outlined),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'outline':
                    _scaffoldKey.currentState?.openEndDrawer();
                  case 'thumbs':
                    _scaffoldKey.currentState?.openEndDrawer();
                  case 'layout':
                    setState(() => _horizontal = !_horizontal);
                    if (_controller.isReady) _controller.invalidate();
                  case 'jump':
                    _jumpToPage();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'outline', child: Text('目录 / 缩略图')),
                PopupMenuItem(value: 'layout', child: Text(_horizontal ? '纵向阅读' : '横向阅读')),
                const PopupMenuItem(value: 'jump', child: Text('跳转页码')),
              ],
            ),
          ],
          bottom: _searchOpen
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(56),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            decoration: InputDecoration(
                              hintText: '搜索文本',
                              isDense: true,
                              border: const OutlineInputBorder(),
                              suffixText: _textSearcher?.hasMatches == true
                                  ? '${(_textSearcher!.currentIndex ?? 0) + 1}/${_textSearcher!.matches.length}'
                                  : null,
                            ),
                            onChanged: _runSearch,
                            onSubmitted: _runSearch,
                          ),
                        ),
                        IconButton(
                          tooltip: '上一个',
                          onPressed: _textSearcher?.hasMatches == true ? () => _textSearcher!.goToPrevMatch() : null,
                          icon: const Icon(Icons.keyboard_arrow_up),
                        ),
                        IconButton(
                          tooltip: '下一个',
                          onPressed: _textSearcher?.hasMatches == true ? () => _textSearcher!.goToNextMatch() : null,
                          icon: const Icon(Icons.keyboard_arrow_down),
                        ),
                      ],
                    ),
                  ),
                )
              : null,
        ),
        endDrawer: Drawer(
          child: SafeArea(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: '目录'),
                      Tab(text: '缩略图'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        OutlinePanel(
                          outline: _outline,
                          controller: _controller,
                          onItemSelected: () => Navigator.of(context).maybePop(),
                        ),
                        ThumbnailsPanel(
                          documentRef: _documentRef,
                          controller: _controller,
                          onItemSelected: () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            if (_textSearcher?.isSearching == true)
              LinearProgressIndicator(value: _textSearcher?.searchProgress, minHeight: 2),
            Expanded(
              child: AnimatedBuilder(
                animation: store,
                builder: (context, _) {
                  return ColorFiltered(
                    colorFilter: store.nightMode ? _invertColors : const ColorFilter.mode(Colors.white, BlendMode.dst),
                    child: _buildViewer(),
                  );
                },
              ),
            ),
            _ReaderBottomBar(
              currentPage: _currentPage,
              pageCount: math.max(_pageCount, 1),
              onPageChanged: _goToPage,
              onJump: _jumpToPage,
              onZoomOut: () {
                if (_controller.isReady) _controller.zoomDown();
              },
              onZoomIn: () {
                if (_controller.isReady) _controller.zoomUp();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderBottomBar extends StatelessWidget {
  const _ReaderBottomBar({
    required this.currentPage,
    required this.pageCount,
    required this.onPageChanged,
    required this.onJump,
    required this.onZoomOut,
    required this.onZoomIn,
  });

  final int currentPage;
  final int pageCount;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onJump;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(
            children: [
              IconButton(tooltip: '缩小', onPressed: onZoomOut, icon: const Icon(Icons.zoom_out)),
              Expanded(
                child: Slider(
                  min: 1,
                  max: pageCount.toDouble(),
                  divisions: pageCount > 1 ? pageCount - 1 : null,
                  value: currentPage.clamp(1, pageCount).toDouble(),
                  onChanged: pageCount > 1 ? (value) => onPageChanged(value.round()) : null,
                ),
              ),
              TextButton(
                onPressed: onJump,
                child: Text('$currentPage / $pageCount'),
              ),
              IconButton(tooltip: '放大', onPressed: onZoomIn, icon: const Icon(Icons.zoom_in)),
            ],
          ),
        ),
      ),
    );
  }
}
