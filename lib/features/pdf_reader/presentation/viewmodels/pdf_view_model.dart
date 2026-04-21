import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/pdf_document.dart';
import '../providers/pdf_provider.dart';

/// Estado da tela principal de documentos.
class PdfState {
  /// Lista completa de documentos carregados.
  final List<PdfDocument> documents;

  /// Texto digitado no campo de busca.
  final String searchTerm;

  /// Define se a tela deve mostrar somente favoritos.
  final bool showOnlyFavorites;

  const PdfState({
    required this.documents,
    this.searchTerm = '',
    this.showOnlyFavorites = false,
  });

  /// Lista filtrada com base na busca e no filtro de favoritos.
  List<PdfDocument> get filteredDocuments {
    final normalizedSearch = searchTerm.trim().toLowerCase();

    return documents.where((doc) {
      final matchesSearch = normalizedSearch.isEmpty ||
          doc.title.toLowerCase().contains(normalizedSearch) ||
          doc.description.toLowerCase().contains(normalizedSearch) ||
          doc.file.toLowerCase().contains(normalizedSearch);

      final matchesFavorite = !showOnlyFavorites || doc.isFavorite;

      return matchesSearch && matchesFavorite;
    }).toList();
  }

  /// Cria uma nova versão do estado.
  PdfState copyWith({
    List<PdfDocument>? documents,
    String? searchTerm,
    bool? showOnlyFavorites,
  }) {
    return PdfState(
      documents: documents ?? this.documents,
      searchTerm: searchTerm ?? this.searchTerm,
      showOnlyFavorites: showOnlyFavorites ?? this.showOnlyFavorites,
    );
  }
}

/// ViewModel da lista de PDFs.
///
/// Usa Riverpod para carregar dados de forma assíncrona e reagir a alterações
/// de busca, favoritos e filtros.
class PdfViewModel extends AsyncNotifier<PdfState> {
  @override
  Future<PdfState> build() async {
    final repository = ref.read(pdfRepositoryProvider);
    final documents = await repository.fetchDocuments();

    return PdfState(documents: documents);
  }

  /// Atualiza o texto de busca.
  void updateSearch(String value) {
    final current = state.value;
    if (current == null) return;

    state = AsyncData(current.copyWith(searchTerm: value));
  }

  /// Alterna entre todos os documentos e somente favoritos.
  void toggleFavoriteFilter() {
    final current = state.value;
    if (current == null) return;

    state = AsyncData(
      current.copyWith(showOnlyFavorites: !current.showOnlyFavorites),
    );
  }


  /// Recarrega a biblioteca depois de mudanças globais.
  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(pdfRepositoryProvider);
      final documents = await repository.fetchDocuments();
      return PdfState(documents: documents);
    });
  }

  /// Marca ou desmarca um documento como favorito.
  Future<void> toggleFavorite(PdfDocument document) async {
    final current = state.value;
    if (current == null) return;

    final repository = ref.read(pdfRepositoryProvider);
    await repository.toggleFavorite(document.file);

    final updatedDocuments = current.documents.map((item) {
      if (item.file == document.file) {
        return item.copyWith(isFavorite: !item.isFavorite);
      }

      return item;
    }).toList();

    state = AsyncData(current.copyWith(documents: updatedDocuments));
  }
}
