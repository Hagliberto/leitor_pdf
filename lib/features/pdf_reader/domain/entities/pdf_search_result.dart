/// Resultado de uma busca textual feita no índice local do PDF.
class PdfSearchResultItem {
  /// Arquivo onde o termo foi encontrado.
  final String file;

  /// Página em que a ocorrência foi localizada.
  final int page;

  /// Trecho textual próximo ao termo pesquisado.
  final String snippet;

  /// Quantidade aproximada de ocorrências encontradas na página.
  final int occurrences;

  const PdfSearchResultItem({
    required this.file,
    required this.page,
    required this.snippet,
    required this.occurrences,
  });
}
