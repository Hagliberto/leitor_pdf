// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

/// Carrega um arquivo textual servido diretamente pelo navegador.
///
/// Este fallback evita depender exclusivamente do `rootBundle`/`AssetManifest`
/// no Flutter Web. Arquivos colocados em `web/assets/...` são servidos como
/// `/assets/...`, sem o prefixo extra `assets/assets/...`.
Future<String?> loadDirectWebTextAsset(String path) async {
  try {
    return await html.HttpRequest.getString(path);
  } catch (_) {
    return null;
  }
}
