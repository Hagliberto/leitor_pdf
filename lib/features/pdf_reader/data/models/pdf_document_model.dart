import '../../domain/entities/pdf_document.dart';

/// Modelo responsável por converter dados JSON em entidade de domínio.
class PdfDocumentModel extends PdfDocument {
  const PdfDocumentModel({
    required super.file,
    required super.title,
    required super.description,
    required super.version,
    required super.pageCount,
    super.localPath,
    super.isFavorite,
  });

  /// Cria um documento PDF a partir de um mapa JSON.
  factory PdfDocumentModel.fromJson(Map<String, dynamic> json) {
    return PdfDocumentModel(
      file: json['file'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      version: json['version'] as String? ?? 'v1.0',
      pageCount: json['pageCount'] as int? ?? 0,
      localPath: json['localPath'] as String?,
    );
  }
}
