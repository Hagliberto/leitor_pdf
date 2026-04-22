import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_info.dart';
import '../../data/repositories/pdf_repository.dart';
import '../../domain/entities/pdf_document.dart';
import '../providers/pdf_provider.dart';
import '../widgets/pdf_card.dart';
import 'pdf_viewer_page.dart';

/// Tela inicial com biblioteca, pastas, busca inferior e favoritos.
class PdfHomePage extends ConsumerStatefulWidget {
  const PdfHomePage({super.key});

  @override
  ConsumerState<PdfHomePage> createState() => _PdfHomePageState();
}

class _PdfHomePageState extends ConsumerState<PdfHomePage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  int _selectedIndex = 0;
  bool _searchOpen = false;
  bool _showFolderTree = false;
  bool _showFoldersPanel = false;
  String _selectedFolderId = 'root';
  List<PdfFolder> _folders = const <PdfFolder>[];

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_refreshFolders);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _refreshFolders() async {
    final folders = await ref.read(pdfRepositoryProvider).getFolders();
    if (!mounted) return;
    setState(() {
      _folders = folders;
      if (!_folders.any((folder) => folder.id == _selectedFolderId)) {
        _selectedFolderId = 'root';
      }
    });
  }

  Future<void> _refreshHome() async {
    await _refreshFolders();
    await ref.read(pdfViewModelProvider.notifier).reload();
  }

  void _showElegantToast({required IconData icon, required String message}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: Colors.transparent,
        duration: const Duration(seconds: 3),
        content: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.92, end: 1),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutBack,
          builder: (context, value, child) => Transform.scale(scale: value, child: child),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4FF),
              border: Border.all(color: const Color(0xFF9CCBFF)),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0B5CAD).withOpacity(0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: const Color(0xFF0B5CAD)),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    message,
                    style: const TextStyle(color: Color(0xFF0B315E), fontWeight: FontWeight.w800),
                  ),
                ),
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
        decoration: BoxDecoration(
          color: const Color(0xFFEAF4FF),
          border: Border.all(color: const Color(0xFF7DBDFF)),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: const Color(0xFF0B5CAD).withOpacity(0.20), blurRadius: 30, offset: const Offset(0, 12))],
        ),
        child: Row(children: [
          Icon(icon, color: const Color(0xFF0B5CAD)),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: Color(0xFF0B315E), fontWeight: FontWeight.w800))),
          const SizedBox(width: 8),
          const Icon(Icons.undo_rounded, color: Color(0xFF0B5CAD)),
        ]),
      ),
    ));
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (context.mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    });
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searchController.clear();
    ref.read(pdfViewModelProvider.notifier).updateSearch('');
    setState(() => _searchOpen = false);
    _searchFocus.unfocus();
  }

  Future<void> _toggleDocumentFavorite(PdfDocument document) async {
    await ref.read(pdfViewModelProvider.notifier).toggleFavorite(document);
    _showElegantToast(
      icon: document.isFavorite ? Icons.star_border_rounded : Icons.star_rounded,
      message: document.isFavorite ? 'Documento removido dos favoritos.' : 'Documento favoritado.',
    );
  }

  Future<bool> _confirmDeleteDocument(PdfDocument document) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded),
        title: const Text('Excluir PDF da biblioteca?'),
        content: Text('O documento "${document.title}" será removido da lista e das pastas. Você terá 5 segundos para desfazer.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton.tonalIcon(onPressed: () => Navigator.of(context).pop(true), icon: const Icon(Icons.delete_outline_rounded), label: const Text('Excluir')),
        ],
      ),
    );
    return confirm ?? false;
  }

  Future<void> _deleteDocumentWithUndo(PdfDocument document) async {
    await ref.read(pdfRepositoryProvider).deleteDocument(document.file);
    await _refreshFolders();
    await ref.read(pdfViewModelProvider.notifier).reload();
    if (!mounted) return;
    _showUndoToast(
      icon: Icons.delete_outline_rounded,
      message: 'PDF removido da biblioteca.',
      actionLabel: 'DESFAZER',
      onUndo: () async {
        await ref.read(pdfRepositoryProvider).restoreDocument(document.file);
        await _refreshFolders();
        await ref.read(pdfViewModelProvider.notifier).reload();
      },
    );
  }

  Future<String?> _askFolderName({String title = 'Nova pasta', String initialValue = ''}) async {
    final controller = TextEditingController(text: initialValue);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nome da pasta'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Salvar')),
        ],
      ),
    );
    controller.dispose();
    final cleaned = value?.trim();
    if (cleaned == null || cleaned.isEmpty) return null;
    return cleaned;
  }

  Future<void> _createFolder([List<PdfDocument> availableDocuments = const <PdfDocument>[]]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final nameController = TextEditingController();
        final colors = <Color>[
          const Color(0xFF0B5CAD),
          const Color(0xFF00A2C7),
          const Color(0xFF2E7D32),
          const Color(0xFFF9A825),
          const Color(0xFFC62828),
          const Color(0xFF6A1B9A),
          const Color(0xFF5D4037),
          const Color(0xFF455A64),
        ];
        Color selectedColor = const Color(0xFF0B5CAD);
        final selectedFiles = <String>{};

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Nova pasta'),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: FilledButton.icon(
                        onPressed: () {
                          final cleaned = nameController.text.trim();
                          if (cleaned.isEmpty) return;
                          Navigator.of(context).pop(<String, dynamic>{
                            'name': cleaned,
                            'colorValue': selectedColor.value,
                            'selectedFiles': selectedFiles.toList(),
                          });
                        },
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        label: const Text('Criar pasta'),
                      ),
                    ),
                  ],
                ),
                body: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 980;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1280),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [Color(0xFFEAF4FF), Color(0xFFF7FBFF)]),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(color: const Color(0xFFB8D9FF)),
                                  boxShadow: [BoxShadow(color: selectedColor.withOpacity(0.08), blurRadius: 14, offset: const Offset(0, 6))],
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(colors: [selectedColor, selectedColor.withOpacity(0.72)]),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: const Icon(Icons.create_new_folder_rounded, color: Colors.white, size: 24),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Criar pasta inteligente', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                                          const SizedBox(height: 4),
                                          const Text(
                                            'Defina nome, cor e PDFs vinculados em uma tela ampla e sem cortes.',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: const [
                                        _TinyPill(icon: Icons.palette_outlined, label: 'Cor'),
                                        _TinyPill(icon: Icons.picture_as_pdf_rounded, label: 'PDFs'),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              if (isWide)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 5,
                                      child: _FolderFormSection(
                                        nameController: nameController,
                                        colors: colors,
                                        selectedColor: selectedColor,
                                        onColorChanged: (color) => setModalState(() => selectedColor = color),
                                      ),
                                    ),
                                    const SizedBox(width: 18),
                                    Expanded(
                                      flex: 7,
                                      child: _FolderDocumentsSection(
                                        availableDocuments: availableDocuments,
                                        selectedFiles: selectedFiles,
                                        onToggleFile: (file, selected) {
                                          setModalState(() {
                                            if (selected) {
                                              selectedFiles.add(file);
                                            } else {
                                              selectedFiles.remove(file);
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                )
                              else ...[
                                _FolderFormSection(
                                  nameController: nameController,
                                  colors: colors,
                                  selectedColor: selectedColor,
                                  onColorChanged: (color) => setModalState(() => selectedColor = color),
                                ),
                                const SizedBox(height: 18),
                                _FolderDocumentsSection(
                                  availableDocuments: availableDocuments,
                                  selectedFiles: selectedFiles,
                                  onToggleFile: (file, selected) {
                                    setModalState(() {
                                      if (selected) {
                                        selectedFiles.add(file);
                                      } else {
                                        selectedFiles.remove(file);
                                      }
                                    });
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
    if (result == null) return;
    final folder = await ref.read(pdfRepositoryProvider).createFolder(name: result['name'] as String, parentId: _selectedFolderId);
    await ref.read(pdfRepositoryProvider).updateFolderColor(folderId: folder.id, colorValue: result['colorValue'] as int);
    final selectedFiles = (result['selectedFiles'] as List<dynamic>? ?? const <dynamic>[]).map((e) => e.toString()).toList();
    for (final file in selectedFiles) {
      await ref.read(pdfRepositoryProvider).toggleDocumentInFolder(folderId: folder.id, documentFile: file);
    }
    await _refreshFolders();
    _showElegantToast(icon: Icons.create_new_folder_rounded, message: 'Pasta "${result['name']}" criada com sucesso.');
  }

  Future<void> _renameFolder(PdfFolder folder) async {
    if (folder.id == 'root') {
      _showElegantToast(icon: Icons.info_outline_rounded, message: 'A pasta Documentos é fixa.');
      return;
    }
    final name = await _askFolderName(title: 'Renomear pasta', initialValue: folder.name);
    if (name == null) return;
    await ref.read(pdfRepositoryProvider).renameFolder(folderId: folder.id, name: name);
    await _refreshFolders();
    _showElegantToast(icon: Icons.drive_file_rename_outline_rounded, message: 'Pasta renomeada.');
  }

  Future<void> _deleteFolder(PdfFolder folder) async {
    if (folder.id == 'root') {
      _showElegantToast(icon: Icons.info_outline_rounded, message: 'A pasta Documentos é fixa.');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.folder_delete_rounded),
        title: Text('Excluir pasta "${folder.name}"?'),
        content: const Text('Os PDFs não serão apagados. Apenas a pasta e seus vínculos serão removidos.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton.tonalIcon(onPressed: () => Navigator.of(context).pop(true), icon: const Icon(Icons.delete_outline_rounded), label: const Text('Excluir')),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(pdfRepositoryProvider).deleteFolder(folder.id);
    setState(() => _selectedFolderId = 'root');
    await _refreshFolders();
    _showUndoToast(icon: Icons.folder_delete_rounded, message: 'Pasta excluída.', actionLabel: 'OK', onUndo: () {});
  }

  Future<void> _changeFolderColor(PdfFolder folder) async {
    final colors = <Color>[const Color(0xFF0B5CAD), const Color(0xFF00A2C7), const Color(0xFF2E7D32), const Color(0xFFF9A825), const Color(0xFFC62828), const Color(0xFF6A1B9A)];
    final selected = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cor da pasta'),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final color in colors)
              InkWell(
                onTap: () => Navigator.of(context).pop(color),
                child: CircleAvatar(backgroundColor: color, child: folder.colorValue == color.value ? const Icon(Icons.check, color: Colors.white) : null),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await ref.read(pdfRepositoryProvider).updateFolderColor(folderId: folder.id, colorValue: selected.value);
    await _refreshFolders();
  }

  void _openFolderOptionsSheet(PdfFolder folder) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: Icon(Icons.folder_rounded, color: Color(folder.colorValue)), title: Text(folder.name), subtitle: const Text('Gerenciar pasta')),
          ListTile(leading: const Icon(Icons.drive_file_rename_outline_rounded), title: const Text('Editar nome'), onTap: () { Navigator.of(context).pop(); Future<void>.delayed(const Duration(milliseconds: 120), () => _renameFolder(folder)); }),
          ListTile(leading: const Icon(Icons.palette_outlined), title: const Text('Alterar cor'), onTap: () { Navigator.of(context).pop(); Future<void>.delayed(const Duration(milliseconds: 120), () => _changeFolderColor(folder)); }),
          ListTile(enabled: folder.id != 'root', leading: const Icon(Icons.folder_delete_outlined), title: const Text('Excluir pasta'), onTap: () { Navigator.of(context).pop(); Future<void>.delayed(const Duration(milliseconds: 120), () => _deleteFolder(folder)); }),
        ]),
      ),
    );
  }

  Future<void> _importPdfsFromDevice() async {
    final imported = await ref.read(pdfRepositoryProvider).importPdfsFromDevice();
    if (imported.isEmpty) {
      _showElegantToast(icon: Icons.info_outline_rounded, message: 'Nenhum PDF foi importado.');
      return;
    }
    for (final doc in imported) {
      await ref.read(pdfRepositoryProvider).toggleDocumentInFolder(folderId: _selectedFolderId, documentFile: doc.file);
    }
    await _refreshFolders();
    await ref.read(pdfViewModelProvider.notifier).reload();
    _showElegantToast(icon: Icons.file_upload_rounded, message: '${imported.length} PDF(s) importado(s).');
  }


  Future<void> _openMoveDocumentSheet(PdfDocument document) async {
    await _refreshFolders();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded),
              title: Text(document.title),
              subtitle: const Text('Escolha uma pasta para mover ou adicionar.'),
            ),
            const Divider(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final folder in _folders)
                    ListTile(
                      leading: Icon(folder.id == _selectedFolderId ? Icons.folder_special_rounded : Icons.folder_rounded),
                      title: Text(folder.name),
                      subtitle: Text(folder.documentFiles.contains(document.file) ? 'Já contém este PDF' : 'Adicionar/mover para esta pasta'),
                      onTap: () async {
                        Navigator.of(context).pop();
                        await ref.read(pdfRepositoryProvider).moveDocumentToFolder(folderId: folder.id, documentFile: document.file);
                        setState(() => _selectedFolderId = folder.id);
                        await _refreshFolders();
                        _showElegantToast(icon: Icons.drive_file_move_rounded, message: 'PDF movido para ${folder.name}.');
                      },
                      trailing: IconButton(
                        tooltip: 'Adicionar/remover nesta pasta',
                        icon: Icon(folder.documentFiles.contains(document.file) ? Icons.remove_circle_outline : Icons.add_circle_outline),
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await ref.read(pdfRepositoryProvider).toggleDocumentInFolder(folderId: folder.id, documentFile: document.file);
                          await _refreshFolders();
                          _showElegantToast(icon: Icons.folder_copy_rounded, message: 'Vínculo da pasta atualizado.');
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openFoldersBrowserSheet(List<PdfDocument> documents) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final orderedFolders = [..._folders]..sort((a, b) {
          final depthA = _folderDepth(a);
          final depthB = _folderDepth(b);
          if (depthA != depthB) return depthA.compareTo(depthB);
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        return Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Pastas da biblioteca'),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FilledButton.icon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await Future<void>.delayed(const Duration(milliseconds: 120));
                      await _createFolder(documents);
                    },
                    icon: const Icon(Icons.create_new_folder_rounded),
                    label: const Text('Nova pasta'),
                  ),
                ),
              ],
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FoldersPageHeader(foldersCount: orderedFolders.length, documentsCount: documents.length),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: orderedFolders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final folder = orderedFolders[index];
                          final depth = _folderDepth(folder);
                          return _FolderTreeTile(
                            folder: folder,
                            depth: depth,
                            selected: folder.id == _selectedFolderId,
                            path: _folderPath(folder),
                            onTap: () {
                              setState(() => _selectedFolderId = folder.id);
                              Navigator.of(context).pop();
                            },
                            onOptions: () {
                              Navigator.of(context).pop();
                              Future<void>.delayed(const Duration(milliseconds: 120), () => _openFolderOptionsSheet(folder));
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  int _folderDepth(PdfFolder folder) {
    int depth = 0;
    String? parentId = folder.parentId;
    while (parentId != null && parentId != 'root') {
      final parent = _folders.cast<PdfFolder?>().firstWhere((item) => item?.id == parentId, orElse: () => null);
      if (parent == null) break;
      depth += 1;
      parentId = parent.parentId;
    }
    return depth;
  }

  String _folderPath(PdfFolder folder) {
    if (folder.id == 'root') return 'Biblioteca principal';
    final names = <String>[folder.name];
    String? parentId = folder.parentId;
    while (parentId != null) {
      final parent = _folders.cast<PdfFolder?>().firstWhere((item) => item?.id == parentId, orElse: () => null);
      if (parent == null) break;
      names.insert(0, parent.name);
      if (parent.id == 'root') break;
      parentId = parent.parentId;
    }
    return names.join(' / ');
  }

  void _openQuickActions() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_rounded),
              title: const Text('Criar pasta'),
              subtitle: const Text('Criar dentro da pasta atual.'),
              onTap: () {
                Navigator.of(context).pop();
                Future<void>.delayed(const Duration(milliseconds: 120), () => _createFolder(ref.read(pdfViewModelProvider).value?.documents ?? const <PdfDocument>[]));
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('Buscar PDF no dispositivo'),
              subtitle: const Text('Selecionar arquivos PDF da pasta Documentos/Downloads.'),
              onTap: () {
                Navigator.of(context).pop();
                Future<void>.delayed(const Duration(milliseconds: 120), _importPdfsFromDevice);
              },
            ),
            ListTile(
              leading: const Icon(Icons.search_rounded),
              title: const Text('Buscar'),
              subtitle: const Text('Pesquisar documentos da biblioteca.'),
              onTap: () {
                Navigator.of(context).pop();
                Future<void>.delayed(const Duration(milliseconds: 120), _openSearch);
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_rounded),
              title: const Text('Favoritos'),
              subtitle: const Text('Mostrar apenas documentos favoritos.'),
              onTap: () {
                Navigator.of(context).pop();
                _onNavTap(1);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _onNavTap(int index) {
    if (_searchOpen) _closeSearch();
    setState(() => _selectedIndex = index);

    if (index == 1) {
      final state = ref.read(pdfViewModelProvider).value;
      if (state != null && !state.showOnlyFavorites) {
        ref.read(pdfViewModelProvider.notifier).toggleFavoriteFilter();
      }
      return;
    }

    if (index == 0) {
      final state = ref.read(pdfViewModelProvider).value;
      if (state != null && state.showOnlyFavorites) {
        ref.read(pdfViewModelProvider.notifier).toggleFavoriteFilter();
      }
      return;
    }

    _openMoreSheet();
  }

  Future<void> _openResetDialog(List<PdfDocument> documents) async {
    final keepDocs = documents.map((doc) => doc.file).toSet();
    final keepFolders = _folders.map((folder) => folder.id).where((id) => id != 'root').toSet();
    final result = await showDialog<Map<String, Set<String>>>(
      context: context,
      builder: (context) {
        final selectedDocs = keepDocs.toSet();
        final selectedFolders = keepFolders.toSet();
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            icon: const Icon(Icons.restart_alt_rounded),
            title: const Text('Resetar configurações'),
            content: SizedBox(
              width: 460,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('O reset remove favoritos, páginas salvas, post-its, marcações locais e preferências. Abaixo você escolhe quais PDFs e pastas quer manter visíveis depois do reset.'),
                const SizedBox(height: 14),
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    Text('PDFs a manter', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                    for (final doc in documents)
                      SwitchListTile(
                        dense: true,
                        value: selectedDocs.contains(doc.file),
                        title: Text(doc.title),
                        subtitle: Text(doc.file, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onChanged: (value) => setDialogState(() { value ? selectedDocs.add(doc.file) : selectedDocs.remove(doc.file); }),
                      ),
                    const Divider(),
                    Text('Pastas a manter', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                    for (final folder in _folders.where((folder) => folder.id != 'root'))
                      SwitchListTile(
                        dense: true,
                        value: selectedFolders.contains(folder.id),
                        secondary: Icon(Icons.folder_rounded, color: Color(folder.colorValue)),
                        title: Text(folder.name),
                        onChanged: (value) => setDialogState(() { value ? selectedFolders.add(folder.id) : selectedFolders.remove(folder.id); }),
                      ),
                  ]),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
              FilledButton.icon(onPressed: () => Navigator.of(context).pop(<String, Set<String>>{'docs': selectedDocs, 'folders': selectedFolders}), icon: const Icon(Icons.restart_alt_rounded), label: const Text('Resetar')),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    await ref.read(pdfRepositoryProvider).resetApplicationSettings(keepDocumentFiles: result['docs'], keepFolderIds: result['folders']);
    await _refreshFolders();
    await ref.read(pdfViewModelProvider.notifier).reload();
    if (!mounted) return;
    _showUndoToast(icon: Icons.restart_alt_rounded, message: 'Configurações resetadas.', actionLabel: 'OK', onUndo: () {});
  }

  void _openAboutPage() {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(title: const Text('Sobre o Folhear'), actions: [IconButton(tooltip: 'Fechar', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded))]),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFEAF4FF), Color(0xFFF8FBFF)]), borderRadius: BorderRadius.circular(30), border: Border.all(color: const Color(0xFFB8D9FF))),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(width: 64, height: 64, decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0B5CAD), Color(0xFF2EA7FF)]), borderRadius: BorderRadius.all(Radius.circular(22))), child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 34)),
                          const SizedBox(width: 16),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${AppInfo.name} ${AppInfo.badge}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 8),
                            const Text('Biblioteca inteligente para leitura, consulta e organização de documentos PDF, criada para transformar arquivos soltos em uma experiência prática, visual e acessível.'),
                            const SizedBox(height: 12),
                            Wrap(spacing: 10, runSpacing: 10, children: const [
                              _TinyPill(icon: Icons.folder_copy_rounded, label: 'Pastas'),
                              _TinyPill(icon: Icons.star_rounded, label: 'Favoritos'),
                              _TinyPill(icon: Icons.sticky_note_2_rounded, label: 'Post-its'),
                              _TinyPill(icon: Icons.search_rounded, label: 'Busca'),
                              _TinyPill(icon: Icons.upload_file_rounded, label: 'Importação local'),
                            ]),
                          ])),
                        ]),
                      ),
                      const SizedBox(height: 18),
                      _AboutSection(icon: Icons.account_circle_outlined, title: 'Desenvolvedor da aplicação', paragraphs: const [
                        'Eu, Hagliberto Alves de Oliveira, desenvolvi o Folhear para facilitar minha rotina de consulta, leitura e organização de documentos em PDF. A proposta nasceu da necessidade de reunir materiais importantes em uma biblioteca simples, visual e prática, evitando que arquivos relevantes fiquem espalhados em pastas do computador, downloads do celular ou locais difíceis de localizar rapidamente.',
                        'O aplicativo foi pensado para uso cotidiano, especialmente em cenários de estudo, trabalho, análise documental e consulta recorrente. A ideia é permitir que o usuário importe seus próprios PDFs, organize por pastas, marque documentos favoritos, salve páginas relevantes e registre observações em post-its, mantendo uma experiência leve e direta.',
                      ]),
                      const SizedBox(height: 14),
                      _AboutSection(icon: Icons.auto_awesome_rounded, title: 'Propósito do Folhear', paragraphs: const [
                        'O Folhear não é apenas um visualizador de PDF. Ele funciona como uma biblioteca pessoal inteligente, voltada para leitura orientada e organização progressiva. O usuário começa importando arquivos, depois pode separá-los em pastas, destacar documentos importantes, salvar páginas específicas e criar anotações conforme a leitura evolui.',
                        'A aplicação busca reduzir o tempo gasto procurando documentos e aumentar a produtividade em consultas rápidas. Em vez de depender apenas do nome do arquivo ou da pasta original, o usuário passa a construir uma camada própria de organização, com favoritos, post-its, páginas salvas e agrupamentos personalizados.',
                      ]),
                      const SizedBox(height: 14),
                      _AboutSection(icon: Icons.new_releases_outlined, title: 'Versão da aplicação', paragraphs: const [
                        '${AppInfo.name} ${AppInfo.version}',
                        'Atualizada em ${AppInfo.versionDate}.',
                        'Notas da versão: ${AppInfo.releaseNote}.',
                        'Esta versão reforça a organização visual das páginas principais, melhora a responsividade do cabeçalho, simplifica a tela de pastas para uma árvore única e transfere as informações de desenvolvedor e versão para uma página própria, mais completa e adequada para consulta.',
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openMoreSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      builder: (context) {
        final state = ref.read(pdfViewModelProvider).value;
        final documents = state?.documents ?? const <PdfDocument>[];

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: ListView(
            shrinkWrap: true,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.account_tree_rounded),
                title: const Text('Visualizar como árvore'),
                subtitle: const Text('Mostra a hierarquia das pastas na Home.'),
                value: _showFolderTree,
                onChanged: (value) {
                  setState(() => _showFolderTree = value);
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.create_new_folder_rounded),
                title: const Text('Criar pasta'),
                onTap: () {
                  Navigator.of(context).pop();
                  Future<void>.delayed(const Duration(milliseconds: 120), () => _createFolder(ref.read(pdfViewModelProvider).value?.documents ?? const <PdfDocument>[]));
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_upload_outlined),
                title: const Text('Importar PDFs do dispositivo'),
                subtitle: const Text('Seleciona arquivos PDF do armazenamento do aparelho.'),
                onTap: () {
                  Navigator.of(context).pop();
                  Future<void>.delayed(const Duration(milliseconds: 120), _importPdfsFromDevice);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('Sobre o Folhear'),
                subtitle: const Text('Desenvolvedor, propósito do aplicativo, recursos disponíveis e detalhes completos da versão.'),
                onTap: () {
                  Navigator.of(context).pop();
                  Future<void>.delayed(const Duration(milliseconds: 120), _openAboutPage);
                },
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Text(
                  'Versões dos PDFs',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              for (final doc in documents)
                ListTile(
                  dense: true,
                  leading: Icon(doc.isLocal ? Icons.upload_file_rounded : Icons.picture_as_pdf_outlined),
                  title: Text(doc.title),
                  subtitle: Text('${doc.version} • ${doc.pageCount} páginas'),
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('Limpar busca'),
                onTap: () {
                  _closeSearch();
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.restart_alt_rounded),
                title: const Text('Resetar configurações'),
                subtitle: const Text('Remove favoritos, pastas, PDFs importados, post-its e preferências locais.'),
                onTap: () {
                  Navigator.of(context).pop();
                  Future<void>.delayed(const Duration(milliseconds: 120), () => _openResetDialog(documents));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pdfState = ref.watch(pdfViewModelProvider);
    final isMobile = MediaQuery.sizeOf(context).width < 700;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: isMobile ? 56 : 64,
        titleSpacing: isMobile ? 6 : 12,
        title: const _BrandTitle(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _AnimatedFoldersButton(
              onTap: () {
                final state = ref.read(pdfViewModelProvider).value;
                _openFoldersBrowserSheet(state?.documents ?? const <PdfDocument>[]);
              },
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          pdfState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Center(child: Text('Erro ao carregar documentos:\n$error', textAlign: TextAlign.center)),
            data: (state) {
              final selectedFolder = _folders.cast<PdfFolder?>().firstWhere(
                    (folder) => folder?.id == _selectedFolderId,
                    orElse: () => null,
                  );
              final folderFiles = selectedFolder?.documentFiles.toSet() ?? <String>{};
              final inRoot = _selectedFolderId == 'root';
              final documents = inRoot ? state.filteredDocuments : state.filteredDocuments.where((doc) => folderFiles.contains(doc.file)).toList();
              final isWide = MediaQuery.sizeOf(context).width >= 900;

              return SafeArea(
                bottom: false,
                child: RefreshIndicator(
                  onRefresh: _refreshHome,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                    if (_showFoldersPanel)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(isMobile ? 14 : 24, 8, isMobile ? 14 : 24, 14),
                        sliver: SliverToBoxAdapter(
                          child: _FolderExplorer(
                          folders: _folders,
                          selectedFolderId: _selectedFolderId,
                          treeMode: _showFolderTree,
                          onSelect: (folder) => setState(() => _selectedFolderId = folder.id),
                          onCreate: _createFolder,
                          onRename: _openFolderOptionsSheet,
                        ),
                      ),
                    ),
                    if (_selectedIndex == 1)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(isMobile ? 14 : 24, 0, isMobile ? 14 : 24, 14),
                        sliver: SliverToBoxAdapter(child: _FavoritePagesStrip(documents: state.documents)),
                      ),
                    if (documents.isNotEmpty)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(isMobile ? 14 : 24, 4, isMobile ? 14 : 24, 14),
                        sliver: SliverToBoxAdapter(
                          child: _PageWorkspaceHeader(
                            favoriteMode: _selectedIndex == 1,
                            totalDocuments: documents.length,
                            selectedFolderName: selectedFolder?.name ?? 'Documentos',
                          ),
                        ),
                      ),
                    if (_selectedIndex == 1 && documents.isNotEmpty)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(isMobile ? 14 : 24, 0, isMobile ? 14 : 24, 12),
                        sliver: const SliverToBoxAdapter(child: _FavoritesSectionTitle(icon: Icons.star_rounded, title: 'Documentos favoritos', description: 'PDFs completos marcados com estrela para acesso rápido.')),
                      ),
                    if (documents.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _selectedIndex == 1
                            ? _FavoritesEmptyState(documents: state.documents)
                            : _RichEmptyState(
                                icon: Icons.upload_file_rounded,
                                title: 'Sua biblioteca está vazia no momento',
                                subtitle: 'Para começar a usar o Folhear, importe um ou mais arquivos PDF do seu dispositivo. Você pode montar uma biblioteca pessoal, separar por pastas e depois marcar itens importantes como favoritos.',
                                pills: const [
                                  'Toque no botão +',
                                  'Escolha “Buscar PDF no dispositivo”',
                                  'Importe um ou vários arquivos PDF',
                                  'Organize em pastas e favoritos',
                                ],
                                badges: const [
                                  _InfoBadgeData(label: 'Importação local', icon: Icons.file_upload_rounded, color: Color(0xFF0B5CAD)),
                                  _InfoBadgeData(label: 'Suporte a múltiplos PDFs', icon: Icons.picture_as_pdf_rounded, color: Color(0xFFD32F2F)),
                                  _InfoBadgeData(label: 'Pastas e favoritos', icon: Icons.folder_copy_rounded, color: Color(0xFF2E7D32)),
                                ],
                                details: const [
                                  'A biblioteca só passa a exibir documentos depois que você importar arquivos PDF do armazenamento do aparelho ou do computador.',
                                  'Depois da importação, você poderá abrir o PDF, navegar entre páginas, criar post-its, marcar páginas favoritas e compartilhar documentos.',
                                  'Se desejar, crie pastas para agrupar conteúdos por tema, disciplina, processo, cliente, assunto ou qualquer outro critério de organização.',
                                ],
                              ),
                      )
                    else if (isWide)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 118),
                        sliver: SliverGrid.builder(
                          itemCount: documents.length,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            mainAxisExtent: 150,
                          ),
                          itemBuilder: (context, index) => _PdfItem(
                            document: documents[index],
                            onFavorite: () => _toggleDocumentFavorite(documents[index]),
                            onDelete: () => _deleteDocumentWithUndo(documents[index]),
                            confirmDelete: () => _confirmDeleteDocument(documents[index]),
                            onLongPress: () => _openMoveDocumentSheet(documents[index]),
                            onBeforeOpen: _closeSearch,
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 124),
                        sliver: SliverList.builder(
                          itemCount: documents.length * 2 - 1,
                          itemBuilder: (context, index) {
                            if (index.isOdd) return const SizedBox(height: 12);
                            final document = documents[index ~/ 2];
                            return _PdfItem(
                              document: document,
                              onFavorite: () => _toggleDocumentFavorite(document),
                              onDelete: () => _deleteDocumentWithUndo(document),
                              confirmDelete: () => _confirmDeleteDocument(document),
                              onLongPress: () => _openMoveDocumentSheet(document),
                              onBeforeOpen: _closeSearch,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (false && _searchOpen)
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
      bottomNavigationBar: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: _HomeBottomArea(
          controller: _searchController,
          focusNode: _searchFocus,
          selectedIndex: _selectedIndex,
          searchOpen: _searchOpen,
          onOpenActions: _openQuickActions,
          onCloseSearch: _closeSearch,
          onChanged: (value) => ref.read(pdfViewModelProvider.notifier).updateSearch(value),
          onNavTap: _onNavTap,
        ),
      ),
    );
  }
}

class _PageWorkspaceHeader extends StatelessWidget {
  final bool favoriteMode;
  final int totalDocuments;
  final String selectedFolderName;
  const _PageWorkspaceHeader({required this.favoriteMode, required this.totalDocuments, required this.selectedFolderName});
  @override
  Widget build(BuildContext context) {
    final title = favoriteMode ? 'Favoritos' : 'Biblioteca';
    final description = favoriteMode ? 'Acesse rapidamente PDFs marcados com estrela e páginas salvas para revisão e consulta recorrente.' : 'Gerencie seus PDFs importados, organize por pastas, abra documentos e marque favoritos para acesso rápido.';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFF8FBFF), Color(0xFFEAF4FF)]), borderRadius: BorderRadius.circular(26), border: Border.all(color: const Color(0xFFD4E7FB))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 48, height: 48, decoration: BoxDecoration(gradient: LinearGradient(colors: favoriteMode ? const [Color(0xFFFFB300), Color(0xFFFFE082)] : const [Color(0xFF0B5CAD), Color(0xFF42A5F5)]), borderRadius: BorderRadius.circular(16)), child: Icon(favoriteMode ? Icons.star_rounded : Icons.library_books_rounded, color: Colors.white)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(description, textAlign: TextAlign.justify, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF355C7D), height: 1.45)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [_TinyPill(icon: Icons.picture_as_pdf_rounded, label: '$totalDocuments PDF(s)'), _TinyPill(icon: Icons.folder_rounded, label: selectedFolderName), _TinyPill(icon: favoriteMode ? Icons.bolt_rounded : Icons.touch_app_rounded, label: favoriteMode ? 'Acesso rápido' : 'Toque para abrir')]),
        ])),
      ]),
    );
  }
}

class _FoldersPageHeader extends StatelessWidget {
  final int foldersCount;
  final int documentsCount;
  const _FoldersPageHeader({required this.foldersCount, required this.documentsCount});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFEAF4FF), Color(0xFFF8FBFF)]), borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFB8D9FF))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 46, height: 46, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF0B5CAD), Color(0xFF42A5F5)]), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.account_tree_rounded, color: Colors.white)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Pastas da biblioteca', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('Visualização em árvore para organizar e filtrar seus PDFs por assunto, estudo, trabalho ou qualquer categoria pessoal.', textAlign: TextAlign.justify, style: TextStyle(color: Color(0xFF355C7D), height: 1.45)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [_TinyPill(icon: Icons.folder_open_rounded, label: '$foldersCount pasta(s)'), _TinyPill(icon: Icons.picture_as_pdf_rounded, label: '$documentsCount PDF(s)'), const _TinyPill(icon: Icons.account_tree_rounded, label: 'Árvore')]),
        ])),
      ]),
    );
  }
}

class _AboutSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> paragraphs;
  const _AboutSection({required this.icon, required this.title, required this.paragraphs});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFD7E7F7)), boxShadow: [BoxShadow(color: const Color(0xFF0B5CAD).withOpacity(0.05), blurRadius: 14, offset: const Offset(0, 6))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0xFFEAF4FF), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: const Color(0xFF0B5CAD))), const SizedBox(width: 12), Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)))]),
        const SizedBox(height: 12),
        for (final paragraph in paragraphs) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(paragraph, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.48, color: const Color(0xFF263238)))),
      ]),
    );
  }
}

class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 420;
    final iconSize = compact ? 36.0 : 42.0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 6 : 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFF9FBFF), Color(0xFFEEF6FF)]),
        borderRadius: BorderRadius.circular(compact ? 16 : 20),
        border: Border.all(color: const Color(0xFFD4E7FB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [scheme.primary, const Color(0xFF2EA7FF)]),
              borderRadius: BorderRadius.circular(compact ? 12 : 15),
              boxShadow: [BoxShadow(color: scheme.primary.withOpacity(0.18), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: compact ? 20 : 23),
          ),
          SizedBox(width: compact ? 8 : 10),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(colors: [Color(0xFF0B315E), Color(0xFF0B5CAD), Color(0xFF2EA7FF)]).createShader(bounds),
            child: Text(
              AppInfo.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (compact ? Theme.of(context).textTheme.titleMedium : Theme.of(context).textTheme.titleLarge)?.copyWith(fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.2),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedFoldersButton extends StatefulWidget {
  final VoidCallback onTap;
  const _AnimatedFoldersButton({required this.onTap});

  @override
  State<_AnimatedFoldersButton> createState() => _AnimatedFoldersButtonState();
}

class _AnimatedFoldersButtonState extends State<_AnimatedFoldersButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 430;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 12, vertical: compact ? 7 : 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: _hovered ? [const Color(0xFFEAF4FF), const Color(0xFFD9EEFF)] : [const Color(0xFFF5FAFF), const Color(0xFFEAF4FF)]),
            borderRadius: BorderRadius.circular(compact ? 15 : 18),
            border: Border.all(color: const Color(0xFFB8D9FF)),
            boxShadow: [BoxShadow(color: const Color(0xFF0B5CAD).withOpacity(_hovered ? 0.18 : 0.08), blurRadius: _hovered ? 16 : 8, offset: const Offset(0, 5))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_copy_rounded, color: Color(0xFF0B5CAD)),
              if (!compact) ...[
                const SizedBox(width: 8),
                const Text('Pastas', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0B315E))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderGridCard extends StatelessWidget {
  final PdfFolder folder;
  final bool selected;
  final bool treeMode;
  final String path;
  final VoidCallback onTap;
  final VoidCallback onOptions;

  const _FolderGridCard({required this.folder, required this.selected, required this.treeMode, required this.path, required this.onTap, required this.onOptions});

  @override
  Widget build(BuildContext context) {
    final color = Color(folder.colorValue);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: selected ? [color.withOpacity(0.18), color.withOpacity(0.08)] : [Colors.white, const Color(0xFFF8FBFF)]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: selected ? color.withOpacity(0.7) : const Color(0xFFD9EAF9), width: selected ? 1.4 : 1),
        boxShadow: [BoxShadow(color: color.withOpacity(selected ? 0.18 : 0.08), blurRadius: selected ? 18 : 12, offset: const Offset(0, 8))],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        onLongPress: onOptions,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: color.withOpacity(0.16), borderRadius: BorderRadius.circular(14)),
                    child: Icon(folder.id == 'root' ? Icons.home_filled : Icons.folder_rounded, color: color),
                  ),
                  const Spacer(),
                  IconButton(visualDensity: VisualDensity.compact, onPressed: onOptions, icon: const Icon(Icons.more_horiz_rounded)),
                ],
              ),
              const SizedBox(height: 8),
              Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(path, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF546E7A))),
              const Spacer(),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TinyPill(icon: Icons.picture_as_pdf_rounded, label: '${folder.documentFiles.length} PDF(s)'),
                  _TinyPill(icon: treeMode ? Icons.account_tree_rounded : Icons.grid_view_rounded, label: treeMode ? 'Árvore' : 'Coluna'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBadgeData {
  final String label;
  final IconData icon;
  final Color color;
  const _InfoBadgeData({required this.label, required this.icon, required this.color});
}


class _FolderFormSection extends StatelessWidget {
  final TextEditingController nameController;
  final List<Color> colors;
  final Color selectedColor;
  final ValueChanged<Color> onColorChanged;

  const _FolderFormSection({
    required this.nameController,
    required this.colors,
    required this.selectedColor,
    required this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD7E7F7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Informações da pasta', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          TextField(
            controller: nameController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Nome da pasta',
              hintText: 'Ex.: Estudos, Processos, Editais, Revisão',
              prefixIcon: const Icon(Icons.drive_file_rename_outline_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
              filled: true,
            ),
          ),
          const SizedBox(height: 16),
          Text('Cor da pasta', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final color in colors)
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => onColorChanged(color),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: selectedColor.value == color.value ? Colors.black12 : Colors.transparent, width: 3),
                      boxShadow: [BoxShadow(color: color.withOpacity(selectedColor.value == color.value ? 0.35 : 0.16), blurRadius: 12, offset: const Offset(0, 5))],
                    ),
                    child: selectedColor.value == color.value ? const Icon(Icons.check_rounded, color: Colors.white) : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF8FBFF), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFD7E7F7))),
            child: const Text(
              'Use nomes objetivos e cores diferentes para separar estudos, normas, relatórios, processos e materiais de consulta rápida.',
              textAlign: TextAlign.justify,
              style: TextStyle(color: Color(0xFF355C7D), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderDocumentsSection extends StatelessWidget {
  final List<PdfDocument> availableDocuments;
  final Set<String> selectedFiles;
  final void Function(String file, bool selected) onToggleFile;

  const _FolderDocumentsSection({
    required this.availableDocuments,
    required this.selectedFiles,
    required this.onToggleFile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD7E7F7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Selecionar PDFs para vincular', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFFEAF4FF), borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFFB8D9FF))),
                child: Text('${selectedFiles.length} selecionado(s)', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0B5CAD))),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (availableDocuments.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFFFE082))),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: Color(0xFFF57F17)),
                  SizedBox(width: 10),
                  Expanded(child: Text('Ainda não há PDFs importados na biblioteca. Crie a pasta agora e vincule documentos depois, assim que fizer o upload dos arquivos PDF.')),
                ],
              ),
            )
          else ...[
            const Text('Selecione um ou vários PDFs para adicionar automaticamente à pasta assim que ela for criada.', textAlign: TextAlign.justify),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final doc in availableDocuments)
                      FilterChip(
                        selected: selectedFiles.contains(doc.file),
                        avatar: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Color(0xFFD32F2F)),
                        label: SizedBox(
                          width: 220,
                          child: Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        onSelected: (value) => onToggleFile(doc.file, value),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FolderTreeTile extends StatelessWidget {
  final PdfFolder folder;
  final int depth;
  final bool selected;
  final String path;
  final VoidCallback onTap;
  final VoidCallback onOptions;

  const _FolderTreeTile({
    required this.folder,
    required this.depth,
    required this.selected,
    required this.path,
    required this.onTap,
    required this.onOptions,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(folder.colorValue);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.fromLTRB(16 + (depth * 20), 14, 16, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: selected ? [color.withOpacity(0.16), color.withOpacity(0.05)] : [Colors.white, const Color(0xFFF8FBFF)]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? color.withOpacity(0.65) : const Color(0xFFD7E7F7)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(14)),
                child: Icon(folder.id == 'root' ? Icons.home_filled : Icons.folder_rounded, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(path, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF546E7A))),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _TinyPill(icon: Icons.picture_as_pdf_rounded, label: '${folder.documentFiles.length} PDF(s)'),
              IconButton(onPressed: onOptions, icon: const Icon(Icons.more_horiz_rounded)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RichEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> pills;
  final List<_InfoBadgeData> badges;
  final List<String> details;

  const _RichEmptyState({required this.icon, required this.title, required this.subtitle, required this.pills, required this.badges, required this.details});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFF7FBFF), Color(0xFFEAF4FF)]),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: const Color(0xFFB8D9FF)),
              boxShadow: [BoxShadow(color: const Color(0xFF0B5CAD).withOpacity(0.10), blurRadius: 28, offset: const Offset(0, 14))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF0B5CAD), Color(0xFF42A5F5)]),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [BoxShadow(color: const Color(0xFF0B5CAD).withOpacity(0.20), blurRadius: 18, offset: const Offset(0, 8))],
                      ),
                      child: Icon(icon, size: 32, color: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 8),
                          Text(subtitle, textAlign: TextAlign.justify, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.45)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(spacing: 10, runSpacing: 10, children: [for (final pill in pills) _TinyPill(icon: Icons.check_circle_outline_rounded, label: pill)]),
                const SizedBox(height: 14),
                Wrap(spacing: 10, runSpacing: 10, children: [for (final badge in badges) _InfoBadge(badge: badge)]),
                const SizedBox(height: 18),
                ...details.map((detail) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.arrow_right_rounded, color: Color(0xFF0B5CAD)),
                          ),
                          const SizedBox(width: 6),
                          Expanded(child: Text(detail, textAlign: TextAlign.justify, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45))),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FavoritesEmptyState extends ConsumerWidget {
  final List<PdfDocument> documents;
  const _FavoritesEmptyState({required this.documents});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<FavoritePdfPage>>(
      future: ref.read(pdfRepositoryProvider).getFavoritePages(),
      builder: (context, snapshot) {
        final favoritePages = snapshot.data ?? const <FavoritePdfPage>[];
        final hasFavoritePages = favoritePages.isNotEmpty;
        return _RichEmptyState(
          icon: Icons.star_rounded,
          title: hasFavoritePages ? 'Você ainda não favoritou documentos completos' : 'Sua área de favoritos está vazia',
          subtitle: hasFavoritePages
              ? 'Você já salvou páginas favoritas, mas ainda não marcou documentos inteiros como favoritos. Toque na estrela de qualquer PDF para destacar o documento completo e facilitar o acesso futuro.'
              : 'Marque documentos ou páginas como favoritos para montar um atalho pessoal com os conteúdos mais importantes. Assim você encontra rapidamente seus materiais principais dentro do Folhear.',
          pills: hasFavoritePages
              ? const [
                  'Páginas favoritas podem aparecer acima',
                  'Use a estrela do PDF para favoritar o documento inteiro',
                  'Abra um PDF e favorite páginas específicas',
                  'Monte uma área de consulta rápida',
                ]
              : const [
                  'Favorite documentos inteiros',
                  'Favorite páginas importantes',
                  'Crie uma rotina de consulta rápida',
                  'Use favoritos para estudo e revisão',
                ],
          badges: const [
            _InfoBadgeData(label: 'Favoritos de documentos', icon: Icons.star_rounded, color: Color(0xFFFFA000)),
            _InfoBadgeData(label: 'Páginas salvas', icon: Icons.bookmark_added_rounded, color: Color(0xFF2E7D32)),
            _InfoBadgeData(label: 'Acesso rápido', icon: Icons.bolt_rounded, color: Color(0xFF5E35B1)),
          ],
          details: hasFavoritePages
              ? const [
                  'Você pode continuar usando as páginas favoritas já salvas e, quando quiser, também destacar o PDF completo tocando no ícone de estrela na biblioteca.',
                  'Favoritar o documento inteiro é útil quando você consulta repetidamente o mesmo arquivo, independentemente da página.',
                  'Favoritar páginas específicas é ideal para revisões, resumos, leis, artigos, normas e trechos importantes dentro de um PDF maior.',
                ]
              : const [
                  'Na biblioteca, toque no ícone de estrela em qualquer cartão de PDF para adicionar ou remover o documento da sua lista de favoritos.',
                  'Dentro do visualizador de PDF, você também pode salvar páginas específicas para voltar exatamente ao trecho que precisa consultar depois.',
                  'A aba Favoritos funciona como uma área de acesso rápido para estudos, trabalho, revisão de documentos ou leitura frequente.',
                ],
        );
      },
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final _InfoBadgeData badge;
  const _InfoBadge({required this.badge});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: badge.color.withOpacity(0.10), borderRadius: BorderRadius.circular(999), border: Border.all(color: badge.color.withOpacity(0.28))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badge.icon, size: 16, color: badge.color),
          const SizedBox(width: 8),
          Text(badge.label, style: TextStyle(fontWeight: FontWeight.w800, color: badge.color)),
        ],
      ),
    );
  }
}

class _TinyPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _TinyPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFFD8E6F3))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF0B5CAD)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF355C7D))),
        ],
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  final int total;
  final bool favoriteMode;
  const _HeroHeader({required this.total, required this.favoriteMode});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [scheme.primaryContainer, scheme.surfaceContainerHighest]),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            favoriteMode ? 'Favoritos' : 'Biblioteca',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 4),
          Text('$total documento(s) importado(s)', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onPrimaryContainer)),
        ],
      ),
    );
  }
}

class _FolderExplorer extends StatelessWidget {
  final List<PdfFolder> folders;
  final String selectedFolderId;
  final bool treeMode;
  final ValueChanged<PdfFolder> onSelect;
  final VoidCallback onCreate;
  final ValueChanged<PdfFolder> onRename;

  const _FolderExplorer({
    required this.folders,
    required this.selectedFolderId,
    required this.treeMode,
    required this.onSelect,
    required this.onCreate,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final visibleFolders = treeMode ? folders : folders.where((folder) => folder.parentId == selectedFolderId || folder.id == 'root').toList();
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.62),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(treeMode ? Icons.account_tree_rounded : Icons.folder_open_rounded, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(treeMode ? 'Árvore de pastas' : 'Pastas', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                ),
                IconButton(tooltip: 'Criar pasta', onPressed: onCreate, icon: const Icon(Icons.create_new_folder_rounded)),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: treeMode ? 158 : 48,
              child: treeMode
                  ? ListView(
                      children: [
                        for (final folder in folders)
                          Padding(
                            padding: EdgeInsets.only(left: folder.parentId == null ? 0 : 18),
                            child: _FolderChip(folder: folder, selected: folder.id == selectedFolderId, onTap: () => onSelect(folder), onLongPress: () => onRename(folder)),
                          ),
                      ],
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: visibleFolders.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final folder = visibleFolders[index];
                        return _FolderChip(folder: folder, selected: folder.id == selectedFolderId, onTap: () => onSelect(folder), onLongPress: () => onRename(folder));
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderChip extends StatelessWidget {
  final PdfFolder folder;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FolderChip({required this.folder, required this.selected, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: FilterChip(
        selected: selected,
        avatar: Icon(folder.id == 'root' ? Icons.folder_special_rounded : Icons.folder_rounded, size: 18, color: Color(folder.colorValue)),
        label: Text(folder.name),
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _PdfItem extends StatelessWidget {
  final PdfDocument document;
  final Future<void> Function() onFavorite;
  final Future<void> Function() onDelete;
  final Future<bool> Function() confirmDelete;
  final VoidCallback onLongPress;
  final VoidCallback? onBeforeOpen;

  const _PdfItem({required this.document, required this.onFavorite, required this.onDelete, required this.confirmDelete, required this.onLongPress, this.onBeforeOpen});

  @override
  Widget build(BuildContext context) {
    void openDocument() {
      onBeforeOpen?.call();
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PdfViewerPage(document: document)));
    }

    return Dismissible(
      key: ValueKey('pdf-${document.file}-${document.isFavorite}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await onFavorite();
          return false;
        }
        return confirmDelete();
      },
      onDismissed: (_) async => onDelete(),
      background: _SwipeFavoriteBackground(isFavorite: document.isFavorite, alignment: Alignment.centerLeft),
      secondaryBackground: const _SwipeDeleteBackground(),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        scale: 1,
        child: PdfCard(document: document, onFavoriteTap: onFavorite, onOpenTap: openDocument, onLongPress: onLongPress),
      ),
    );
  }
}

class _SwipeDeleteBackground extends StatelessWidget {
  const _SwipeDeleteBackground();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(18)),
      child: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
    );
  }
}

class _SwipeFavoriteBackground extends StatelessWidget {
  final bool isFavorite;
  final Alignment alignment;

  const _SwipeFavoriteBackground({required this.isFavorite, required this.alignment});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(color: isFavorite ? scheme.errorContainer : scheme.primaryContainer, borderRadius: BorderRadius.circular(18)),
      child: Icon(isFavorite ? Icons.star_border_rounded : Icons.star_rounded, color: isFavorite ? scheme.onErrorContainer : scheme.onPrimaryContainer),
    );
  }
}

class _FavoritesSectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  const _FavoritesSectionTitle({required this.icon, required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD7E7F7)),
        boxShadow: [BoxShadow(color: const Color(0xFF0B5CAD).withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: const Color(0xFFEAF4FF), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: const Color(0xFF0B5CAD))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(description, textAlign: TextAlign.justify, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF355C7D), height: 1.35)),
          ])),
        ],
      ),
    );
  }
}

class _FavoritePagesStrip extends ConsumerWidget {
  final List<PdfDocument> documents;

  const _FavoritePagesStrip({required this.documents});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<FavoritePdfPage>>(
      future: ref.read(pdfRepositoryProvider).getFavoritePages(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <FavoritePdfPage>[];
        if (items.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _FavoritesSectionTitle(icon: Icons.bookmark_added_rounded, title: 'Páginas salvas', description: 'Trechos e páginas específicas que você marcou dentro dos PDFs para voltar exatamente ao ponto importante.'),
            const SizedBox(height: 10),
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final doc = documents.firstWhere(
                    (doc) => doc.file == item.file,
                    orElse: () => PdfDocument(file: item.file, title: item.title, description: '', version: 'v1.0', pageCount: item.page),
                  );

                  return SizedBox(
                    width: 270,
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onLongPress: () async {
                          await ref.read(pdfRepositoryProvider).togglePageFavorite(document: doc, page: item.page);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Página removida dos favoritos.')));
                        },
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PdfViewerPage(document: doc, initialPage: item.page))),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Chip(avatar: const Icon(Icons.bookmark, size: 16), label: Text('${item.title} • pág. ${item.page}'), visualDensity: VisualDensity.compact),
                              const SizedBox(height: 6),
                              Text(item.preview, maxLines: 3, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HomeBottomArea extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final int selectedIndex;
  final bool searchOpen;
  final VoidCallback onOpenActions;
  final VoidCallback onCloseSearch;
  final ValueChanged<String> onChanged;
  final ValueChanged<int> onNavTap;

  const _HomeBottomArea({
    required this.controller,
    required this.focusNode,
    required this.selectedIndex,
    required this.searchOpen,
    required this.onOpenActions,
    required this.onCloseSearch,
    required this.onChanged,
    required this.onNavTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: searchOpen
                    ? SizedBox(
                        key: const ValueKey('home-search-field'),
                        height: 48,
                        child: SearchBar(
                          controller: controller,
                          focusNode: focusNode,
                          leading: const Icon(Icons.search),
                          hintText: 'Pesquisar documentos',
                          onChanged: onChanged,
                          trailing: [IconButton(tooltip: 'Fechar busca', icon: const Icon(Icons.close), onPressed: onCloseSearch)],
                        ),
                      )
                    : FloatingActionButton.small(
                        key: const ValueKey('home-actions-button'),
                        heroTag: 'home-actions-button',
                        tooltip: 'Ações rápidas',
                        onPressed: onOpenActions,
                        child: const Icon(Icons.add_rounded, color: Color(0xFF0D47A1)),
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
