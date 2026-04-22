import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../../../core/constants/app_info.dart';
import '../../data/repositories/pdf_repository.dart';
import '../../domain/entities/pdf_document.dart';
import '../../domain/entities/pdf_search_result.dart';
import '../providers/pdf_provider.dart';
import '../widgets/web_pdf_viewer_frame.dart';

enum _ShareTarget { currentPagePdf, currentPagePng, fullDocumentPdf }
enum _PdfEditTool { none, highlight, draw, text, rectangle, circle }
enum _PdfDisplayMode { fitPage, fitWidth, customZoom }

class _EditMark {
  final _PdfEditTool tool;
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final String? text;

  const _EditMark({
    required this.tool,
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.text,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'tool': tool.name,
        'points': points.map((p) => <String, double>{'x': p.dx, 'y': p.dy}).toList(),
        'color': color.value,
        'strokeWidth': strokeWidth,
        'text': text,
      };

  factory _EditMark.fromJson(Map<String, dynamic> json) {
    final name = json['tool'] as String? ?? 'draw';
    final tool = _PdfEditTool.values.firstWhere((item) => item.name == name, orElse: () => _PdfEditTool.draw);
    final points = (json['points'] as List<dynamic>? ?? const <dynamic>[]).map((raw) {
      final map = raw as Map<String, dynamic>;
      return Offset((map['x'] as num).toDouble(), (map['y'] as num).toDouble());
    }).toList();
    return _EditMark(tool: tool, points: points, color: Color(json['color'] as int? ?? 0xFFFFEB3B), strokeWidth: (json['strokeWidth'] as num? ?? 5).toDouble(), text: json['text'] as String?);
  }
}



class _PostItEntry {
  final String id;
  final int page;
  final String text;

  const _PostItEntry({required this.id, required this.page, required this.text});

  _PostItEntry copyWith({String? text}) => _PostItEntry(id: id, page: page, text: text ?? this.text);
}

class _PostItData {
  static const String prefix = '__POSTIT_JSON__:';
  final String title;
  final String body;
  final int colorValue;
  final String? imageName;
  final String? imageBase64;

  const _PostItData({
    this.title = '',
    this.body = '',
    this.colorValue = 0xFFFFF8CF,
    this.imageName,
    this.imageBase64,
  });

  Color get color => Color(colorValue);
  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty && (imageBase64 == null || imageBase64!.isEmpty);

  factory _PostItData.fromStored(String raw) {
    final value = raw.trim();
    if (value.startsWith(prefix)) {
      try {
        final json = jsonDecode(value.substring(prefix.length)) as Map<String, dynamic>;
        return _PostItData(
          title: json['title'] as String? ?? '',
          body: json['body'] as String? ?? '',
          colorValue: json['colorValue'] as int? ?? 0xFFFFF8CF,
          imageName: json['imageName'] as String?,
          imageBase64: json['imageBase64'] as String?,
        );
      } catch (_) {}
    }
    final normalized = raw.replaceAll('\r\n', '\n');
    final lines = normalized.split('\n');
    final hasStoredTitle = lines.isNotEmpty && lines.first.startsWith('Título: ');
    return _PostItData(
      title: hasStoredTitle ? lines.first.replaceFirst('Título: ', '').trim() : '',
      body: hasStoredTitle ? lines.skip(1).join('\n').trim() : normalized.trim(),
    );
  }

  _PostItData copyWith({String? title, String? body, int? colorValue, String? imageName, String? imageBase64, bool clearImage = false}) {
    return _PostItData(
      title: title ?? this.title,
      body: body ?? this.body,
      colorValue: colorValue ?? this.colorValue,
      imageName: clearImage ? null : (imageName ?? this.imageName),
      imageBase64: clearImage ? null : (imageBase64 ?? this.imageBase64),
    );
  }

  String toStored() => '$prefix${jsonEncode(<String, dynamic>{
        'title': title,
        'body': body,
        'colorValue': colorValue,
        'imageName': imageName,
        'imageBase64': imageBase64,
      })}';
}

/// Tela de visualização do PDF.
///
/// Recursos principais:
/// - leitura via iframe no Web e Syncfusion nas demais plataformas;
/// - busca indexada com lista de resultados;
/// - favoritos por página com prévia;
/// - duplo clique/toque para favoritar a página atual;
/// - pressão longa para compartilhar página atual ou documento;
/// - alternância entre navegação vertical e horizontal no viewer nativo.
class PdfViewerPage extends ConsumerStatefulWidget {
  /// Documento aberto no leitor.
  final PdfDocument document;

  /// Página inicial opcional, útil ao abrir favoritos ou resultados.
  final int initialPage;

  const PdfViewerPage({
    super.key,
    required this.document,
    this.initialPage = 1,
  });

  @override
  ConsumerState<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends ConsumerState<PdfViewerPage> {
  final PdfViewerController _pdfController = PdfViewerController();
  final TextEditingController _pageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  late final Future<Uint8List> _pdfBytesFuture;
  PdfTextSearchResult _nativeSearchResult = PdfTextSearchResult();

  int _currentPage = 1;
  int _totalPages = 0;
  int _selectedNavIndex = 0;
  double _zoom = 1.0;
  bool _isSearching = false;
  bool _isAnySheetOpen = false;
  bool _isSearchOpen = false;
  bool _isQuickActionsOpen = false;
  bool _isHorizontalNavigation = false;
  String _webSearchTerm = '';
  int _webNavigationToken = 0;
  List<PdfSearchResultItem> _searchResults = const <PdfSearchResultItem>[];
  Set<int> _favoritePages = <int>{};
  _PdfEditTool _editTool = _PdfEditTool.none;
  Color _editColor = const Color(0xFFFFEB3B);
  double _editStrokeWidth = 5;
  final List<_EditMark> _editMarks = <_EditMark>[];
  List<Offset> _currentStroke = <Offset>[];
  final Map<int, List<_PostItEntry>> _postIts = <int, List<_PostItEntry>>{};
  _PdfDisplayMode _displayMode = _PdfDisplayMode.fitWidth;
  bool _fullScreen = false;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage.clamp(1, widget.document.pageCount).toInt();
    _totalPages = widget.document.pageCount;
    _pageController.text = _currentPage.toString();
    _webNavigationToken = DateTime.now().microsecondsSinceEpoch;
    _pdfBytesFuture = _loadPdfBytes(widget.document);
    _loadFavoritePagesForCurrentDocument();
    _loadPostItsForCurrentDocument();
    _loadEditsForCurrentPage();
  }

  Future<void> _loadFavoritePagesForCurrentDocument() async {
    final favorites = await ref.read(pdfRepositoryProvider).getFavoritePages();
    if (!mounted) return;
    setState(() {
      _favoritePages = favorites
          .where((item) => item.file == widget.document.file)
          .map((item) => item.page)
          .toSet();
    });
  }

  Future<void> _loadPostItsForCurrentDocument() async {
    final rawPostIts = await ref.read(pdfRepositoryProvider).getPostItsForDocument(widget.document.file);
    final grouped = <int, List<_PostItEntry>>{};

    for (final item in rawPostIts) {
      final page = item['page'] as int?;
      final id = item['id'] as String?;
      final text = item['text'] as String?;
      if (page == null || id == null || text == null || text.trim().isEmpty) continue;
      grouped.putIfAbsent(page, () => <_PostItEntry>[]).add(_PostItEntry(id: id, page: page, text: text));
    }

    if (!mounted) return;
    setState(() {
      _postIts
        ..clear()
        ..addAll(grouped);
    });
  }

  bool _hasPostItsOnCurrentPage() => (_postIts[_currentPage] ?? const <_PostItEntry>[]).isNotEmpty;

  String _postItPreviewText(String raw) {
    final data = _PostItData.fromStored(raw);
    final title = data.title.trim();
    final body = data.body
        .replaceAll('**', '')
        .replaceAll('_', '')
        .replaceAll('<u>', '')
        .replaceAll('</u>', '')
        .replaceAll('☐ ', '')
        .replaceAll('☑ ', '')
        .trim();
    if (title.isNotEmpty && body.isNotEmpty) return '$title — $body';
    if (title.isNotEmpty) return title;
    if (body.isNotEmpty) return body;
    return data.imageName == null ? 'Post-it sem texto.' : 'Post-it com imagem: ${data.imageName}';
  }

  Future<void> _loadEditsForCurrentPage() async {
    final rawEdits = await ref.read(pdfRepositoryProvider).getPageEdits(file: widget.document.file, page: _currentPage);
    if (!mounted) return;
    setState(() {
      _editMarks
        ..clear()
        ..addAll(rawEdits.map(_EditMark.fromJson));
      _currentStroke.clear();
      _editTool = _PdfEditTool.none;
    });
  }

  Future<void> _saveEditsForCurrentPage() async {
    await ref.read(pdfRepositoryProvider).savePageEdits(file: widget.document.file, page: _currentPage, edits: _editMarks.map((mark) => mark.toJson()).toList());
  }

  Future<void> _addEditMark(_EditMark mark) async {
    setState(() => _editMarks.add(mark));
    await _saveEditsForCurrentPage();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _nativeSearchResult.removeListener(_onNativeSearchChanged);
    super.dispose();
  }

  /// Carrega o PDF, seja ele asset empacotado ou documento importado.
  Future<Uint8List> _loadPdfBytes(PdfDocument document) async {
    final bytes = await ref.read(pdfRepositoryProvider).loadDocumentBytes(document);
    if (bytes == null) {
      throw StateError('PDF não encontrado ou inacessível.');
    }
    return bytes;
  }

  /// Atualiza a interface quando a busca nativa do Syncfusion muda.
  void _onNativeSearchChanged() {
    if (mounted) setState(() {});
  }

  void _showElegantToast({required IconData icon, required String message}) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: Colors.transparent,
        duration: const Duration(seconds: 3),
        content: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.92, end: 1),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          builder: (context, value, child) => Transform.scale(scale: value, child: child),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4FF),
              border: Border.all(color: const Color(0xFF9CCBFF)),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: const Color(0xFF0B5CAD).withOpacity(0.18), blurRadius: 28, offset: const Offset(0, 12))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: const Color(0xFF0B5CAD)),
                const SizedBox(width: 10),
                Flexible(child: Text(message, style: const TextStyle(color: Color(0xFF0B315E), fontWeight: FontWeight.w800))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showUndoToast({required IconData icon, required String message, required String actionLabel, required VoidCallback onUndo}) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: Colors.transparent,
      duration: const Duration(seconds: 3),
      action: SnackBarAction(label: actionLabel, textColor: scheme.primary, onPressed: onUndo),
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: const Color(0xFFEAF4FF), border: Border.all(color: const Color(0xFF7DBDFF)), borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: const Color(0xFF0B5CAD).withOpacity(0.20), blurRadius: 30, offset: const Offset(0, 12))]),
        child: Row(children: [Icon(icon, color: const Color(0xFF0B5CAD)), const SizedBox(width: 10), Expanded(child: Text(message, style: const TextStyle(color: Color(0xFF0B315E), fontWeight: FontWeight.w800))), const SizedBox(width: 8), const Icon(Icons.undo_rounded, color: Color(0xFF0B5CAD))]),
      ),
    ));
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (context.mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    });
  }

  /// Busca um texto dentro do PDF usando o índice local.
  Future<void> _searchText(String query) async {
    final normalizedQuery = query.trim();

    if (normalizedQuery.length < 2) {
      setState(() {
        _searchResults = const <PdfSearchResultItem>[];
        _webSearchTerm = '';
      });
      return;
    }

    setState(() => _isSearching = true);

    final repository = ref.read(pdfRepositoryProvider);
    final results = await repository
        .searchInDocument(file: widget.document.file, query: normalizedQuery, allowDynamicExtraction: true)
        .timeout(const Duration(seconds: 8), onTimeout: () => <PdfSearchResultItem>[]);

    if (!kIsWeb && _totalPages > 0) {
      _nativeSearchResult.removeListener(_onNativeSearchChanged);
      _nativeSearchResult.clear();
      _nativeSearchResult = await _pdfController.searchText(normalizedQuery);
      _nativeSearchResult.addListener(_onNativeSearchChanged);
    }

    if (!mounted) return;

    setState(() {
      _isSearching = false;
      _searchResults = results;
      _webSearchTerm = normalizedQuery;
    });

    if (results.isEmpty) {
      _showElegantToast(icon: Icons.search_off_rounded, message: 'Nenhum resultado indexado para "$normalizedQuery".');
      return;
    }

    _openResultsSheet();
  }

  /// Limpa busca e resultados.
  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _webSearchTerm = '';
      _searchResults = const <PdfSearchResultItem>[];
    });
    if (!kIsWeb) _nativeSearchResult.clear();
  }

  /// Aumenta o zoom do PDF em passos de 25%, limitado entre 50% e 400%.
  void _zoomIn() => _setZoom(((_zoom + 0.25).clamp(0.5, 4.0) as num).toDouble());

  /// Reduz o zoom do PDF em passos de 25%, limitado entre 50% e 400%.
  void _zoomOut() => _setZoom(((_zoom - 0.25).clamp(0.5, 4.0) as num).toDouble());

  void _setZoom(double value) {
    setState(() {
      _displayMode = _PdfDisplayMode.customZoom;
      _zoom = (value.clamp(0.5, 4.0) as num).toDouble();
      if (!kIsWeb) _pdfController.zoomLevel = _zoom;
      if (kIsWeb) _webNavigationToken = DateTime.now().microsecondsSinceEpoch;
    });
  }

  void _setDisplayMode(_PdfDisplayMode mode) {
    setState(() {
      _displayMode = mode;
      switch (mode) {
        case _PdfDisplayMode.fitPage:
          _zoom = 1.0;
          break;
        case _PdfDisplayMode.fitWidth:
          _zoom = 1.0;
          break;
        case _PdfDisplayMode.customZoom:
          _zoom = (_zoom.clamp(0.5, 4.0) as num).toDouble();
          break;
      }
      if (!kIsWeb) _pdfController.zoomLevel = _zoom;
      if (kIsWeb) _webNavigationToken = DateTime.now().microsecondsSinceEpoch;
    });

    final label = switch (mode) {
      _PdfDisplayMode.fitPage => 'Página ajustada à janela.',
      _PdfDisplayMode.fitWidth => 'Página ajustada à largura.',
      _PdfDisplayMode.customZoom => 'Zoom personalizado ativado.',
    };
    _showElegantToast(icon: Icons.fit_screen_rounded, message: label);
  }

  /// Avança para a próxima página.
  void _nextPage() {
    if (_currentPage >= _totalPages) return;
    if (kIsWeb) {
      _goToPage(_currentPage + 1);
    } else {
      _pdfController.nextPage();
    }
  }

  /// Volta para a página anterior.
  void _previousPage() {
    if (_currentPage <= 1) return;
    if (kIsWeb) {
      _goToPage(_currentPage - 1);
    } else {
      _pdfController.previousPage();
    }
  }

  /// Navega para a página digitada.
  void _jumpToPage() {
    final page = int.tryParse(_pageController.text);
    if (page == null) return;
    _goToPage(page);
  }

  /// Centraliza a navegação de página para Web e nativo.
  ///
  /// No Flutter Web, o visualizador nativo do navegador pode reaproveitar
  /// o estado anterior do iframe e ignorar o fragmento . Por isso,
  /// sempre que a navegação é solicitada, um token único é renovado e enviado
  /// antes do fragmento da URL. Isso força o iframe a recarregar exatamente
  /// na página escolhida pelo resultado da busca ou pelo campo de página.
  void _goToPage(int page) {
    if (page < 1 || page > _totalPages) return;

    setState(() {
      _currentPage = page;
      _pageController.text = page.toString();

      if (kIsWeb) {
        _webNavigationToken = DateTime.now().microsecondsSinceEpoch;
      }
    });

    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pdfController.jumpToPage(page);
      });
    }
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _loadEditsForCurrentPage();
    });
  }

  /// Alterna entre rolagem vertical e horizontal.
  void _toggleNavigationMode() {
    setState(() => _isHorizontalNavigation = !_isHorizontalNavigation);
    _showElegantToast(
      icon: _isHorizontalNavigation ? Icons.swap_horiz_rounded : Icons.swap_vert_rounded,
      message: _isHorizontalNavigation ? 'Navegação horizontal ativada.' : 'Navegação vertical ativada.',
    );
  }

  /// Favorita ou remove a página atual dos favoritos, salvando uma prévia.
  Future<void> _toggleCurrentPageFavorite() async {
    HapticFeedback.mediumImpact();
    final repository = ref.read(pdfRepositoryProvider);
    final added = await repository.togglePageFavorite(document: widget.document, page: _currentPage);
    final preview = await repository.getPagePreview(file: widget.document.file, page: _currentPage);

    if (!mounted) return;

    setState(() {
      if (added) {
        _favoritePages.add(_currentPage);
      } else {
        _favoritePages.remove(_currentPage);
      }
    });

    _showElegantToast(
      icon: added ? Icons.bookmark_added_rounded : Icons.bookmark_remove_rounded,
      message: added ? 'Página $_currentPage salva: $preview' : 'Página $_currentPage removida dos favoritos.',
    );
  }

  Future<void> _removeFavoritePage(FavoritePdfPage item) async {
    await ref.read(pdfRepositoryProvider).togglePageFavorite(document: widget.document, page: item.page);
    await _loadFavoritePagesForCurrentDocument();
    if (mounted) {
      _showElegantToast(icon: Icons.bookmark_remove_rounded, message: 'Página ${item.page} removida dos favoritos.');
    }
  }

  void _setEditTool(_PdfEditTool tool) {
    setState(() => _editTool = tool);
    _showElegantToast(
      icon: _iconForEditTool(tool),
      message: tool == _PdfEditTool.none ? 'Edição desativada.' : 'Ferramenta de edição ativada.',
    );
  }

  IconData _iconForEditTool(_PdfEditTool tool) {
    switch (tool) {
      case _PdfEditTool.highlight:
        return Icons.format_color_fill_rounded;
      case _PdfEditTool.draw:
        return Icons.draw_rounded;
      case _PdfEditTool.text:
        return Icons.text_fields_rounded;
      case _PdfEditTool.rectangle:
        return Icons.crop_square_rounded;
      case _PdfEditTool.circle:
        return Icons.circle_outlined;
      case _PdfEditTool.none:
        return Icons.edit_off_rounded;
    }
  }

  void _clearEdits() {
    setState(() => _editMarks.clear());
    _saveEditsForCurrentPage();
    _showUndoToast(icon: Icons.cleaning_services_rounded, message: 'Marcações limpas.', actionLabel: 'OK', onUndo: () {});
  }

  void _fitPageWidth() => _setDisplayMode(_PdfDisplayMode.fitWidth);

  void _fitPageToWindow() => _setDisplayMode(_PdfDisplayMode.fitPage);

  void _toggleFullScreen() {
    setState(() => _fullScreen = !_fullScreen);
    _showElegantToast(icon: Icons.fullscreen_rounded, message: _fullScreen ? 'Tela cheia ativada.' : 'Tela cheia desativada.');
  }

  Future<void> _addTextAnnotation() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adicionar texto'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Digite a anotação'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Adicionar')),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty) return;
    setState(() {
      _editMarks.add(_EditMark(
        tool: _PdfEditTool.text,
        points: const [Offset(80, 160)],
        color: _editColor,
        strokeWidth: _editStrokeWidth,
        text: text.trim(),
      ));
      _editTool = _PdfEditTool.none;
    });
    await _saveEditsForCurrentPage();
    _showElegantToast(icon: Icons.text_fields_rounded, message: 'Texto adicionado.');
  }

  /// Normaliza nomes para arquivos compartilhados.
  String _safeFileName(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\-_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  /// Gera um PDF contendo somente a página atual.
  ///
  /// O arquivo é montado em memória a partir do PDF original e compartilhado
  /// via `share_plus`, sem depender de caminho físico local.
  Future<Uint8List> _buildCurrentPagePdfBytes() async {
    final sourceBytes = await _pdfBytesFuture;
    final sourceDocument = sfpdf.PdfDocument(inputBytes: sourceBytes);
    final pageIndex = (_currentPage - 1).clamp(0, sourceDocument.pages.count - 1).toInt();
    final sourcePage = sourceDocument.pages[pageIndex];
    final template = sourcePage.createTemplate();

    final outputDocument = sfpdf.PdfDocument();
    outputDocument.pageSettings.margins.all = 0;
    outputDocument.pageSettings.size = template.size;

    final outputPage = outputDocument.pages.add();
    outputPage.graphics.drawPdfTemplate(template, Offset.zero);

    final bytes = await outputDocument.save();
    sourceDocument.dispose();
    outputDocument.dispose();

    return Uint8List.fromList(bytes);
  }

  /// Renderiza a página atual como PNG.
  ///
  /// A página é primeiro isolada em um PDF temporário e depois rasterizada.
  Future<Uint8List> _buildCurrentPagePngBytes() async {
    final pagePdfBytes = await _buildCurrentPagePdfBytes();

    await for (final raster in Printing.raster(pagePdfBytes, dpi: 144)) {
      return await raster.toPng();
    }

    throw StateError("Não foi possível gerar a imagem da página.");
  }

  /// Compartilha a página atual como PDF/PNG ou o documento inteiro em PDF.
  Future<void> _shareFile({required _ShareTarget target}) async {
    try {
      final safeTitle = _safeFileName(widget.document.title);
      final baseName = safeTitle.isEmpty ? "normativo" : safeTitle;

      final Uint8List bytes;
      final String fileName;
      final String mimeType;
      final String subject;

      switch (target) {
        case _ShareTarget.currentPagePdf:
          bytes = await _buildCurrentPagePdfBytes();
          fileName = "${baseName}_pagina_$_currentPage.pdf";
          mimeType = "application/pdf";
          subject = "${widget.document.title} — página $_currentPage em PDF";
          break;
        case _ShareTarget.currentPagePng:
          bytes = await _buildCurrentPagePngBytes();
          fileName = "${baseName}_pagina_$_currentPage.png";
          mimeType = "image/png";
          subject = "${widget.document.title} — página $_currentPage em PNG";
          break;
        case _ShareTarget.fullDocumentPdf:
          bytes = await _pdfBytesFuture;
          fileName = "${baseName}_completo.pdf";
          mimeType = "application/pdf";
          subject = "${widget.document.title} — documento completo";
          break;
      }

      await Share.shareXFiles(
        [XFile.fromData(bytes, name: fileName, mimeType: mimeType)],
        subject: subject,
        text: subject,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Não foi possível compartilhar o arquivo: $error")),
      );
    }
  }

  /// Abre opções de compartilhamento ao pressionar a página.
  void _openPageActionsSheet() {
    HapticFeedback.selectionClick();
    setState(() => _isAnySheetOpen = true);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: Text('Página $_currentPage em PDF'),
                subtitle: const Text('Compartilha somente esta página.'),
                onTap: () {
                  Navigator.of(context).pop();
                  _shareFile(target: _ShareTarget.currentPagePdf);
                },
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: Text('Página $_currentPage em PNG'),
                subtitle: const Text('Compartilha esta página como imagem.'),
                onTap: () {
                  Navigator.of(context).pop();
                  _shareFile(target: _ShareTarget.currentPagePng);
                },
              ),
              ListTile(
                leading: const Icon(Icons.library_books_outlined),
                title: const Text('Documento completo'),
                subtitle: const Text('Compartilha o PDF original.'),
                onTap: () {
                  Navigator.of(context).pop();
                  _shareFile(target: _ShareTarget.fullDocumentPdf);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: const Text('Favoritar página'),
                subtitle: const Text('Salva com prévia textual.'),
                onTap: () {
                  Navigator.of(context).pop();
                  _toggleCurrentPageFavorite();
                },
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      if (mounted) setState(() => _isAnySheetOpen = false);
    });
  }

  /// Abre uma folha inferior com os resultados encontrados.
  void _openResultsSheet() {
    if (_searchResults.isEmpty) return;

    setState(() => _isAnySheetOpen = true);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (context) {
        final height = MediaQuery.sizeOf(context).height;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: height * 0.86),
          child: _SearchResultsList(
            results: _searchResults,
            query: _searchController.text,
            onClose: () => Navigator.of(context).pop(),
            onTapResult: (result) {
              final targetPage = result.page;
              Navigator.of(context).pop();

              // Aguarda o fechamento da folha inferior antes de recriar o
              // iframe. Isso evita corrida entre o modal e o viewer Web.
              Future<void>.delayed(const Duration(milliseconds: 180), () {
                if (mounted) _goToPage(targetPage);
              });
            },
          ),
        );
      },
    ).whenComplete(() {
      if (mounted) setState(() => _isAnySheetOpen = false);
    });
  }

  /// Exibe as páginas favoritas do documento atual.
  void _openFavoritePagesSheet() {
    setState(() => _isAnySheetOpen = true);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (context) {
        return FutureBuilder<List<FavoritePdfPage>>(
          future: ref.read(pdfRepositoryProvider).getFavoritePages(),
          builder: (context, snapshot) {
            final items = (snapshot.data ?? const <FavoritePdfPage>[])
                .where((item) => item.file == widget.document.file)
                .toList();

            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.78),
              child: _FavoritePagesList(
                items: items,
                onLongPress: (item) async {
                  await _removeFavoritePage(item);
                  if (context.mounted) Navigator.of(context).pop();
                  Future<void>.delayed(const Duration(milliseconds: 160), _openFavoritePagesSheet);
                },
                onTap: (item) {
                  final targetPage = item.page;
                  Navigator.of(context).pop();
                  Future<void>.delayed(const Duration(milliseconds: 180), () {
                    if (mounted) _goToPage(targetPage);
                  });
                },
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      if (mounted) setState(() => _isAnySheetOpen = false);
    });
  }

  void _insertAtCursor(TextEditingController controller, String value) {
    final selection = controller.selection;
    final text = controller.text;
    if (!selection.isValid) {
      controller.text = '$text$value';
      controller.selection = TextSelection.collapsed(offset: controller.text.length);
      return;
    }
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    final next = text.replaceRange(start, end, value);
    controller.text = next;
    controller.selection = TextSelection.collapsed(offset: start + value.length);
  }

  void _formatSelectionOrInsert(TextEditingController controller, String before, String after, {String placeholder = 'texto'}) {
    final selection = controller.selection;
    final text = controller.text;
    if (!selection.isValid || selection.isCollapsed) {
      final value = '$before$placeholder$after';
      _insertAtCursor(controller, value);
      final cursor = controller.selection.baseOffset;
      final start = (cursor - after.length - placeholder.length).clamp(0, controller.text.length);
      final end = (cursor - after.length).clamp(0, controller.text.length);
      controller.selection = TextSelection(baseOffset: start, extentOffset: end);
      return;
    }
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    final selected = text.substring(start, end);
    final next = text.replaceRange(start, end, '$before$selected$after');
    controller.text = next;
    controller.selection = TextSelection(baseOffset: start + before.length, extentOffset: start + before.length + selected.length);
  }

  Future<void> _openIconGallery(TextEditingController controller) async {
    final icons = <String>['⭐', '📌', '📎', '📚', '⚠️', '✅', '❗', '💡', '🔎', '📝', '📅', '➡️', '⬅️', '🔵', '🟢', '🟡', '🔴'];
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Galeria de ícones', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final icon in icons)
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(context).pop(icon),
                    child: Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF4FF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF9CCBFF)),
                      ),
                      child: Text(icon, style: const TextStyle(fontSize: 24)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (selected != null) _insertAtCursor(controller, '$selected ');
  }

  /// Abre um post-it robusto da página atual.
  ///
  /// Quando [entry] é informado, abre o post-it existente. Sem [entry], cria
  /// um novo post-it na mesma página, permitindo vários registros por página.
  void _openPostItSheet({_PostItEntry? entry}) {
    final postItId = entry?.id ?? 'postit_${DateTime.now().microsecondsSinceEpoch}';
    final existing = entry?.text ?? '';
    var data = _PostItData.fromStored(existing);

    final titleController = TextEditingController(text: data.title);
    final controller = TextEditingController(text: data.body);
    var selectedColor = data.color;
    var imageBase64 = data.imageBase64;
    var imageName = data.imageName;
    var showMoreColors = false;
    bool editing = data.isEmpty;

    Future<void> attachImage(void Function(void Function()) setSheetState) async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.first;
      final bytes = picked.bytes;
      if (bytes == null || bytes.isEmpty) {
        _showElegantToast(icon: Icons.image_not_supported_outlined, message: 'Não foi possível anexar a imagem.');
        return;
      }
      setSheetState(() {
        imageBase64 = base64Encode(bytes);
        imageName = picked.name;
      });
    }

    Future<void> saveCurrent() async {
      final next = _PostItData(
        title: titleController.text.trim(),
        body: controller.text.trim(),
        colorValue: selectedColor.value,
        imageName: imageName,
        imageBase64: imageBase64,
      );
      final text = next.isEmpty ? '' : next.toStored();
      await ref.read(pdfRepositoryProvider).savePagePostIt(file: widget.document.file, page: _currentPage, id: postItId, text: text);
      if (!mounted) return;
      setState(() {
        final list = List<_PostItEntry>.from(_postIts[_currentPage] ?? const <_PostItEntry>[]);
        list.removeWhere((item) => item.id == postItId);
        if (text.isNotEmpty) list.add(_PostItEntry(id: postItId, page: _currentPage, text: text));
        if (list.isEmpty) {
          _postIts.remove(_currentPage);
        } else {
          _postIts[_currentPage] = list;
        }
      });
      _showElegantToast(icon: Icons.sticky_note_2_rounded, message: 'Post-it salvo na página $_currentPage.');
    }

    setState(() => _isAnySheetOpen = true);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final bottom = MediaQuery.viewInsetsOf(context).bottom;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            data = _PostItData(
              title: titleController.text.trim(),
              body: controller.text,
              colorValue: selectedColor.value,
              imageName: imageName,
              imageBase64: imageBase64,
            );

            Future<void> toggleTask(int lineIndex) async {
              final lines = controller.text.split('\n');
              if (lineIndex < 0 || lineIndex >= lines.length) return;
              if (lines[lineIndex].startsWith('☐ ')) {
                lines[lineIndex] = lines[lineIndex].replaceFirst('☐ ', '☑ ');
              } else if (lines[lineIndex].startsWith('☑ ')) {
                lines[lineIndex] = lines[lineIndex].replaceFirst('☑ ', '☐ ');
              }
              controller.text = lines.join('\n');
              await saveCurrent();
              setSheetState(() {});
            }

            return AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.fromLTRB(16, 0, 16, 18 + bottom),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: selectedColor,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 24, offset: const Offset(0, 12))],
                ),
                child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.sticky_note_2_rounded, color: Color(0xFF9A6B00)),
                      const SizedBox(width: 10),
                      Expanded(child: Text('Post-it da página $_currentPage', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                      IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
                    ]),
                    const SizedBox(height: 8),
                    if (!editing)
                      GestureDetector(
                        onTap: () => setSheetState(() => editing = true),
                        child: _PostItCardView(data: data, onToggleTask: toggleTask),
                      )
                    else ...[
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final color in [
                          const Color(0xFFFFF8CF),
                          const Color(0xFFEAF4FF),
                          const Color(0xFFEAFBE7),
                          const Color(0xFFFFE8F4),
                          const Color(0xFFEDE7FF),
                          if (showMoreColors) ...const [
                            Color(0xFFFFE0B2),
                            Color(0xFFE0F7FA),
                            Color(0xFFFFCDD2),
                            Color(0xFFE8F5E9),
                            Color(0xFFF3E5F5),
                          ],
                        ])
                          ChoiceChip(
                            selected: selectedColor.value == color.value,
                            label: const SizedBox(width: 8),
                            avatar: CircleAvatar(backgroundColor: color),
                            onSelected: (_) => setSheetState(() => selectedColor = color),
                            visualDensity: VisualDensity.compact,
                          ),
                        ActionChip(
                          avatar: Icon(showMoreColors ? Icons.remove_rounded : Icons.add_rounded, color: const Color(0xFF0B5CAD)),
                          label: Text(showMoreColors ? 'menos' : 'cores'),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setSheetState(() => showMoreColors = !showMoreColors),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      TextField(
                        controller: titleController,
                        decoration: InputDecoration(labelText: 'Título do post-it', prefixIcon: const Icon(Icons.title_rounded), filled: true, fillColor: Colors.white.withOpacity(0.78), border: OutlineInputBorder(borderRadius: BorderRadius.circular(18))),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        minLines: 6,
                        maxLines: 12,
                        decoration: InputDecoration(hintText: 'Observação, resumo, alerta ou lembrete desta página...', filled: true, fillColor: Colors.white.withOpacity(0.78), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20))),
                      ),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        ActionChip(avatar: const Icon(Icons.format_bold, color: Color(0xFF1565C0)), label: const Text('B'), onPressed: () => setSheetState(() => _formatSelectionOrInsert(controller, '**', '**'))),
                        ActionChip(avatar: const Icon(Icons.format_italic, color: Color(0xFF5E35B1)), label: const Text('I'), onPressed: () => setSheetState(() => _formatSelectionOrInsert(controller, '_', '_'))),
                        ActionChip(avatar: const Icon(Icons.format_underlined, color: Color(0xFF00838F)), label: const Text('U'), onPressed: () => setSheetState(() => _formatSelectionOrInsert(controller, '<u>', '</u>'))),
                        ActionChip(avatar: const Icon(Icons.format_list_bulleted, color: Color(0xFF2E7D32)), label: const Text('Lista'), onPressed: () => setSheetState(() => _insertAtCursor(controller, '\n• '))),
                        ActionChip(avatar: const Icon(Icons.image_outlined, color: Color(0xFF0277BD)), label: Text(imageName == null ? 'Imagem' : 'Trocar imagem'), onPressed: () => attachImage(setSheetState)),
                        ActionChip(avatar: const Icon(Icons.emoji_symbols_rounded, color: Color(0xFFE65100)), label: const Text('Ícones'), onPressed: () async { await _openIconGallery(controller); setSheetState(() {}); }),
                        if (imageBase64 != null)
                          ActionChip(
                            avatar: const Icon(Icons.delete_outline),
                            label: const Text('Remover imagem'),
                            onPressed: () => setSheetState(() {
                              imageBase64 = null;
                              imageName = null;
                            }),
                          ),
                      ]),
                      if (imageBase64 != null) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.memory(base64Decode(imageBase64!), height: 120, width: double.infinity, fit: BoxFit.cover),
                        ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    Row(children: [
                      TextButton.icon(onPressed: () async {
                        await ref.read(pdfRepositoryProvider).savePagePostIt(file: widget.document.file, page: _currentPage, id: postItId, text: '');
                        setState(() {
                          final list = List<_PostItEntry>.from(_postIts[_currentPage] ?? const <_PostItEntry>[]);
                          list.removeWhere((item) => item.id == postItId);
                          list.isEmpty ? _postIts.remove(_currentPage) : _postIts[_currentPage] = list;
                        });
                        if (context.mounted) Navigator.of(context).pop();
                        _showUndoToast(icon: Icons.delete_outline_rounded, message: 'Post-it removido.', actionLabel: 'DESFAZER', onUndo: () async {
                          if (existing.trim().isEmpty) return;
                          await ref.read(pdfRepositoryProvider).savePagePostIt(file: widget.document.file, page: _currentPage, id: postItId, text: existing);
                          await _loadPostItsForCurrentDocument();
                        });
                      }, icon: const Icon(Icons.delete_outline_rounded), label: const Text('Remover')),
                      const Spacer(),
                      if (!editing)
                        FilledButton.tonalIcon(onPressed: () => setSheetState(() => editing = true), icon: const Icon(Icons.edit_rounded), label: const Text('Editar')),
                      if (editing)
                        FilledButton.icon(onPressed: () async {
                          await saveCurrent();
                          if (context.mounted) Navigator.of(context).pop();
                        }, icon: const Icon(Icons.save_rounded), label: const Text('Salvar')),
                    ]),
                  ]),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      titleController.dispose();
      controller.dispose();
      if (mounted) setState(() => _isAnySheetOpen = false);
    });
  }

  void _openPdfToolsSheet() {
    setState(() => _isAnySheetOpen = true);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
        child: ListView(shrinkWrap: true, children: [
          ListTile(leading: const Icon(Icons.format_color_fill_rounded), title: const Text('Realçar textos'), subtitle: const Text('Marca visual aplicada na página atual.'), onTap: () { Navigator.of(context).pop(); _setEditTool(_PdfEditTool.highlight); }),
          ListTile(leading: const Icon(Icons.draw_rounded), title: const Text('Desenhar'), onTap: () { Navigator.of(context).pop(); _setEditTool(_PdfEditTool.draw); }),
          ListTile(leading: const Icon(Icons.text_fields_rounded), title: const Text('Adicionar texto'), onTap: () { Navigator.of(context).pop(); Future<void>.delayed(const Duration(milliseconds: 120), _addTextAnnotation); }),
          ListTile(leading: const Icon(Icons.category_outlined), title: const Text('Adicionar formas'), subtitle: const Text('Retângulo ou círculo.'), onTap: () { Navigator.of(context).pop(); Future<void>.delayed(const Duration(milliseconds: 120), _openShapesSheet); }),
          ListTile(leading: const Icon(Icons.cleaning_services_outlined), title: const Text('Limpar formatações'), onTap: () { Navigator.of(context).pop(); _clearEdits(); }),
          const Divider(),
          ListTile(leading: const Icon(Icons.screen_rotation_alt_rounded), title: const Text('Orientação da página'), subtitle: const Text('Alterna vertical/horizontal.'), onTap: () { Navigator.of(context).pop(); _toggleNavigationMode(); }),
          ListTile(leading: const Icon(Icons.fit_screen_rounded), title: const Text('Ajustar largura da página'), onTap: () { Navigator.of(context).pop(); _fitPageWidth(); }),
          ListTile(leading: Icon(_fullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded), title: Text(_fullScreen ? 'Sair da tela cheia' : 'Tela cheia'), onTap: () { Navigator.of(context).pop(); _toggleFullScreen(); }),
        ]),
      ),
    ).whenComplete(() { if (mounted) setState(() => _isAnySheetOpen = false); });
  }

  void _openPostItsListSheet() {
    setState(() => _isAnySheetOpen = true);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        final entries = _postIts.entries
            .expand((entry) => entry.value.map((postIt) => postIt))
            .toList()
          ..sort((a, b) {
            if (a.page != b.page) return a.page.compareTo(b.page);
            return a.id.compareTo(b.id);
          });
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.78),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Icon(Icons.sticky_note_2_rounded, color: Color(0xFF9A6B00)),
                const SizedBox(width: 10),
                Expanded(child: Text('Post-its do PDF', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                IconButton(
                  tooltip: 'Novo post-it nesta página',
                  onPressed: () {
                    Navigator.of(context).pop();
                    Future<void>.delayed(const Duration(milliseconds: 180), () => _openPostItSheet());
                  },
                  icon: const Icon(Icons.add_rounded),
                ),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
              ]),
              if (entries.isEmpty)
                const Padding(padding: EdgeInsets.all(18), child: Text('Nenhum post-it criado neste PDF.'))
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final preview = _postItPreviewText(entry.text);
                      return ListTile(
                        leading: Badge(label: Text('${entry.page}'), child: const Icon(Icons.sticky_note_2_rounded)),
                        title: Text('Página ${entry.page} • Post-it ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(preview, maxLines: 3, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.edit_note_rounded),
                        onTap: () {
                          Navigator.of(context).pop();
                          Future<void>.delayed(const Duration(milliseconds: 180), () {
                            if (!mounted) return;
                            _goToPage(entry.page);
                            _openPostItSheet(entry: entry);
                          });
                        },
                      );
                    },
                  ),
                ),
            ]),
          ),
        );
      },
    ).whenComplete(() { if (mounted) setState(() => _isAnySheetOpen = false); });
  }

  void _openMoreSheet() {
    setState(() => _isAnySheetOpen = true);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
          child: ListView(
            shrinkWrap: true,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.swap_vert),
                title: const Text('Navegação horizontal'),
                subtitle: const Text('Alterna o sentido de leitura.'),
                value: _isHorizontalNavigation,
                onChanged: (_) {
                  Navigator.of(context).pop();
                  _toggleNavigationMode();
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Compartilhar'),
                subtitle: const Text('Página em PDF/PNG ou documento completo.'),
                onTap: () {
                  Navigator.of(context).pop();
                  Future<void>.delayed(const Duration(milliseconds: 120), _openPageActionsSheet);
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmarks_outlined),
                title: const Text('Páginas favoritas'),
                onTap: () {
                  Navigator.of(context).pop();
                  Future<void>.delayed(const Duration(milliseconds: 120), _openFavoritePagesSheet);
                },
              ),
              ListTile(
                leading: const Icon(Icons.speaker_notes_rounded),
                title: const Text('Lista de post-its'),
                subtitle: const Text('Ver todas as anotações deste PDF.'),
                onTap: () { Navigator.of(context).pop(); Future<void>.delayed(const Duration(milliseconds: 120), _openPostItsListSheet); },
              ),
              ListTile(
                leading: Icon(_hasPostItsOnCurrentPage() ? Icons.sticky_note_2_rounded : Icons.sticky_note_2_outlined),
                title: const Text('Adicionar novo post-it'),
                subtitle: Text('Página $_currentPage'),
                onTap: () {
                  Navigator.of(context).pop();
                  Future<void>.delayed(const Duration(milliseconds: 120), _openPostItSheet);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: const Text('Desenvolvedor'),
                subtitle: const Text(
                  'Eu, Hagliberto Alves de Oliveira, desenvolvi o Folhear para facilitar minha rotina de estudo, consulta e organização de documentos. O aplicativo reúne biblioteca, pastas, favoritos, busca, post-its e compartilhamento em uma experiência pensada para uso rápido no celular e no desktop.',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.new_releases_outlined),
                title: const Text('Versão do aplicativo'),
                subtitle: const Text('${AppInfo.name} ${AppInfo.version} • ${AppInfo.releaseNote} • Atualizada em ${AppInfo.versionDate}'),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: Text(widget.document.title),
                subtitle: Text('${widget.document.version} • ${widget.document.pageCount} páginas'),
              ),
              ListTile(
                leading: const Icon(Icons.restart_alt_rounded),
                title: const Text('Resetar configurações'),
                subtitle: const Text('Remove favoritos, páginas salvas e preferências locais.'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await ref.read(pdfRepositoryProvider).resetApplicationSettings();
                  await _loadFavoritePagesForCurrentDocument();
                  if (mounted) _showElegantToast(icon: Icons.check_circle_rounded, message: 'Configurações resetadas.');
                },
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      if (mounted) setState(() => _isAnySheetOpen = false);
    });
  }

  void _openShapesSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.crop_square_rounded),
              title: const Text('Retângulo'),
              onTap: () { Navigator.of(context).pop(); _setEditTool(_PdfEditTool.rectangle); },
            ),
            ListTile(
              leading: const Icon(Icons.circle_outlined),
              title: const Text('Círculo'),
              onTap: () { Navigator.of(context).pop(); _setEditTool(_PdfEditTool.circle); },
            ),
          ],
        ),
      ),
    );
  }

  void _openQuickActions() {
    setState(() => _isQuickActionsOpen = !_isQuickActionsOpen);
  }

  void _closeQuickActions() {
    if (_isQuickActionsOpen) setState(() => _isQuickActionsOpen = false);
  }

  void _openSearch() {
    setState(() {
      _isSearchOpen = true;
      _isQuickActionsOpen = false;
    });
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searchController.clear();
    _clearSearch();
    setState(() {
      _isSearchOpen = false;
      _isQuickActionsOpen = false;
    });
    _searchFocus.unfocus();
  }

  void _onNavTap(int index) {
    if (_isSearchOpen) _closeSearch();
    setState(() => _selectedNavIndex = index);

    switch (index) {
      case 0:
        Navigator.of(context).maybePop();
        break;
      case 1:
        _openFavoritePagesSheet();
        break;
      case 2:
        _openMoreSheet();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 700;

    return Scaffold(
      appBar: _fullScreen ? null : AppBar(
        toolbarHeight: isMobile ? 48 : 60,
        titleSpacing: 0,
        title: Row(
          children: [
            Expanded(child: Text(widget.document.title, style: const TextStyle(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
            if (_hasPostItsOnCurrentPage())
              IconButton(
                tooltip: 'Listar post-its da página',
                onPressed: _openPostItsListSheet,
                icon: const Icon(Icons.sticky_note_2_rounded),
              ),
            if (_favoritePages.contains(_currentPage))
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Badge(label: Text('★'), child: Icon(Icons.bookmark_rounded, size: 18)),
              ),
          ],
        ),
        actions: [          IconButton(
            tooltip: 'Favoritar página',
            onPressed: _toggleCurrentPageFavorite,
            icon: Icon(_favoritePages.contains(_currentPage) ? Icons.bookmark_rounded : Icons.bookmark_add_outlined),
          ),
          IconButton(
            tooltip: 'Compartilhar',
            onPressed: _openPageActionsSheet,
            icon: const Icon(Icons.share_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
        children: [
          if (!_fullScreen)
          _PdfToolbar(
            currentPage: _currentPage,
            totalPages: _totalPages,
            zoom: _zoom,
            displayMode: _displayMode,
            onSetZoom: _setZoom,
            onSetDisplayMode: _setDisplayMode,
            isHorizontalNavigation: _isHorizontalNavigation,
            pageController: _pageController,
            resultsCount: _searchResults.length,
            onPreviousPage: _previousPage,
            onNextPage: _nextPage,
            onJumpToPage: _jumpToPage,
            onZoomOut: _zoomOut,
            onZoomIn: _zoomIn,
            onToggleNavigationMode: _toggleNavigationMode,
            onOpenResults: _openResultsSheet,
          ),
          Expanded(
            child: _EditablePdfSurface(
              editTool: _PdfEditTool.none,
              editColor: _editColor,
              strokeWidth: _editStrokeWidth,
              marks: const <_EditMark>[],
              currentStroke: const <Offset>[],
              onChanged: () {},
              onAddMark: (_) {},
              onSelectTool: (_) {},
              onColorChanged: (_) {},
              onStopEditing: () {},
              onDoubleTap: _toggleCurrentPageFavorite,
              onLongPress: _openPageActionsSheet,
              child: kIsWeb
                  ? WebPdfViewerFrame(
                      key: ValueKey('${widget.document.assetPath}-$_currentPage-$_zoom-$_webSearchTerm-$_isAnySheetOpen-$_webNavigationToken'),
                      assetPath: widget.document.assetPath,
                      page: _currentPage,
                      zoom: _zoom,
                      displayMode: _displayMode.name,
                      searchTerm: _webSearchTerm,
                      localBase64: widget.document.localBase64,
                      reloadToken: _webNavigationToken,
                      allowPointerEvents: !(_isAnySheetOpen || _isSearchOpen),
                      onDoubleTapPage: _toggleCurrentPageFavorite,
                      onLongPressPage: _openPageActionsSheet,
                    )
                  : _NativePdfViewer(
                      pdfBytesFuture: _pdfBytesFuture,
                      pdfController: _pdfController,
                      isHorizontalNavigation: _isHorizontalNavigation,
                      onDocumentLoaded: (pageCount) {
                        setState(() {
                          _totalPages = pageCount;
                          _currentPage = widget.initialPage.clamp(1, pageCount).toInt();
                          _pageController.text = _currentPage.toString();
                        });
                        if (widget.initialPage > 1) {
                          WidgetsBinding.instance.addPostFrameCallback((_) => _goToPage(widget.initialPage));
                        }
                      },
                      onPageChanged: (page) {
                        setState(() {
                          _currentPage = page;
                          _pageController.text = page.toString();
                        });
                        _loadEditsForCurrentPage();
                      },
                    ),
            ),
          ),
        ],
      ),
          if (_fullScreen)
            Positioned(
              top: 12,
              right: 12,
              child: SafeArea(
                child: IconButton.filled(
                  tooltip: 'Sair da tela cheia',
                  onPressed: _toggleFullScreen,
                  icon: const Icon(Icons.fullscreen_exit_rounded),
                ),
              ),
            ),
          if (_isSearchOpen)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _closeSearch();
                  FocusScope.of(context).unfocus();
                },
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _fullScreen ? null : AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: _ViewerBottomArea(
          controller: _searchController,
          focusNode: _searchFocus,
          selectedIndex: _selectedNavIndex,
          resultsCount: _searchResults.length,
          isSearching: _isSearching,
          searchOpen: _isSearchOpen,
          quickActionsOpen: _isQuickActionsOpen,
          onOpenActions: _openQuickActions,
          onOpenSearch: _openSearch,
          onFavoritePage: _toggleCurrentPageFavorite,
          onShare: _openPageActionsSheet,
          onToggleNavigationMode: _toggleNavigationMode,
          onFitPageWidth: _fitPageWidth,
          onToggleFullScreen: _toggleFullScreen,
          onOpenPostIt: _openPostItSheet,
          onOpenPostItsList: _openPostItsListSheet,
          isFullScreen: _fullScreen,
          onCloseSearch: _closeSearch,
          onSearch: _searchText,
          onClearSearch: _clearSearch,
          onNavTap: _onNavTap,
        ),
      ),
    );
  }
}


class _PostItCardView extends StatelessWidget {
  final _PostItData data;
  final ValueChanged<int> onToggleTask;

  const _PostItCardView({required this.data, required this.onToggleTask});

  String _cleanMarkdown(String value) {
    return value
        .replaceAll('**', '')
        .replaceAll('_', '')
        .replaceAll('<u>', '')
        .replaceAll('</u>', '');
  }

  TextStyle _styleFor(BuildContext context, String value) {
    return TextStyle(
      height: 1.35,
      fontSize: 14,
      fontWeight: value.contains('**') ? FontWeight.w800 : FontWeight.w400,
      fontStyle: value.contains('_') ? FontStyle.italic : FontStyle.normal,
      decoration: value.contains('<u>') ? TextDecoration.underline : TextDecoration.none,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = data.body.trim().isEmpty ? <String>['Toque para editar este post-it.'] : data.body.split('\n');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: data.color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE0C96C)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.push_pin_rounded, color: Color(0xFF9A6B00)),
          const SizedBox(width: 8),
          Expanded(child: Text(data.title.isEmpty ? 'Anotação da página' : data.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
          const Icon(Icons.edit_note_rounded),
        ]),
        const SizedBox(height: 12),
        for (var i = 0; i < lines.length; i++)
          if (lines[i].startsWith('☐ ') || lines[i].startsWith('☑ '))
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: lines[i].startsWith('☑ '),
              onChanged: (_) => onToggleTask(i),
              title: Text(_cleanMarkdown(lines[i].substring(2)), style: _styleFor(context, lines[i])),
              controlAffinity: ListTileControlAffinity.leading,
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(_cleanMarkdown(lines[i]), style: _styleFor(context, lines[i])),
            ),
        if (data.imageBase64 != null && data.imageBase64!.isNotEmpty) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.memory(base64Decode(data.imageBase64!), height: 160, width: double.infinity, fit: BoxFit.cover),
          ),
          if (data.imageName != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(data.imageName!, style: Theme.of(context).textTheme.labelSmall),
            ),
        ],
      ]),
    );
  }
}


/// Área sensível a duplo toque, pressão longa e marcações visuais sobre o PDF.
class _EditablePdfSurface extends StatelessWidget {
  final Widget child;
  final _PdfEditTool editTool;
  final Color editColor;
  final double strokeWidth;
  final List<_EditMark> marks;
  final List<Offset> currentStroke;
  final VoidCallback onChanged;
  final ValueChanged<_EditMark> onAddMark;
  final ValueChanged<_PdfEditTool> onSelectTool;
  final ValueChanged<Color> onColorChanged;
  final VoidCallback onStopEditing;
  final VoidCallback onDoubleTap;
  final VoidCallback onLongPress;

  const _EditablePdfSurface({
    required this.child,
    required this.editTool,
    required this.editColor,
    required this.strokeWidth,
    required this.marks,
    required this.currentStroke,
    required this.onChanged,
    required this.onAddMark,
    required this.onSelectTool,
    required this.onColorChanged,
    required this.onStopEditing,
    required this.onDoubleTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final editing = editTool != _PdfEditTool.none;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: editing ? null : onDoubleTap,
      onLongPress: editing ? null : onLongPress,
      onPanStart: editing
          ? (details) {
              currentStroke
                ..clear()
                ..add(details.localPosition);
              onChanged();
            }
          : null,
      onPanUpdate: editing
          ? (details) {
              currentStroke.add(details.localPosition);
              onChanged();
            }
          : null,
      onPanEnd: editing
          ? (_) {
              if (currentStroke.isNotEmpty) {
                onAddMark(_EditMark(
                  tool: editTool,
                  points: List<Offset>.from(currentStroke),
                  color: editColor,
                  strokeWidth: strokeWidth,
                ));
                currentStroke.clear();
                onChanged();
              }
            }
          : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          IgnorePointer(
            child: CustomPaint(
              painter: _PdfEditPainter(
                marks: marks,
                currentStroke: currentStroke,
                currentTool: editTool,
                color: editColor,
                strokeWidth: strokeWidth,
              ),
            ),
          ),
          if (editing)
            Positioned(
              left: 12,
              right: 12,
              bottom: 14,
              child: _InlinePdfEditToolbar(
                currentTool: editTool,
                currentColor: editColor,
                onSelectTool: onSelectTool,
                onColorChanged: onColorChanged,
                onStopEditing: onStopEditing,
              ),
            ),
        ],
      ),
    );
  }
}

class _InlinePdfEditToolbar extends StatelessWidget {
  final _PdfEditTool currentTool;
  final Color currentColor;
  final ValueChanged<_PdfEditTool> onSelectTool;
  final ValueChanged<Color> onColorChanged;
  final VoidCallback onStopEditing;

  const _InlinePdfEditToolbar({required this.currentTool, required this.currentColor, required this.onSelectTool, required this.onColorChanged, required this.onStopEditing});

  @override
  Widget build(BuildContext context) {
    final colors = <Color>[const Color(0xFFFFEB3B), const Color(0xFF64B5F6), const Color(0xFF81C784), const Color(0xFFE57373), const Color(0xFFBA68C8)];
    return Material(
      elevation: 10,
      color: const Color(0xFFF2F8FF),
      borderRadius: BorderRadius.circular(26),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.edit_rounded, color: Color(0xFF0B5CAD), size: 20),
            const SizedBox(width: 8),
            _EditToolButton(icon: Icons.format_color_fill_rounded, selected: currentTool == _PdfEditTool.highlight, tooltip: 'Realçar', onTap: () => onSelectTool(_PdfEditTool.highlight)),
            _EditToolButton(icon: Icons.draw_rounded, selected: currentTool == _PdfEditTool.draw, tooltip: 'Desenhar', onTap: () => onSelectTool(_PdfEditTool.draw)),
            _EditToolButton(icon: Icons.crop_square_rounded, selected: currentTool == _PdfEditTool.rectangle, tooltip: 'Retângulo', onTap: () => onSelectTool(_PdfEditTool.rectangle)),
            _EditToolButton(icon: Icons.circle_outlined, selected: currentTool == _PdfEditTool.circle, tooltip: 'Círculo', onTap: () => onSelectTool(_PdfEditTool.circle)),
            const SizedBox(width: 6),
            for (final color in colors) Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: InkWell(borderRadius: BorderRadius.circular(99), onTap: () => onColorChanged(color), child: Container(width: 24, height: 24, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: currentColor.value == color.value ? const Color(0xFF0B5CAD) : Colors.white, width: 3))))),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(onPressed: onStopEditing, icon: const Icon(Icons.check_rounded), label: const Text('Concluir')),
          ]),
        ),
      ),
    );
  }
}

class _EditToolButton extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;
  const _EditToolButton({required this.icon, required this.selected, required this.tooltip, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: IconButton.filledTonal(tooltip: tooltip, isSelected: selected, onPressed: onTap, icon: Icon(icon), style: IconButton.styleFrom(backgroundColor: selected ? const Color(0xFFD6E9FF) : const Color(0xFFEAF4FF), foregroundColor: const Color(0xFF0B5CAD))));
  }
}

class _PdfEditPainter extends CustomPainter {
  final List<_EditMark> marks;
  final List<Offset> currentStroke;
  final _PdfEditTool currentTool;
  final Color color;
  final double strokeWidth;

  const _PdfEditPainter({
    required this.marks,
    required this.currentStroke,
    required this.currentTool,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final mark in marks) {
      _drawMark(canvas, mark);
    }
    if (currentStroke.isNotEmpty && currentTool != _PdfEditTool.none) {
      _drawMark(canvas, _EditMark(tool: currentTool, points: currentStroke, color: color, strokeWidth: strokeWidth));
    }
  }

  void _drawMark(Canvas canvas, _EditMark mark) {
    if (mark.points.isEmpty) return;
    final paint = Paint()
      ..color = mark.tool == _PdfEditTool.highlight ? mark.color.withOpacity(0.36) : mark.color
      ..strokeWidth = mark.strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    switch (mark.tool) {
      case _PdfEditTool.highlight:
      case _PdfEditTool.draw:
        final path = Path()..moveTo(mark.points.first.dx, mark.points.first.dy);
        for (final point in mark.points.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(path, paint);
        break;
      case _PdfEditTool.rectangle:
        if (mark.points.length < 2) return;
        canvas.drawRect(Rect.fromPoints(mark.points.first, mark.points.last), paint);
        break;
      case _PdfEditTool.circle:
        if (mark.points.length < 2) return;
        canvas.drawOval(Rect.fromPoints(mark.points.first, mark.points.last), paint);
        break;
      case _PdfEditTool.text:
        final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 18, fontWeight: FontWeight.w700))
          ..pushStyle(ui.TextStyle(color: mark.color))
          ..addText(mark.text ?? 'Texto');
        final paragraph = paragraphBuilder.build()..layout(const ui.ParagraphConstraints(width: 260));
        canvas.drawParagraph(paragraph, mark.points.first);
        break;
      case _PdfEditTool.none:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _PdfEditPainter oldDelegate) => true;
}

/// Visualizador usado em Android, iOS e Desktop.
class _NativePdfViewer extends StatelessWidget {
  final Future<Uint8List> pdfBytesFuture;
  final PdfViewerController pdfController;
  final bool isHorizontalNavigation;
  final ValueChanged<int> onDocumentLoaded;
  final ValueChanged<int> onPageChanged;

  const _NativePdfViewer({
    required this.pdfBytesFuture,
    required this.pdfController,
    required this.isHorizontalNavigation,
    required this.onDocumentLoaded,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: pdfBytesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return _PdfLoadError(error: snapshot.error);
        }

        return SfPdfViewer.memory(
          snapshot.data!,
          key: ValueKey('native-pdf-${isHorizontalNavigation ? 'horizontal' : 'vertical'}'),
          controller: pdfController,
          canShowScrollHead: true,
          canShowScrollStatus: true,
          enableDoubleTapZooming: true,
          pageLayoutMode: isHorizontalNavigation ? PdfPageLayoutMode.single : PdfPageLayoutMode.continuous,
          scrollDirection: isHorizontalNavigation ? PdfScrollDirection.horizontal : PdfScrollDirection.vertical,
          onDocumentLoaded: (details) => onDocumentLoaded(details.document.pages.count),
          onPageChanged: (details) => onPageChanged(details.newPageNumber),
          onDocumentLoadFailed: (details) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Falha ao carregar PDF: ${details.description}')),
            );
          },
        );
      },
    );
  }
}

/// Mensagem exibida quando os bytes do PDF não são encontrados nos assets.
class _PdfLoadError extends StatelessWidget {
  final Object? error;

  const _PdfLoadError({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text('Não foi possível carregar o PDF.', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('$error', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Barra compacta de controle de página e zoom.
class _PdfToolbar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final double zoom;
  final _PdfDisplayMode displayMode;
  final ValueChanged<double> onSetZoom;
  final ValueChanged<_PdfDisplayMode> onSetDisplayMode;
  final bool isHorizontalNavigation;
  final TextEditingController pageController;
  final int resultsCount;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;
  final VoidCallback onJumpToPage;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onToggleNavigationMode;
  final VoidCallback onOpenResults;

  const _PdfToolbar({
    required this.currentPage,
    required this.totalPages,
    required this.zoom,
    required this.displayMode,
    required this.onSetZoom,
    required this.onSetDisplayMode,
    required this.isHorizontalNavigation,
    required this.pageController,
    required this.resultsCount,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onJumpToPage,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onToggleNavigationMode,
    required this.onOpenResults,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 1,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            children: [
              IconButton.filledTonal(
                tooltip: 'Página anterior',
                onPressed: currentPage > 1 ? onPreviousPage : null,
                icon: const Icon(Icons.chevron_left),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 58,
                height: 40,
                child: TextField(
                  controller: pageController,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => onJumpToPage(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(child: Text('/ ${totalPages == 0 ? '-' : totalPages}')),
              ),
              IconButton.filledTonal(
                tooltip: 'Próxima página',
                onPressed: currentPage < totalPages ? onNextPage : null,
                icon: const Icon(Icons.chevron_right),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              ActionChip(
                avatar: const Icon(Icons.remove, size: 16),
                label: Text('${(zoom * 100).round()}%'),
                onPressed: onZoomOut,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 6),
              PopupMenuButton<double>(
                tooltip: 'Selecionar zoom',
                onSelected: onSetZoom,
                itemBuilder: (context) => [
                  for (double value = 0.5; value <= 4.001; value += 0.25)
                    PopupMenuItem<double>(value: value, child: Text('${(value * 100).round()}%')),
                ],
                child: ActionChip(
                  avatar: const Icon(Icons.zoom_in_rounded, size: 16),
                  label: const Text('Zoom'),
                  onPressed: null,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 6),
              SegmentedButton<_PdfDisplayMode>(
                segments: const [
                  ButtonSegment(value: _PdfDisplayMode.fitPage, label: Text('Janela'), icon: Icon(Icons.fit_screen_rounded, size: 17)),
                  ButtonSegment(value: _PdfDisplayMode.fitWidth, label: Text('Largura'), icon: Icon(Icons.width_full_rounded, size: 17)),
                ],
                selected: {displayMode == _PdfDisplayMode.customZoom ? _PdfDisplayMode.fitWidth : displayMode},
                onSelectionChanged: (value) => onSetDisplayMode(value.first),
              ),
              const SizedBox(width: 6),
              FilterChip(
                selected: isHorizontalNavigation,
                avatar: Icon(isHorizontalNavigation ? Icons.swap_horiz : Icons.swap_vert, size: 17),
                label: Text(isHorizontalNavigation ? 'Horizontal' : 'Vertical'),
                onSelected: (_) => onToggleNavigationMode(),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 6),
              ActionChip(
                avatar: Badge.count(
                  count: resultsCount,
                  isLabelVisible: resultsCount > 0,
                  child: const Icon(Icons.format_list_bulleted, size: 17),
                ),
                label: const Text('Resultados'),
                onPressed: resultsCount > 0 ? onOpenResults : null,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Área inferior com busca expansível e navbar Material 3.
class _ViewerBottomArea extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final int selectedIndex;
  final int resultsCount;
  final bool isSearching;
  final bool searchOpen;
  final bool quickActionsOpen;
  final VoidCallback onOpenActions;
  final VoidCallback onOpenSearch;
  final VoidCallback onFavoritePage;
  final VoidCallback onShare;
  final VoidCallback onToggleNavigationMode;
  final VoidCallback onFitPageWidth;
  final VoidCallback onToggleFullScreen;
  final VoidCallback onOpenPostIt;
  final VoidCallback onOpenPostItsList;
  final bool isFullScreen;
  final VoidCallback onCloseSearch;
  final ValueChanged<String> onSearch;
  final VoidCallback onClearSearch;
  final ValueChanged<int> onNavTap;

  const _ViewerBottomArea({
    required this.controller,
    required this.focusNode,
    required this.selectedIndex,
    required this.resultsCount,
    required this.isSearching,
    required this.searchOpen,
    required this.quickActionsOpen,
    required this.onOpenActions,
    required this.onOpenSearch,
    required this.onFavoritePage,
    required this.onShare,
    required this.onToggleNavigationMode,
    required this.onFitPageWidth,
    required this.onToggleFullScreen,
    required this.onOpenPostIt,
    required this.onOpenPostItsList,
    required this.isFullScreen,
    required this.onCloseSearch,
    required this.onSearch,
    required this.onClearSearch,
    required this.onNavTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: searchOpen
                    ? SizedBox(
                        key: const ValueKey('viewer-search-field'),
                        height: 46,
                        child: SearchBar(
                          controller: controller,
                          focusNode: focusNode,
                          leading: const Icon(Icons.search),
                          hintText: 'Buscar no PDF',
                          onSubmitted: onSearch,
                          trailing: [
                            if (isSearching)
                              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            else if (resultsCount > 0)
                              Badge.count(count: resultsCount, child: const Icon(Icons.list_alt)),
                            IconButton(
                              tooltip: 'Fechar busca',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                onClearSearch();
                                onCloseSearch();
                              },
                            ),
                          ],
                        ),
                      )
                    : Row(
                        key: const ValueKey('viewer-actions-row'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FloatingActionButton.small(
                            heroTag: 'viewer-search-button',
                            tooltip: 'Buscar no PDF',
                            backgroundColor: const Color(0xFFEAF4FF),
                            foregroundColor: const Color(0xFF0B5CAD),
                            onPressed: onOpenSearch,
                            child: const Icon(Icons.search_rounded),
                          ),
                          const SizedBox(width: 8),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            child: quickActionsOpen
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _QuickActionIcon(
                                        icon: Icons.swap_vert_rounded,
                                        tooltip: 'Orientação',
                                        onTap: onToggleNavigationMode,
                                      ),
                                      _QuickActionIcon(
                                        icon: Icons.fit_screen_rounded,
                                        tooltip: 'Ajustar largura',
                                        onTap: onFitPageWidth,
                                      ),
                                      _QuickActionIcon(
                                        icon: isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                        tooltip: isFullScreen ? 'Sair da tela cheia' : 'Tela cheia',
                                        onTap: onToggleFullScreen,
                                      ),
                                      _QuickActionIcon(
                                        icon: Icons.sticky_note_2_rounded,
                                        tooltip: 'Adicionar post-it',
                                        onTap: onOpenPostIt,
                                      ),
                                      _QuickActionIcon(
                                        icon: Icons.list_alt_rounded,
                                        tooltip: 'Lista de post-its',
                                        onTap: onOpenPostItsList,
                                      ),
                                      _QuickActionIcon(
                                        icon: Icons.bookmark_add_rounded,
                                        tooltip: 'Favoritar página',
                                        onTap: onFavoritePage,
                                      ),
                                      _QuickActionIcon(
                                        icon: Icons.share_rounded,
                                        tooltip: 'Compartilhar',
                                        onTap: onShare,
                                      ),
                                    ],
                                  )
                                : const SizedBox.shrink(),
                          ),
                          const SizedBox(width: 8),
                          FloatingActionButton.small(
                            heroTag: 'viewer-plus-button',
                            tooltip: quickActionsOpen ? 'Fechar ações' : 'Ações rápidas',
                            onPressed: onOpenActions,
                            child: AnimatedRotation(
                              turns: quickActionsOpen ? 0.125 : 0,
                              duration: const Duration(milliseconds: 180),
                              child: Icon(quickActionsOpen ? Icons.remove_rounded : Icons.add_rounded),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 6),
              NavigationBar(
                height: 62,
                selectedIndex: selectedIndex,
                onDestinationSelected: onNavTap,
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.menu_book_outlined, color: Color(0xFF1565C0)), selectedIcon: Icon(Icons.menu_book_rounded, color: Color(0xFF0D47A1)), label: 'Biblioteca'),
                  NavigationDestination(icon: Icon(Icons.star_border_rounded, color: Color(0xFFFFA000)), selectedIcon: Icon(Icons.star_rounded, color: Color(0xFFFFA000)), label: 'Favoritos'),
                  NavigationDestination(icon: Icon(Icons.more_horiz_rounded, color: Color(0xFF5E35B1)), selectedIcon: Icon(Icons.more_horiz_rounded, color: Color(0xFF5E35B1)), label: 'Mais'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionIcon extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _QuickActionIcon({required this.icon, required this.tooltip, required this.onTap});

  @override
  State<_QuickActionIcon> createState() => _QuickActionIconState();
}

class _QuickActionIconState extends State<_QuickActionIcon> {
  bool _pressed = false;

  Color get _color {
    final colors = <Color>[
      const Color(0xFF1565C0),
      const Color(0xFF00838F),
      const Color(0xFF2E7D32),
      const Color(0xFFFF8F00),
      const Color(0xFF6A1B9A),
      const Color(0xFFC62828),
      const Color(0xFF5D4037),
    ];
    return colors[widget.icon.codePoint.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: IconButton.filledTonal(
          tooltip: widget.tooltip,
          onPressed: () async {
            setState(() => _pressed = true);
            await Future<void>.delayed(const Duration(milliseconds: 90));
            if (mounted) setState(() => _pressed = false);
            widget.onTap();
          },
          icon: AnimatedRotation(
            turns: _pressed ? -0.05 : 0,
            duration: const Duration(milliseconds: 120),
            child: Icon(widget.icon, color: color),
          ),
          style: IconButton.styleFrom(
            backgroundColor: color.withOpacity(0.12),
            foregroundColor: color,
          ),
        ),
      ),
    );
  }
}

/// Lista visual de resultados encontrados dentro do PDF.
class _SearchResultsList extends StatelessWidget {
  final List<PdfSearchResultItem> results;
  final String query;
  final VoidCallback onClose;
  final ValueChanged<PdfSearchResultItem> onTapResult;

  const _SearchResultsList({
    required this.results,
    required this.query,
    required this.onClose,
    required this.onTapResult,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${results.length} página(s) para "$query"',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(tooltip: 'Resultado anterior', onPressed: results.isEmpty ? null : () => onTapResult(results.first), icon: const Icon(Icons.keyboard_arrow_up_rounded, color: Color(0xFF0B5CAD))),
              IconButton(tooltip: 'Próximo resultado', onPressed: results.isEmpty ? null : () => onTapResult(results.first), icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF0B5CAD))),
              IconButton(tooltip: 'Fechar', onPressed: onClose, icon: const Icon(Icons.close)),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: results.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final result = results[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                leading: CircleAvatar(child: Text('${result.page}')),
                title: Text('Página ${result.page} • ${result.occurrences} ocorrência(s)', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _HighlightedSnippet(text: result.snippet, query: query),
                ),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => onTapResult(result),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Lista de páginas favoritadas do documento aberto.
class _FavoritePagesList extends StatelessWidget {
  final List<FavoritePdfPage> items;
  final ValueChanged<FavoritePdfPage> onTap;
  final ValueChanged<FavoritePdfPage> onLongPress;

  const _FavoritePagesList({required this.items, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Nenhuma página favoritada neste documento.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: Text('Páginas favoritas', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                leading: CircleAvatar(child: Text('${item.page}')),
                title: Text('Página ${item.page}', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(item.preview, maxLines: 3, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.bookmark_remove_outlined),
                onTap: () => onTap(item),
                onLongPress: () => onLongPress(item),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HighlightedSnippet extends StatelessWidget {
  final String text;
  final String query;

  const _HighlightedSnippet({required this.text, required this.query});

  @override
  Widget build(BuildContext context) {
    final q = query.trim();
    if (q.isEmpty) {
      return Text(text, maxLines: 4, overflow: TextOverflow.ellipsis);
    }
    final lower = text.toLowerCase();
    final lowerQ = q.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final index = lower.indexOf(lowerQ, start);
      if (index < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) spans.add(TextSpan(text: text.substring(start, index)));
      spans.add(TextSpan(
        text: text.substring(index, index + q.length),
        style: const TextStyle(
          color: Color(0xFF1B1B00),
          fontWeight: FontWeight.w900,
          backgroundColor: Color(0xFFFFEB3B),
        ),
      ));
      start = index + q.length;
    }
    return RichText(
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: DefaultTextStyle.of(context).style.copyWith(height: 1.35), children: spans),
    );
  }
}
