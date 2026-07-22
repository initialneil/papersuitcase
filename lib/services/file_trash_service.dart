import 'dart:io';
import 'package:path/path.dart' as p;

/// Moves a file to the OS trash / recycle bin — recoverable, not a hard delete.
///
/// The app is not sandboxed (see `macos/Runner/*.entitlements`), so `HOME`
/// resolves to the real home and `~/.Trash` is directly writable — no Finder
/// automation / TCC prompt needed.
class FileTrashService {
  FileTrashService._();

  /// Move [path] to the trash. Returns true on success (or if already gone).
  /// Best effort: returns false if the platform move failed (caller decides).
  static Future<bool> moveToTrash(String path) async {
    final file = File(path);
    if (!await file.exists()) return true; // nothing to trash
    try {
      if (Platform.isMacOS) return await _macTrash(file);
      if (Platform.isWindows) return await _windowsRecycle(path);
    } catch (_) {}
    return false;
  }

  static Future<bool> _macTrash(File file) async {
    final home = Platform.environment['HOME'];
    if (home == null) return false;
    final trashDir = Directory(p.join(home, '.Trash'));
    if (!await trashDir.exists()) return false;

    var dest = p.join(trashDir.path, p.basename(file.path));
    // Don't clobber a same-named file already in the trash.
    if (await File(dest).exists() || await Directory(dest).exists()) {
      final base = p.basenameWithoutExtension(file.path);
      final ext = p.extension(file.path);
      dest = p.join(
          trashDir.path, '$base ${DateTime.now().millisecondsSinceEpoch}$ext');
    }
    try {
      await file.rename(dest); // same volume — atomic move
    } on FileSystemException {
      await file.copy(dest); // cross-volume fallback
      await file.delete();
    }
    return true;
  }

  static Future<bool> _windowsRecycle(String path) async {
    // VisualBasic FileSystem sends to the Recycle Bin (recoverable).
    final escaped = path.replaceAll("'", "''");
    final ps = "Add-Type -AssemblyName Microsoft.VisualBasic; "
        "[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile("
        "'$escaped','OnlyErrorDialogs','SendToRecycleBin')";
    final r =
        await Process.run('powershell', ['-NoProfile', '-Command', ps]);
    return r.exitCode == 0;
  }
}
