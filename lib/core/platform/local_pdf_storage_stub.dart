import 'dart:typed_data';

/// Copia um PDF escolhido pelo usuário para uma área persistente do app.
///
/// No Web essa operação não é persistente por caminho físico, por isso o stub
/// retorna `null`.
Future<String?> copyPickedPdfToAppStorage({
  required String sourcePath,
  required String fileName,
}) async {
  return null;
}

/// Lê bytes de um PDF salvo localmente.
Future<Uint8List?> readLocalPdfBytes(String localPath) async {
  return null;
}

/// No Web não há acesso permanente e recursivo a diretórios pelo FilePicker padrão.
Future<List<({String path, String name})>> listPdfFilesRecursively(String directoryPath) async {
  return const <({String path, String name})>[];
}
