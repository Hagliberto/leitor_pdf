import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;

import '../../../../core/constants/asset_paths.dart';
import '../../../../core/platform/local_pdf_storage.dart';
import '../../../../core/platform/web_asset_loader.dart';
import '../../domain/entities/pdf_document.dart';
import '../../domain/entities/pdf_search_result.dart';
import '../models/pdf_document_model.dart';

/// Repositório responsável por buscar PDFs, favoritos, pastas e anotações.
class PdfRepository {
  static const String _favoritesKey = 'favorite_pdfs';
  static const String _favoritePagesKey = 'favorite_pdf_pages';
  static const String _localDocumentsKey = 'local_pdf_documents';
  static const String _foldersKey = 'pdf_folders';
  static const String _postItsKey = 'pdf_page_post_its';
  static const String _deletedDocumentsKey = 'deleted_pdf_documents';
  static const String _pdfEditsKey = 'pdf_page_edits';

  final Map<String, List<Map<String, dynamic>>> _pagesCache = <String, List<Map<String, dynamic>>>{};

  Future<String?> _loadTextAssetWithFallback(String assetPath) async {
    final directWebAsset = await loadDirectWebTextAsset(assetPath);
    if (directWebAsset != null) return directWebAsset;
    try {
      return await rootBundle.loadString(assetPath);
    } catch (_) {
      return null;
    }
  }

  Future<ByteData?> _loadBytesAssetWithFallback(String assetPath) async {
    try {
      return await rootBundle.load(assetPath);
    } catch (_) {
      return null;
    }
  }

  /// Carrega PDFs dos assets e PDFs importados pelo usuário.
  Future<List<PdfDocument>> fetchDocuments() async {
    final favorites = await getFavoriteFiles();
    final deleted = await getDeletedDocumentFiles();
    final catalog = await _loadCatalogByFile();
    final pdfAssetPaths = await _discoverPdfAssetPaths();

    final documents = await Future.wait(
      pdfAssetPaths.map((assetPath) async {
        final fileKey = assetPath.startsWith(AssetPaths.pdfDirectory) ? assetPath.substring(AssetPaths.pdfDirectory.length) : assetPath;
        final fileName = assetPath.split('/').last;
        final catalogItem = catalog[fileKey] ?? catalog[fileName] ?? catalog[assetPath];

        final document = catalogItem == null
            ? PdfDocument(
                file: fileKey,
                title: _titleFromFileName(fileName),
                description: 'Documento disponível na biblioteca.',
                version: 'v1.0',
                pageCount: await _countPdfPages(assetPath),
              )
            : PdfDocumentModel.fromJson(catalogItem).copyWith(
                file: fileKey,
                pageCount: (catalogItem['pageCount'] as int?) == null || (catalogItem['pageCount'] as int? ?? 0) <= 0
                    ? await _countPdfPages(assetPath)
                    : catalogItem['pageCount'] as int,
              );

        return document.copyWith(isFavorite: favorites.contains(document.file));
      }),
    );

    final localDocuments = await getLocalDocuments();
    documents.removeWhere((doc) => deleted.contains(doc.file));
    documents.addAll(localDocuments.where((doc) => !deleted.contains(doc.file)).map((doc) => doc.copyWith(isFavorite: favorites.contains(doc.file))));
    documents.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return documents;
  }

  Future<Map<String, Map<String, dynamic>>> _loadCatalogByFile() async {
    try {
      final rawJson = await _loadTextAssetWithFallback(AssetPaths.pdfCatalog);
      if (rawJson == null || rawJson.trim().isEmpty) return <String, Map<String, dynamic>>{};
      final decoded = jsonDecode(rawJson) as List<dynamic>;
      final map = <String, Map<String, dynamic>>{};

      for (final item in decoded.cast<Map<String, dynamic>>()) {
        final file = item['file'] as String?;
        if (file == null || file.trim().isEmpty) continue;
        map[file] = item;
        map[file.split('/').last] = item;
        map['${AssetPaths.pdfDirectory}$file'] = item;
      }
      return map;
    } catch (_) {
      return <String, Map<String, dynamic>>{};
    }
  }

  Future<List<String>> _discoverPdfAssetPaths() async {
    final discovered = <String>{};
    discovered.addAll(await _loadGeneratedPdfManifest());

    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      discovered.addAll(
        manifest.listAssets().where((path) => path.toLowerCase().endsWith('.pdf')).where((path) => path.startsWith('assets/')),
      );
    } catch (_) {}

    final catalog = await _loadCatalogByFile();
    discovered.addAll(catalog.keys.where((path) => path.toLowerCase().endsWith('.pdf')).map((file) => file.contains('/') ? file : '${AssetPaths.pdfDirectory}$file'));


    return discovered.where((path) => path.toLowerCase().endsWith('.pdf')).map(_normalizePdfAssetPath).toSet().toList()..sort();
  }

  String _normalizePdfAssetPath(String rawPath) {
    var path = rawPath.trim().replaceAll('\\', '/');
    if (path.startsWith('/')) path = path.substring(1);
    if (path.startsWith('web/')) path = path.substring('web/'.length);
    if (!path.startsWith('assets/')) path = '${AssetPaths.pdfDirectory}$path';
    return path;
  }

  Future<List<String>> _loadGeneratedPdfManifest() async {
    try {
      final rawJson = await _loadTextAssetWithFallback('assets/pdfs/pdf_manifest.json');
      if (rawJson == null || rawJson.trim().isEmpty) return const <String>[];
      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      return (decoded['pdfs'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => item.toString())
          .where((path) => path.toLowerCase().endsWith('.pdf'))
          .map((path) => path.contains('/') ? path : '${AssetPaths.pdfDirectory}$path')
          .toSet()
          .toList()
        ..sort();
    } catch (_) {
      return const <String>[];
    }
  }

  String _titleFromFileName(String fileName) {
    final withoutExtension = fileName.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');
    final clean = withoutExtension.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    if (clean.isEmpty) return fileName;
    return clean.split(RegExp(r'\s+')).map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}').join(' ');
  }

  Future<int> _countPdfPages(String assetPath) async {
    try {
      final byteData = await _loadBytesAssetWithFallback(assetPath);
      if (byteData == null) return 1;
      final bytes = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
      final document = sfpdf.PdfDocument(inputBytes: bytes);
      final count = document.pages.count;
      document.dispose();
      return count;
    } catch (_) {
      return 1;
    }
  }

  Future<Set<String>> getFavoriteFiles() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_favoritesKey) ?? <String>[]).toSet();
  }

  Future<void> toggleFavorite(String file) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = await getFavoriteFiles();
    favorites.contains(file) ? favorites.remove(file) : favorites.add(file);
    await prefs.setStringList(_favoritesKey, favorites.toList());
  }

  Future<Set<String>> getDeletedDocumentFiles() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_deletedDocumentsKey) ?? <String>[]).toSet();
  }

  Future<void> deleteDocument(String file) async {
    final prefs = await SharedPreferences.getInstance();
    final deleted = await getDeletedDocumentFiles();
    deleted.add(file);
    await prefs.setStringList(_deletedDocumentsKey, deleted.toList());
    // Mantém os dados do PDF importado para permitir DESFAZER e restauração posterior.
    final folders = await getFolders();
    final updatedFolders = folders.map((folder) {
      final files = folder.documentFiles.toSet()..remove(file);
      return folder.copyWith(documentFiles: files.toList()..sort());
    }).toList();
    await _saveFolders(updatedFolders);
  }

  Future<void> restoreDocument(String file) async {
    final prefs = await SharedPreferences.getInstance();
    final deleted = await getDeletedDocumentFiles();
    deleted.remove(file);
    await prefs.setStringList(_deletedDocumentsKey, deleted.toList());
  }

  Future<void> resetApplicationSettings({Set<String>? keepDocumentFiles, Set<String>? keepFolderIds}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_favoritesKey);
    await prefs.remove(_favoritePagesKey);
    await prefs.remove(_postItsKey);
    await prefs.remove(_pdfEditsKey);

    if (keepFolderIds == null) {
      await prefs.remove(_foldersKey);
    } else {
      final folders = await getFolders();
      await _saveFolders(folders.where((folder) => folder.id == 'root' || keepFolderIds.contains(folder.id)).toList());
    }

    if (keepDocumentFiles == null) {
      await prefs.remove(_deletedDocumentsKey);
    } else {
      final allDocuments = await fetchDocuments();
      final toHide = allDocuments.map((doc) => doc.file).where((file) => !keepDocumentFiles.contains(file)).toSet();
      await prefs.setStringList(_deletedDocumentsKey, toHide.toList());
      final localDocuments = await getLocalDocuments();
      await _saveLocalDocuments(localDocuments.where((doc) => keepDocumentFiles.contains(doc.file)).toList());
    }
    _pagesCache.clear();
  }

  Future<List<PdfDocument>> getLocalDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_localDocumentsKey) ?? <String>[];
    return rawList.map((raw) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        return PdfDocument(
          file: json['file'] as String,
          title: json['title'] as String? ?? _titleFromFileName(json['file'].toString()),
          description: json['description'] as String? ?? 'Documento importado do dispositivo.',
          version: json['version'] as String? ?? 'importado',
          pageCount: json['pageCount'] as int? ?? 1,
          localPath: json['localPath'] as String?,
          localBase64: json['localBase64'] as String?,
        );
      } catch (_) {
        return null;
      }
    }).whereType<PdfDocument>().toList();
  }

  Future<void> _saveLocalDocuments(List<PdfDocument> documents) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _localDocumentsKey,
      documents
          .map((doc) => jsonEncode(<String, dynamic>{
                'file': doc.file,
                'title': doc.title,
                'description': doc.description,
                'version': doc.version,
                'pageCount': doc.pageCount,
                'localPath': doc.localPath,
                'localBase64': doc.localBase64,
              }))
          .toList(),
    );
  }

  Future<List<PdfDocument>> importPdfsFromDevice() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['pdf'],
      allowMultiple: true,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return const <PdfDocument>[];

    final current = await getLocalDocuments();
    final imported = <PdfDocument>[];
    for (final file in result.files) {
      String? savedPath;
      String? localBase64;
      Uint8List? pickedBytes;

      if (kIsWeb) {
        pickedBytes = file.bytes;
        if (pickedBytes == null || pickedBytes.isEmpty) continue;
        localBase64 = base64Encode(pickedBytes);
      } else {
        final sourcePath = file.path;
        if (sourcePath == null || sourcePath.isEmpty) continue;
        savedPath = await copyPickedPdfToAppStorage(sourcePath: sourcePath, fileName: file.name);
        if (savedPath == null) continue;
        pickedBytes = await readLocalPdfBytes(savedPath);
      }

      final doc = PdfDocument(
        file: 'local:${DateTime.now().microsecondsSinceEpoch}-${file.name}',
        title: _titleFromFileName(file.name),
        description: kIsWeb ? 'Documento importado no navegador.' : 'Documento importado do dispositivo.',
        version: 'importado',
        pageCount: pickedBytes == null ? await _countLocalPdfPages(savedPath ?? '') : _countPdfPagesFromBytes(pickedBytes),
        localPath: savedPath,
        localBase64: localBase64,
      );
      imported.add(doc);
    }
    if (imported.isNotEmpty) {
      current.addAll(imported);
      await _saveLocalDocuments(current);
    }
    return imported;
  }


  Future<List<PdfDocument>> importPdfsFromDirectory() async {
    if (kIsWeb) {
      return importPdfsFromDevice();
    }

    final directoryPath = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Escolha uma pasta com PDFs');
    if (directoryPath == null || directoryPath.isEmpty) return const <PdfDocument>[];

    final files = await listPdfFilesRecursively(directoryPath);
    if (files.isEmpty) return const <PdfDocument>[];

    final current = await getLocalDocuments();
    final imported = <PdfDocument>[];
    for (final file in files) {
      final savedPath = await copyPickedPdfToAppStorage(sourcePath: file.path, fileName: file.name);
      if (savedPath == null) continue;
      final pickedBytes = await readLocalPdfBytes(savedPath);
      final doc = PdfDocument(
        file: 'local:${DateTime.now().microsecondsSinceEpoch}-${file.name}',
        title: _titleFromFileName(file.name),
        description: 'Documento importado de pasta do dispositivo.',
        version: 'importado',
        pageCount: pickedBytes == null ? await _countLocalPdfPages(savedPath) : _countPdfPagesFromBytes(pickedBytes),
        localPath: savedPath,
      );
      imported.add(doc);
    }
    if (imported.isNotEmpty) {
      current.addAll(imported);
      await _saveLocalDocuments(current);
    }
    return imported;
  }

  int _countPdfPagesFromBytes(Uint8List bytes) {
    try {
      final document = sfpdf.PdfDocument(inputBytes: bytes);
      final count = document.pages.count;
      document.dispose();
      return count;
    } catch (_) {
      return 1;
    }
  }

  Future<int> _countLocalPdfPages(String localPath) async {
    try {
      final bytes = await readLocalPdfBytes(localPath);
      if (bytes == null) return 1;
      final document = sfpdf.PdfDocument(inputBytes: bytes);
      final count = document.pages.count;
      document.dispose();
      return count;
    } catch (_) {
      return 1;
    }
  }

  Future<Uint8List?> loadDocumentBytes(PdfDocument document) async {
    if (document.localBase64 != null && document.localBase64!.isNotEmpty) {
      try { return base64Decode(document.localBase64!); } catch (_) { return null; }
    }
    if (document.localPath != null && document.localPath!.isNotEmpty) return readLocalPdfBytes(document.localPath!);
    final byteData = await _loadBytesAssetWithFallback(document.assetPath);
    if (byteData == null) return null;
    return byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
  }

  Future<List<PdfFolder>> getFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_foldersKey) ?? <String>[];
    final folders = rawList.map((raw) {
      try {
        return PdfFolder.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }).whereType<PdfFolder>().toList();

    if (folders.isEmpty) {
      final root = PdfFolder(id: 'root', name: 'Documentos', parentId: null, documentFiles: const <String>[], createdAt: DateTime.now().toIso8601String());
      await _saveFolders(<PdfFolder>[root]);
      return <PdfFolder>[root];
    }
    return folders..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> _saveFolders(List<PdfFolder> folders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_foldersKey, folders.map((folder) => jsonEncode(folder.toJson())).toList());
  }

  Future<PdfFolder> createFolder({required String name, String? parentId}) async {
    final folders = await getFolders();
    final folder = PdfFolder(
      id: 'folder-${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Nova pasta' : name.trim(),
      parentId: parentId ?? 'root',
      documentFiles: const <String>[],
      createdAt: DateTime.now().toIso8601String(),
    );
    folders.add(folder);
    await _saveFolders(folders);
    return folder;
  }

  Future<void> renameFolder({required String folderId, required String name}) async {
    final folders = await getFolders();
    await _saveFolders(folders.map((folder) => folder.id == folderId ? folder.copyWith(name: name.trim().isEmpty ? folder.name : name.trim()) : folder).toList());
  }

  Future<void> updateFolderColor({required String folderId, required int colorValue}) async {
    final folders = await getFolders();
    await _saveFolders(folders.map((folder) => folder.id == folderId ? folder.copyWith(colorValue: colorValue) : folder).toList());
  }

  Future<void> deleteFolder(String folderId) async {
    if (folderId == 'root') return;
    final folders = await getFolders();
    await _saveFolders(folders.where((folder) => folder.id != folderId && folder.parentId != folderId).toList());
  }

  Future<void> toggleDocumentInFolder({required String folderId, required String documentFile}) async {
    final folders = await getFolders();
    final updated = folders.map((folder) {
      if (folder.id != folderId) return folder;
      final files = folder.documentFiles.toSet();
      files.contains(documentFile) ? files.remove(documentFile) : files.add(documentFile);
      return folder.copyWith(documentFiles: files.toList()..sort());
    }).toList();
    await _saveFolders(updated);
  }

  Future<void> moveDocumentToFolder({required String folderId, required String documentFile}) async {
    final folders = await getFolders();
    final updated = folders.map((folder) {
      final files = folder.documentFiles.toSet()..remove(documentFile);
      if (folder.id == folderId) files.add(documentFile);
      return folder.copyWith(documentFiles: files.toList()..sort());
    }).toList();
    await _saveFolders(updated);
  }

  Future<Map<int, String>> getPostItsForDocument(String file) async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_postItsKey) ?? <String>[];
    final map = <int, String>{};
    for (final raw in rawList) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if (json['file'] != file) continue;
        final page = json['page'] as int?;
        final text = json['text'] as String?;
        if (page != null && text != null && text.trim().isNotEmpty) map[page] = text;
      } catch (_) {}
    }
    return map;
  }

  Future<void> savePagePostIt({required String file, required int page, required String text}) async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_postItsKey) ?? <String>[];
    final items = <Map<String, dynamic>>[];
    for (final raw in rawList) {
      try {
        final item = jsonDecode(raw) as Map<String, dynamic>;
        if (item['file'] == file && item['page'] == page) continue;
        items.add(item);
      } catch (_) {}
    }
    if (text.trim().isNotEmpty) {
      items.add(<String, dynamic>{'file': file, 'page': page, 'text': text.trim(), 'updatedAt': DateTime.now().toIso8601String()});
    }
    await prefs.setStringList(_postItsKey, items.map((item) => jsonEncode(item)).toList());
  }

  Future<List<Map<String, dynamic>>> getPageEdits({required String file, required int page}) async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_pdfEditsKey) ?? <String>[];
    final edits = <Map<String, dynamic>>[];
    for (final raw in rawList) {
      try {
        final item = jsonDecode(raw) as Map<String, dynamic>;
        if (item['file'] == file && item['page'] == page) edits.add(item);
      } catch (_) {}
    }
    return edits;
  }

  Future<void> savePageEdits({required String file, required int page, required List<Map<String, dynamic>> edits}) async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_pdfEditsKey) ?? <String>[];
    final items = <Map<String, dynamic>>[];
    for (final raw in rawList) {
      try {
        final item = jsonDecode(raw) as Map<String, dynamic>;
        if (item['file'] == file && item['page'] == page) continue;
        items.add(item);
      } catch (_) {}
    }
    items.addAll(edits.map((edit) => <String, dynamic>{...edit, 'file': file, 'page': page, 'updatedAt': DateTime.now().toIso8601String()}));
    await prefs.setStringList(_pdfEditsKey, items.map((item) => jsonEncode(item)).toList());
  }

  Future<List<FavoritePdfPage>> getFavoritePages() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_favoritePagesKey) ?? <String>[];
    return rawList.map((raw) {
      try {
        return FavoritePdfPage.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }).whereType<FavoritePdfPage>().toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<bool> isPageFavorite({required String file, required int page}) async {
    final favorites = await getFavoritePages();
    return favorites.any((item) => item.file == file && item.page == page);
  }

  Future<bool> togglePageFavorite({required PdfDocument document, required int page}) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = await getFavoritePages();
    final existingIndex = favorites.indexWhere((item) => item.file == document.file && item.page == page);

    if (existingIndex >= 0) {
      favorites.removeAt(existingIndex);
      await prefs.setStringList(_favoritePagesKey, favorites.map((item) => jsonEncode(item.toJson())).toList());
      return false;
    }

    final preview = await getPagePreview(file: document.file, page: page);
    favorites.insert(0, FavoritePdfPage(file: document.file, title: document.title, page: page, preview: preview, createdAt: DateTime.now().toIso8601String()));
    await prefs.setStringList(_favoritePagesKey, favorites.map((item) => jsonEncode(item.toJson())).toList());
    return true;
  }

  Future<List<PdfSearchResultItem>> searchInDocument({required String file, required String query, bool allowDynamicExtraction = false}) async {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.length < 2) return const <PdfSearchResultItem>[];
    final pages = await _loadIndexedPages(file, allowDynamicExtraction: allowDynamicExtraction);
    final results = <PdfSearchResultItem>[];

    for (final item in pages) {
      final page = item['page'] as int;
      final text = item['text'] as String? ?? '';
      final normalizedText = _normalize(text);
      if (!normalizedText.contains(normalizedQuery)) continue;
      final occurrences = RegExp(RegExp.escape(normalizedQuery)).allMatches(normalizedText).length;
      results.add(PdfSearchResultItem(file: file, page: page, snippet: _buildSnippet(text, normalizedText, normalizedQuery), occurrences: occurrences));
    }
    return results;
  }

  Future<String> getPagePreview({required String file, required int page}) async {
    final pages = await _loadIndexedPages(file);
    final item = pages.cast<Map<String, dynamic>>().firstWhere((entry) => entry['page'] == page, orElse: () => <String, dynamic>{'text': ''});
    final text = (item['text'] as String? ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return 'Prévia indisponível para esta página.';
    return text.length > 180 ? '${text.substring(0, 180)}...' : text;
  }

  Future<List<Map<String, dynamic>>> _loadIndexedPages(String file, {bool allowDynamicExtraction = true}) async {
    final cached = _pagesCache[file];
    if (cached != null) return cached;

    try {
      final rawJson = await _loadTextAssetWithFallback(AssetPaths.pdfTextIndex);
      if (rawJson == null || rawJson.trim().isEmpty) return allowDynamicExtraction ? await _extractPagesFromPdf(file) : const <Map<String, dynamic>>[];
      final decoded = jsonDecode(rawJson) as List<dynamic>;
      final documentIndex = decoded.cast<Map<String, dynamic>>().firstWhere(
            (item) => item['file'] == file || item['file'] == file.split('/').last,
            orElse: () => <String, dynamic>{'pages': <dynamic>[]},
          );
      final indexedPages = (documentIndex['pages'] as List<dynamic>).cast<Map<String, dynamic>>();
      if (indexedPages.isNotEmpty) {
        _pagesCache[file] = indexedPages;
        return indexedPages;
      }
    } catch (_) {}

    if (!allowDynamicExtraction) return const <Map<String, dynamic>>[];
    final extractedPages = await _extractPagesFromPdf(file);
    _pagesCache[file] = extractedPages;
    return extractedPages;
  }

  Future<List<Map<String, dynamic>>> _extractPagesFromPdf(String file) async {
    final localDoc = (await getLocalDocuments()).where((doc) => doc.file == file).cast<PdfDocument?>().firstWhere((doc) => doc != null, orElse: () => null);
    Uint8List? bytes;
    if (localDoc != null && localDoc.localBase64 != null && localDoc.localBase64!.isNotEmpty) {
      try { bytes = base64Decode(localDoc.localBase64!); } catch (_) { bytes = null; }
    } else if (localDoc != null && localDoc.localPath != null && localDoc.localPath!.isNotEmpty) {
      bytes = await readLocalPdfBytes(localDoc.localPath!);
    } else {
      final assetPath = file.contains('/') ? file : '${AssetPaths.pdfDirectory}$file';
      final byteData = await _loadBytesAssetWithFallback(assetPath);
      bytes = byteData?.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
    }
    if (bytes == null) return const <Map<String, dynamic>>[];

    try {
      final document = sfpdf.PdfDocument(inputBytes: bytes);
      final extractor = sfpdf.PdfTextExtractor(document);
      final pages = <Map<String, dynamic>>[];
      for (var i = 0; i < document.pages.count; i++) {
        pages.add(<String, dynamic>{'page': i + 1, 'text': extractor.extractText(startPageIndex: i, endPageIndex: i)});
      }
      document.dispose();
      return pages;
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  String _normalize(String value) {
    final lower = value.toLowerCase();
    return lower
        .replaceAll(RegExp('[áàâãä]'), 'a')
        .replaceAll(RegExp('[éèêë]'), 'e')
        .replaceAll(RegExp('[íìîï]'), 'i')
        .replaceAll(RegExp('[óòôõö]'), 'o')
        .replaceAll(RegExp('[úùûü]'), 'u')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _buildSnippet(String original, String normalized, String query) {
    final index = normalized.indexOf(query);
    if (index < 0) return original.length > 180 ? '${original.substring(0, 180)}...' : original;
    final start = (index - 80).clamp(0, original.length).toInt();
    final end = (index + query.length + 120).clamp(0, original.length).toInt();
    return '${start > 0 ? '...' : ''}${original.substring(start, end)}${end < original.length ? '...' : ''}';
  }
}

/// Pasta criada pelo usuário para organizar PDFs em hierarquia simples.
class PdfFolder {
  final String id;
  final String name;
  final String? parentId;
  final List<String> documentFiles;
  final String createdAt;
  final int colorValue;

  const PdfFolder({required this.id, required this.name, required this.parentId, required this.documentFiles, required this.createdAt, this.colorValue = 0xFF0B5CAD});

  factory PdfFolder.fromJson(Map<String, dynamic> json) {
    return PdfFolder(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Pasta',
      parentId: json['parentId'] as String?,
      documentFiles: (json['documentFiles'] as List<dynamic>? ?? const <dynamic>[]).map((item) => item.toString()).toList(),
      createdAt: json['createdAt'] as String? ?? '',
      colorValue: json['colorValue'] as int? ?? 0xFF0B5CAD,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'name': name, 'parentId': parentId, 'documentFiles': documentFiles, 'createdAt': createdAt, 'colorValue': colorValue};

  PdfFolder copyWith({String? id, String? name, String? parentId, bool clearParentId = false, List<String>? documentFiles, String? createdAt, int? colorValue}) {
    return PdfFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: clearParentId ? null : (parentId ?? this.parentId),
      documentFiles: documentFiles ?? this.documentFiles,
      createdAt: createdAt ?? this.createdAt,
      colorValue: colorValue ?? this.colorValue,
    );
  }
}

/// Página favoritada pelo usuário com uma prévia textual.
class FavoritePdfPage {
  final String file;
  final String title;
  final int page;
  final String preview;
  final String createdAt;

  const FavoritePdfPage({required this.file, required this.title, required this.page, required this.preview, required this.createdAt});

  factory FavoritePdfPage.fromJson(Map<String, dynamic> json) {
    return FavoritePdfPage(
      file: json['file'] as String,
      title: json['title'] as String,
      page: json['page'] as int,
      preview: json['preview'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{'file': file, 'title': title, 'page': page, 'preview': preview, 'createdAt': createdAt};
}
