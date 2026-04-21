import 'package:flutter/material.dart';

import '../../domain/entities/pdf_document.dart';

/// Card visual de um documento PDF na lista principal.
///
/// Mantém o layout leve, sem miniaturas, e usa um visual mais elegante para
/// funcionar bem no celular e no desktop.
class PdfCard extends StatefulWidget {
  final PdfDocument document;
  final VoidCallback onOpenTap;
  final VoidCallback onFavoriteTap;

  /// Ação executada ao pressionar o card por alguns segundos.
  final VoidCallback? onLongPress;

  const PdfCard({
    super.key,
    required this.document,
    required this.onOpenTap,
    required this.onFavoriteTap,
    this.onLongPress,
  });

  @override
  State<PdfCard> createState() => _PdfCardState();
}

class _PdfCardState extends State<PdfCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final document = widget.document;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.012 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: document.isFavorite
                  ? const [Color(0xFFEAF4FF), Color(0xFFD7E9FF)]
                  : [Colors.white, const Color(0xFFF6FAFF)],
            ),
            border: Border.all(
              color: document.isFavorite
                  ? const Color(0xFF6FAEF8)
                  : scheme.outlineVariant.withOpacity(0.55),
              width: document.isFavorite ? 1.4 : 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0B5CAD).withOpacity(document.isFavorite ? 0.18 : 0.08),
                blurRadius: document.isFavorite || _hovered ? 24 : 14,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: widget.onOpenTap,
              onLongPress: widget.onLongPress,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 430;

                  return Padding(
                    padding: EdgeInsets.all(compact ? 12 : 16),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: compact ? 48 : 56,
                          height: compact ? 48 : 56,
                          decoration: BoxDecoration(
                            color: document.isFavorite ? const Color(0xFFD8E9FF) : const Color(0xFFEAF4FF),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFB8D8FF)),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: Icon(
                              document.isFavorite
                                  ? Icons.bookmark_added_rounded
                                  : Icons.picture_as_pdf_rounded,
                              key: ValueKey(document.isFavorite),
                              color: document.isFavorite ? const Color(0xFF0B5CAD) : const Color(0xFF355C7D),
                              size: compact ? 27 : 31,
                            ),
                          ),
                        ),
                        SizedBox(width: compact ? 12 : 16),
                        Expanded(child: _PdfCardText(document: document, compact: compact)),
                        AnimatedRotation(
                          turns: document.isFavorite ? 0.08 : 0,
                          duration: const Duration(milliseconds: 220),
                          child: IconButton(
                            tooltip: document.isFavorite ? 'Remover dos favoritos' : 'Adicionar aos favoritos',
                            onPressed: widget.onFavoriteTap,
                            icon: Icon(
                              document.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                              color: document.isFavorite ? const Color(0xFFFFA000) : const Color(0xFF5C6B7A),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Textos internos do card.
class _PdfCardText extends StatelessWidget {
  final PdfDocument document;
  final bool compact;

  const _PdfCardText({required this.document, required this.compact});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          document.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: compact ? 15 : 16,
                color: const Color(0xFF16283D),
              ),
        ),
        const SizedBox(height: 5),
        Text(
          document.description,
          maxLines: compact ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: compact ? 12.5 : 13.5,
                color: const Color(0xFF526173),
              ),
        ),
        if (!compact) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _InfoPill(icon: Icons.description_outlined, label: document.isLocal ? 'Importado' : 'Biblioteca'),
              _InfoPill(icon: Icons.layers_outlined, label: '${document.pageCount} pág.'),
              if (document.isFavorite) const _InfoPill(icon: Icons.star_rounded, label: 'Favorito'),
            ],
          ),
        ],
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4FF),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0xFFB8D8FF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF0B5CAD)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF0B315E))),
        ],
      ),
    );
  }
}
