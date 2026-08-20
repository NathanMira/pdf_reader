Future<void> ensureDirectory(String path) async {}

Future<void> saveBytesToFile(String path, Stream<List<int>> bytes) async {}

Future<bool> pathExists(String path) async => false;

Future<void> deletePath(String path) async {}

Future<int> pathSize(String path) async => 0;
