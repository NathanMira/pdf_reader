String formatBytes(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String formatOpenedAt(DateTime time) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(time.year, time.month, time.day);
  final hh = time.hour.toString().padLeft(2, '0');
  final mm = time.minute.toString().padLeft(2, '0');
  if (date == today) return '今天 $hh:$mm';
  if (date == today.subtract(const Duration(days: 1))) return '昨天 $hh:$mm';
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  if (time.year == now.year) return '$month-$day $hh:$mm';
  return '${time.year}-$month-$day';
}

String formatPageProgress(int lastPage, int pageCount) {
  if (pageCount > 0) return '读到第 $lastPage / $pageCount 页';
  if (lastPage > 1) return '读到第 $lastPage 页';
  return '尚未开始阅读';
}
