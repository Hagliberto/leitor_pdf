import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

String _safeFileName(String value) {
  return value
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Copia um PDF selecionado no dispositivo para a pasta interna do app.
///
/// Isso permite que o documento importado continue disponível depois que o app
/// for fechado, sem depender do caminho original do arquivo escolhido.
Future<String?> copyPickedPdfToAppStorage({
  required String sourcePath,
  required String fileName,
}) async {
  final source = File(sourcePath);
  if (!await source.exists()) return null;

  final baseDir = await getApplicationDocumentsDirectory();
  final pdfDir = Directory('${baseDir.path}${Platform.pathSeparator}normativos_pdfs');
  if (!await pdfDir.exists()) {
    await pdfDir.create(recursive: true);
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final safeName = _safeFileName(fileName.toLowerCase().endsWith('.pdf') ? fileName : '$fileName.pdf');
  final target = File('${pdfDir.path}${Platform.pathSeparator}$stamp-$safeName');
  await source.copy(target.path);
  return target.path;
}

/// Lê bytes de um PDF salvo localmente.
Future<Uint8List?> readLocalPdfBytes(String localPath) async {
  final file = File(localPath);
  if (!await file.exists()) return null;
  return file.readAsBytes();
}

/// Lista apenas os PDFs existentes diretamente na pasta escolhida pelo usuário.
///
/// A varredura não é recursiva para evitar importações inesperadas em massa.
Future<List<({String path, String name})>> listPdfFilesInDirectory(String directoryPath) async {
  final root = Directory(directoryPath);
  if (!await root.exists()) return const <({String path, String name})>[];

  final files = <({String path, String name})>[];
  await for (final entity in root.list(recursive: false, followLinks: false)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
      final name = entity.uri.pathSegments.isNotEmpty ? Uri.decodeComponent(entity.uri.pathSegments.last) : entity.path.split(Platform.pathSeparator).last;
      files.add((path: entity.path, name: name));
    }
  }
  files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return files;
}
