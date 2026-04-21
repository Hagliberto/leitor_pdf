// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// Visualizador de PDF específico para Flutter Web.
///
/// Usa o viewer nativo do navegador dentro de um iframe e registra eventos
/// básicos de interação no próprio elemento HTML para suportar duplo clique e
/// pressão longa/context menu mesmo com PDF aberto em platform view.
class WebPdfViewerFrame extends StatefulWidget {
  final String assetPath;
  final int page;
  final double zoom;
  final String displayMode;
  final String searchTerm;
  final String? localBase64;
  final int reloadToken;
  final bool allowPointerEvents;
  final VoidCallback? onDoubleTapPage;
  final VoidCallback? onLongPressPage;

  const WebPdfViewerFrame({
    super.key,
    required this.assetPath,
    required this.page,
    required this.zoom,
    this.displayMode = 'fitWidth',
    this.searchTerm = '',
    this.localBase64,
    required this.reloadToken,
    this.allowPointerEvents = true,
    this.onDoubleTapPage,
    this.onLongPressPage,
  });

  @override
  State<WebPdfViewerFrame> createState() => _WebPdfViewerFrameState();
}

class _WebPdfViewerFrameState extends State<WebPdfViewerFrame> {
  late String _viewType;
  Timer? _longPressTimer;
  String? _objectUrl;

  @override
  void initState() {
    super.initState();
    _registerFrame();
  }

  @override
  void didUpdateWidget(covariant WebPdfViewerFrame oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.assetPath != widget.assetPath ||
        oldWidget.page != widget.page ||
        oldWidget.zoom != widget.zoom ||
        oldWidget.displayMode != widget.displayMode ||
        oldWidget.searchTerm != widget.searchTerm ||
        oldWidget.localBase64 != widget.localBase64 ||
        oldWidget.reloadToken != widget.reloadToken ||
        oldWidget.allowPointerEvents != widget.allowPointerEvents) {
      _registerFrame();
    }
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    if (_objectUrl != null) {
      html.Url.revokeObjectUrl(_objectUrl!);
      _objectUrl = null;
    }
    super.dispose();
  }

  /// Registra um iframe HTML para exibir o PDF usando o visualizador nativo.
  void _registerFrame() {
    final safeKey = Object.hash(
      widget.assetPath,
      widget.page,
      widget.zoom,
      widget.displayMode,
      widget.searchTerm,
      widget.localBase64 ?? '',
      widget.reloadToken,
      widget.allowPointerEvents,
      DateTime.now().microsecondsSinceEpoch,
    );

    _viewType = 'pdf-frame-$safeKey';

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final pdfUrl = _buildPdfUrl();
      final frame = html.IFrameElement()
        ..src = pdfUrl
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = '#f4f1fa'
        ..style.display = 'block'
        ..style.pointerEvents = widget.allowPointerEvents ? 'auto' : 'none'
        ..allowFullscreen = true;

      frame.onDoubleClick.listen((_) => widget.onDoubleTapPage?.call());
      frame.onContextMenu.listen((event) {
        event.preventDefault();
        widget.onLongPressPage?.call();
      });
      frame.onTouchStart.listen((_) {
        _longPressTimer?.cancel();
        _longPressTimer = Timer(const Duration(milliseconds: 650), () {
          widget.onLongPressPage?.call();
        });
      });
      frame.onTouchEnd.listen((_) => _longPressTimer?.cancel());
      frame.onTouchCancel.listen((_) => _longPressTimer?.cancel());

      return frame;
    });
  }

  /// Monta a URL real do PDF no Flutter Web.
  ///
  /// Preferimos o caminho direto `assets/pdfs/arquivo.pdf`, porque os PDFs
  /// também são publicados em `web/assets/pdfs/`. Isso evita depender do
  /// caminho gerado pelo bundle do Flutter (`assets/assets/pdfs/...`), que pode
  /// ficar sensível a cache durante desenvolvimento no Edge/Chrome.
  String _buildPdfUrl() {
    final zoomPercent = (widget.zoom * 100).round();
    final search = widget.searchTerm.trim();

    final viewFragment = switch (widget.displayMode) {
      'fitPage' => 'view=Fit',
      'fitWidth' => 'view=FitH',
      _ => 'zoom=$zoomPercent',
    };

    final fragments = <String>[
      'page=${widget.page}',
      viewFragment,
      'toolbar=0',
      'navpanes=0',
      'scrollbar=1',
      if (search.isNotEmpty) 'search=${Uri.encodeComponent(search)}',
    ];

    final importedBase64 = widget.localBase64;
    if (importedBase64 != null && importedBase64.isNotEmpty) {
      if (_objectUrl != null) {
        html.Url.revokeObjectUrl(_objectUrl!);
        _objectUrl = null;
      }

      final bytes = base64Decode(importedBase64);
      final blob = html.Blob(<dynamic>[bytes], 'application/pdf');
      _objectUrl = html.Url.createObjectUrlFromBlob(blob);
      return '$_objectUrl#${fragments.join('&')}';
    }

    final directPath = widget.assetPath.startsWith('assets/')
        ? widget.assetPath
        : 'assets/pdfs/${widget.assetPath.split('/').last}';
    final encodedAssetPath = directPath.split('/').map(Uri.encodeComponent).join('/');
    final url = Uri.base.resolve('$encodedAssetPath?v=${widget.reloadToken}').toString();

    return '$url#${fragments.join('&')}';
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(
      key: ValueKey(_viewType),
      viewType: _viewType,
    );
  }
}
