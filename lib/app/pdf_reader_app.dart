import 'dart:async';

import 'package:flutter/material.dart';

import '../core/constants/app_info.dart';
import '../features/pdf_reader/presentation/pages/pdf_home_page.dart';

/// Widget raiz da aplicação.
///
/// Define tema, título, idioma visual e tela inicial do leitor digital.
class PdfReaderApp extends StatelessWidget {
  const PdfReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0B5CAD),
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF4F8FC),
        cardTheme: CardThemeData(
          elevation: 1.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      home: const _FolhearSplashPage(),
    );
  }
}

/// Tela de abertura exibida por 3 segundos antes da Biblioteca.
class _FolhearSplashPage extends StatefulWidget {
  const _FolhearSplashPage();

  @override
  State<_FolhearSplashPage> createState() => _FolhearSplashPageState();
}

class _FolhearSplashPageState extends State<_FolhearSplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, animation, __) => const PdfHomePage(),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 420),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF4FF),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/icon.gif',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFEAF4FF), Color(0xFFB9E3FF)],
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withOpacity(0.18),
                  Colors.black.withOpacity(0.10),
                ],
              ),
            ),
          ),
          Center(
            child: FadeTransition(
              opacity: _fade,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/icon.png', width: 112, height: 112),
                  const SizedBox(height: 18),
                  const Text(
                    AppInfo.name,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: Color(0xFF073A66),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    AppInfo.subtitle,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0B5CAD),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
