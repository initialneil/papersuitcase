import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:paper_suitecase/services/file_trash_service.dart';

void main() {
  test('moveToTrash removes the file from its folder', () async {
    if (!Platform.isMacOS) return; // trash path is platform-specific
    final tmp = await Directory.systemTemp.createTemp('pst_trash_');
    final name = 'trash_me_${DateTime.now().microsecondsSinceEpoch}.pdf';
    final f = File(p.join(tmp.path, name));
    await f.writeAsString('x');

    final ok = await FileTrashService.moveToTrash(f.path);

    expect(ok, isTrue);
    expect(await f.exists(), isFalse); // gone from its folder — won't resurrect

    // clean up whatever landed in ~/.Trash
    final trashed = File(p.join(Platform.environment['HOME']!, '.Trash', name));
    if (await trashed.exists()) await trashed.delete();
    await tmp.delete(recursive: true);
  });

  test('moveToTrash on a missing file is a no-op success', () async {
    final ok = await FileTrashService.moveToTrash(
        p.join(Directory.systemTemp.path, 'pst_does_not_exist_xyz.pdf'));
    expect(ok, isTrue);
  });
}
