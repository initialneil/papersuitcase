enum DownloadStatus { downloading, done, failed }

class DownloadTask {
  final String id;
  final String title;
  int receivedBytes;
  int? totalBytes;
  DownloadStatus status;
  String? error;

  DownloadTask({
    required this.id,
    required this.title,
    this.receivedBytes = 0,
    this.totalBytes,
    this.status = DownloadStatus.downloading,
    this.error,
  });

  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0);
  }
}
