import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/pdf_repository.dart';
import '../viewmodels/pdf_view_model.dart';

/// Provider do repositório de PDFs.
final pdfRepositoryProvider = Provider<PdfRepository>((ref) {
  return PdfRepository();
});

/// Provider principal do ViewModel.
///
/// Controla lista, busca, favoritos, carregamento e reatividade da tela.
final pdfViewModelProvider =
    AsyncNotifierProvider<PdfViewModel, PdfState>(PdfViewModel.new);
