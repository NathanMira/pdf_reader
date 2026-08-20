import 'dart:io';

Future<void> ensureDirectory(String path) async {
  await Directory(path).create(recursive: true);
}

Future<void> saveBytesToFile(String path, Stream<List<int>> bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  final sink = file.openWrite();
  try {
    await sink.addStream(bytes);
  } finally {
    await sink.close();
  }
}

Future<bool> pathExists(String path) => File(path).exists();

Future<void> deletePath(String path) async {
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}

Future<int> pathSize(String path) async {
  final file = File(path);
  if (!await file.exists()) return 0;
  return file.length();
}
