/// Centraliza os caminhos de assets utilizados pela aplicação.
abstract final class AssetPaths {
  /// Caminho do catálogo JSON com a lista de documentos disponíveis.
  static const String pdfCatalog = 'assets/pdfs/catalog.json';

  /// Diretório base onde os PDFs ficam armazenados.
  static const String pdfDirectory = 'assets/pdfs/';

  /// Índice textual pré-processado para busca local nos PDFs.
  static const String pdfTextIndex = 'assets/pdfs/pdf_text_index.json';
}
