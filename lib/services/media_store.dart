import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class MediaStore {
  MediaStore._();

  /// Copia o arquivo escolhido para dentro do app, para nao depender do
  /// caminho temporario devolvido pelo seletor de arquivos.
  static Future<File?> persist(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) return null;

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'media'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final name = p.basename(sourcePath);
    final target = p.join(
      dir.path,
      '${DateTime.now().millisecondsSinceEpoch}_$name',
    );
    return source.copy(target);
  }

  static Future<void> remove(String? path) async {
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
