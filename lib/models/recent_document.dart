enum DocumentSource { file, url, memory }

class RecentDocument {
  const RecentDocument({
    required this.id,
    required this.name,
    required this.path,
    required this.source,
    required this.openedAt,
    this.lastPage = 1,
    this.pageCount = 0,
    this.sizeBytes = 0,
  });

  final String id;
  final String name;
  final String path;
  final DocumentSource source;
  final DateTime openedAt;
  final int lastPage;
  final int pageCount;
  final int sizeBytes;

  bool get isLocalFile => source == DocumentSource.file;
  bool get isUrl => source == DocumentSource.url;

  RecentDocument copyWith({
    String? name,
    String? path,
    DateTime? openedAt,
    int? lastPage,
    int? pageCount,
    int? sizeBytes,
  }) {
    return RecentDocument(
      id: id,
      name: name ?? this.name,
      path: path ?? this.path,
      source: source,
      openedAt: openedAt ?? this.openedAt,
      lastPage: lastPage ?? this.lastPage,
      pageCount: pageCount ?? this.pageCount,
      sizeBytes: sizeBytes ?? this.sizeBytes,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'source': source.name,
    'openedAt': openedAt.toIso8601String(),
    'lastPage': lastPage,
    'pageCount': pageCount,
    'sizeBytes': sizeBytes,
  };

  factory RecentDocument.fromJson(Map<String, dynamic> json) {
    return RecentDocument(
      id: json['id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
      source: DocumentSource.values.firstWhere(
        (value) => value.name == json['source'],
        orElse: () => DocumentSource.file,
      ),
      openedAt: DateTime.tryParse(json['openedAt'] as String? ?? '') ?? DateTime.now(),
      lastPage: json['lastPage'] as int? ?? 1,
      pageCount: json['pageCount'] as int? ?? 0,
      sizeBytes: json['sizeBytes'] as int? ?? 0,
    );
  }
}
