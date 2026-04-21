import 'package:flutter/material.dart';

/// Stub usado em plataformas que não são Web.
class WebPdfViewerFrame extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
