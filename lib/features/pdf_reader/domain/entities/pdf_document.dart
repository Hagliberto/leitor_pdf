import '../../../../core/constants/asset_paths.dart';

/// Entidade principal que representa um documento PDF disponível no app.
class PdfDocument {
  /// Nome lógico do arquivo PDF.
  ///
  /// Para documentos dos assets, normalmente será algo como `acordo.pdf`.
  /// Para documentos importados, recebe um identificador lógico iniciado por
  /// `local:`.
  final String file;

  /// Título amigável exibido na interface.
  final String title;

  /// Descrição curta do documento.
  final String description;

  /// Versão do PDF informada no catálogo ou definida automaticamente.
  final String version;

  /// Quantidade de páginas do PDF.
  final int pageCount;

  /// Caminho físico local, usado para PDFs importados do dispositivo.
  final String? localPath;

  /// Bytes do PDF importado codificados em Base64.
  ///
  /// Usado principalmente no Flutter Web, onde o navegador não expõe um caminho físico persistente.
  final String? localBase64;

  /// Indica se o documento foi marcado como favorito pelo usuário.
  final bool isFavorite;

  const PdfDocument({
    required this.file,
    required this.title,
    required this.description,
    required this.version,
    required this.pageCount,
    this.localPath,
    this.localBase64,
    this.isFavorite = false,
  });

  /// Indica se o documento foi importado do dispositivo.
  bool get isLocal => (localPath != null && localPath!.isNotEmpty) || (localBase64 != null && localBase64!.isNotEmpty);

  /// Caminho completo do PDF dentro dos assets.
  String get assetPath => file.contains('/') ? file : '${AssetPaths.pdfDirectory}$file';

  /// Retorna uma nova instância alterando apenas os campos informados.
  PdfDocument copyWith({
    String? file,
    String? title,
    String? description,
    String? version,
    int? pageCount,
    String? localPath,
    String? localBase64,
    bool? clearLocalPath,
    bool? clearLocalBase64,
    bool? isFavorite,
  }) {
    return PdfDocument(
      file: file ?? this.file,
      title: title ?? this.title,
      description: description ?? this.description,
      version: version ?? this.version,
      pageCount: pageCount ?? this.pageCount,
      localPath: clearLocalPath == true ? null : (localPath ?? this.localPath),
      localBase64: clearLocalBase64 == true ? null : (localBase64 ?? this.localBase64),
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}
