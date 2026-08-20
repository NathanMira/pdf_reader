import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recent_document.dart';
import '../platform/file_ops.dart';

class LibraryStore extends ChangeNotifier {
  LibraryStore(this._prefs) {
    _load();
  }

  static const _docsKey = 'recent_documents_v1';
  static const _nightModeKey = 'night_mode';

  final SharedPreferences _prefs;
  final List<RecentDocument> _documents = [];
  bool _nightMode = false;

  List<RecentDocument> get documents => List.unmodifiable(_documents);
  bool get nightMode => _nightMode;

  void _load() {
    _nightMode = _prefs.getBool(_nightModeKey) ?? false;
    final raw = _prefs.getString(_docsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _documents
        ..clear()
        ..addAll(
          list
              .whereType<Map>()
              .map((item) => RecentDocument.fromJson(Map<String, dynamic>.from(item)))
              .where((doc) => doc.source != DocumentSource.memory),
        );
      _documents.sort((a, b) => b.openedAt.compareTo(a.openedAt));
    } catch (_) {
      _documents.clear();
    }
  }

  Future<void> _persist() async {
    final payload = jsonEncode(_documents.map((doc) => doc.toJson()).toList());
    await _prefs.setString(_docsKey, payload);
  }

  Future<void> setNightMode(bool value) async {
    _nightMode = value;
    await _prefs.setBool(_nightModeKey, value);
    notifyListeners();
  }

  Future<void> upsert(RecentDocument document) async {
    _documents.removeWhere((item) => item.id == document.id);
    _documents.insert(0, document);
    await _persist();
    notifyListeners();
  }

  Future<void> updateProgress(String id, {required int lastPage, int? pageCount}) async {
    final index = _documents.indexWhere((item) => item.id == id);
    if (index < 0) return;
    _documents[index] = _documents[index].copyWith(lastPage: lastPage, pageCount: pageCount);
    await _persist();
    notifyListeners();
  }

  Future<void> remove(RecentDocument document) async {
    _documents.removeWhere((item) => item.id == document.id);
    if (document.isLocalFile) {
      await deletePath(document.path);
    }
    await _persist();
    notifyListeners();
  }

  RecentDocument? findById(String id) {
    for (final document in _documents) {
      if (document.id == id) return document;
    }
    return null;
  }

  Future<RecentDocument> importPickedFile(PlatformFile file) async {
    final name = file.name.isEmpty ? '未命名.pdf' : file.name;
    final size = await file.length();
    final existing = _findDuplicate(
      (doc) => doc.source == DocumentSource.file && doc.name == name && doc.sizeBytes == size,
    );
    if (existing != null && await pathExists(existing.path)) {
      final updated = existing.copyWith(openedAt: DateTime.now());
      await upsert(updated);
      return updated;
    }

    if (kIsWeb) {
      final document = RecentDocument(
        id: _newId(),
        name: name,
        path: name,
        source: DocumentSource.memory,
        openedAt: DateTime.now(),
        sizeBytes: size,
      );
      return document;
    }

    final dir = await _libraryDir();
    final id = _newId();
    final destPath = p.join(dir, '$id.pdf');
    await saveBytesToFile(destPath, file.readAsByteStream());
    final document = RecentDocument(
      id: id,
      name: name,
      path: destPath,
      source: DocumentSource.file,
      openedAt: DateTime.now(),
      sizeBytes: size,
    );
    await upsert(document);
    return document;
  }

  Future<RecentDocument> importUrl(Uri uri) async {
    final url = uri.toString();
    final existing = _findDuplicate((doc) => doc.source == DocumentSource.url && doc.path == url);
    if (existing != null) {
      final updated = existing.copyWith(openedAt: DateTime.now());
      await upsert(updated);
      return updated;
    }

    final name = _nameFromUri(uri);
    final document = RecentDocument(
      id: _newId(),
      name: name,
      path: url,
      source: DocumentSource.url,
      openedAt: DateTime.now(),
    );
    await upsert(document);
    return document;
  }

  Future<bool> isReadable(RecentDocument document) async {
    if (document.source == DocumentSource.url || document.source == DocumentSource.memory) {
      return true;
    }
    return pathExists(document.path);
  }

  Future<String> _libraryDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final path = p.join(docs.path, 'library');
    await ensureDirectory(path);
    return path;
  }

  RecentDocument? _findDuplicate(bool Function(RecentDocument doc) test) {
    for (final document in _documents) {
      if (test(document)) return document;
    }
    return null;
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  String _nameFromUri(Uri uri) {
    if (uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.last;
      if (last.toLowerCase().endsWith('.pdf')) return last;
      if (last.isNotEmpty) return '$last.pdf';
    }
    return uri.host.isEmpty ? '远程文档.pdf' : '${uri.host}.pdf';
  }
}
