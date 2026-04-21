import 'package:flutter/material.dart';

/// Container responsivo que limita largura em desktop e ocupa toda a tela no mobile.
class ResponsivePageShell extends StatelessWidget {
  final Widget child;

  const ResponsivePageShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final maxWidth = width >= 1200 ? 1180.0 : double.infinity;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }
}
