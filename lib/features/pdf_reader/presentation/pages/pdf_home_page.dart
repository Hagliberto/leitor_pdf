import 'dart:ui' show FontFeature;

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
  int _favoriteSectionIndex = 0;
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

  PdfFolder? _findFolderById(String? folderId) {
    if (folderId == null) return null;
    return _folders.cast<PdfFolder?>().firstWhere(
          (folder) => folder?.id == folderId,
          orElse: () => null,
        );
  }

  String _categoryLabelForFolder(PdfFolder? folder) {
    if (folder == null || folder.id == 'root') return 'Biblioteca';
    if (folder.parentId == 'root') {
      return (folder.categoryName?.trim().isNotEmpty ?? false)
          ? folder.categoryName!.trim()
          : folder.name;
    }
    final parent = _findFolderById(folder.parentId);
    if (parent == null) return folder.name;
    return (parent.categoryName?.trim().isNotEmpty ?? false)
        ? parent.categoryName!.trim()
        : parent.name;
  }

  Future<void> _importPdfsToFolder(PdfFolder folder) async {
    final repo = ref.read(pdfRepositoryProvider);
    final beforeDocuments = ref.read(pdfViewModelProvider).value?.documents ?? const <PdfDocument>[];
    final logId = await repo.addOperationLog(
      action: 'Importação de PDF',
      title: 'Importação em pasta',
      detail: 'Estado anterior salvo antes de importar arquivos diretamente para a pasta "${folder.name}".',
    );
    final imported = await repo.importPdfsFromDevice();
    if (imported.isEmpty) {
      if (mounted) {
        _showElegantToast(
          icon: Icons.info_outline_rounded,
          message: 'Nenhum PDF foi importado para "${folder.name}".',
        );
      }
      return;
    }

    for (final document in imported) {
      await repo.moveDocumentToFolder(
        folderId: folder.id,
        documentFile: document.file,
      );
    }
    await _resolveImportedDuplicates(imported: imported, previousDocuments: beforeDocuments);

    await ref.read(pdfViewModelProvider.notifier).reload();
    await _refreshFolders();
    if (!mounted) return;
    setState(() {
      _selectedFolderId = folder.id;
      _selectedIndex = 0;
      _showFoldersPanel = true;
    });
    await _checkLogCacheHealth();
    _showUndoToast(
      icon: Icons.upload_file_rounded,
      message:
          '${imported.length} PDF(s) importado(s) diretamente para "${folder.name}".',
      actionLabel: 'Desfazer',
      onUndo: () async => _restoreOperationAndRefresh(logId),
    );
  }

  void _showElegantToast({
    required IconData icon,
    required String message,
    VoidCallback? onUndo,
    String actionLabel = 'Desfazer',
  }) {
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
          builder: (context, value, child) =>
              Transform.scale(scale: value, child: child),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEAF4FF), Color(0xFFF8FBFF)],
              ),
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
                    style: const TextStyle(
                      color: Color(0xFF0B315E),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const _ToastCountdownPill(seconds: 3),
                if (onUndo != null) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF0B5CAD),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      onUndo.call();
                    },
                    icon: const Icon(Icons.undo_rounded, size: 16),
                    label: Text(actionLabel),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showUndoToast({
    required IconData icon,
    required String message,
    String actionLabel = 'Desfazer',
    required VoidCallback onUndo,
  }) {
    _showElegantToast(
      icon: icon,
      message: message,
      actionLabel: actionLabel,
      onUndo: onUndo,
    );
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (context.mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    });
  }

  Future<void> _restoreOperationAndRefresh(String logId, {bool offerUndo = false}) async {
    String? undoRestoreLogId;
    if (offerUndo) {
      undoRestoreLogId = await ref.read(pdfRepositoryProvider).addOperationLog(
            action: 'Restauração desfeita',
            title: 'Estado antes da restauração',
            detail: 'Ponto salvo automaticamente para permitir desfazer a restauração recém-aplicada.',
          );
    }
    await ref.read(pdfRepositoryProvider).restoreOperationLog(logId);
    await _refreshFolders();
    await ref.read(pdfViewModelProvider.notifier).reload();
    if (mounted) setState(() {});
    if (offerUndo && undoRestoreLogId != null && mounted) {
      _showUndoToast(
        icon: Icons.restore_rounded,
        message: 'Estado anterior restaurado.',
        actionLabel: 'Desfazer restauração',
        onUndo: () async => _restoreOperationAndRefresh(undoRestoreLogId!),
      );
    }
  }

  String _normalizeDuplicateName(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<Map<String, dynamic>?> _askDuplicateResolution({
    required String title,
    required String existingName,
    required String incomingName,
    required IconData icon,
    required Color color,
  }) async {
    final renameController = TextEditingController(text: '$incomingName (2)');
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        icon: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, color: color, size: 30),
        ),
        title: Text(title, textAlign: TextAlign.center),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Já existe um item chamado "$existingName". Para evitar confusão na biblioteca, escolha como o Folhear deve tratar o novo item "$incomingName".',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: renameController,
                decoration: const InputDecoration(
                  labelText: 'Novo nome para manter os dois',
                  helperText: 'Use quando quiser preservar o original e também salvar o novo item.',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(<String, dynamic>{'action': 'keepOriginal'}),
            icon: const Icon(Icons.shield_outlined),
            label: const Text('Manter original'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context).pop(<String, dynamic>{'action': 'replace'}),
            icon: const Icon(Icons.swap_horiz_rounded),
            label: const Text('Substituir'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(<String, dynamic>{
              'action': 'rename',
              'name': renameController.text.trim().isEmpty ? '$incomingName (2)' : renameController.text.trim(),
            }),
            icon: const Icon(Icons.drive_file_rename_outline_rounded),
            label: const Text('Manter os dois'),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>?> _resolveFolderDuplicate({
    required String name,
    required String parentId,
  }) async {
    final normalized = _normalizeDuplicateName(name);
    // Evita criar categorias/expanders ou pastas com o mesmo nome visual.
    // Primeiro procura no mesmo nível da hierarquia; se não achar, procura em
    // toda a biblioteca para impedir duplicidades confusas na navegação.
    final existingSameParent = _folders.cast<PdfFolder?>().firstWhere(
          (folder) => folder?.parentId == parentId && _normalizeDuplicateName(folder?.name ?? '') == normalized,
          orElse: () => null,
        );
    final existingAnywhere = existingSameParent ?? _folders.cast<PdfFolder?>().firstWhere(
          (folder) => folder?.id != 'root' && _normalizeDuplicateName(folder?.name ?? '') == normalized,
          orElse: () => null,
        );
    final existing = existingAnywhere;
    if (existing == null) return <String, dynamic>{'name': name, 'replaceFolderId': null};
    final decision = await _askDuplicateResolution(
      title: 'Pasta com mesmo nome',
      existingName: existing.name,
      incomingName: name,
      icon: Icons.folder_copy_rounded,
      color: Color(existing.colorValue),
    );
    if (decision == null || decision['action'] == 'keepOriginal') return null;
    if (decision['action'] == 'replace') {
      return <String, dynamic>{'name': name, 'replaceFolderId': existing.id};
    }
    return <String, dynamic>{'name': decision['name'] as String, 'replaceFolderId': null};
  }

  Future<void> _resolveImportedDuplicates({
    required List<PdfDocument> imported,
    required List<PdfDocument> previousDocuments,
  }) async {
    if (imported.isEmpty || previousDocuments.isEmpty) return;
    final repo = ref.read(pdfRepositoryProvider);
    for (final incoming in imported) {
      final existing = previousDocuments.cast<PdfDocument?>().firstWhere(
            (doc) => _normalizeDuplicateName(doc?.title ?? '') == _normalizeDuplicateName(incoming.title),
            orElse: () => null,
          );
      if (existing == null) continue;
      final decision = await _askDuplicateResolution(
        title: 'PDF com mesmo nome',
        existingName: existing.title,
        incomingName: incoming.title,
        icon: Icons.picture_as_pdf_rounded,
        color: const Color(0xFFD32F2F),
      );
      final action = decision?['action'];
      if (action == null || action == 'keepOriginal') {
        await repo.deleteDocument(incoming.file);
        await repo.addOperationLog(
          action: 'Duplicidade de PDF',
          title: 'Original preservado',
          detail: 'O PDF importado "${incoming.title}" foi ocultado para preservar o arquivo original já existente.',
        );
      } else if (action == 'replace') {
        await repo.deleteDocument(existing.file);
        await repo.addOperationLog(
          action: 'Duplicidade de PDF',
          title: 'PDF substituído',
          detail: 'O PDF antigo "${existing.title}" foi removido e o novo arquivo importado assumiu o lugar dele.',
        );
      } else if (action == 'rename') {
        final newName = decision?['name'] as String? ?? '${incoming.title} (2)';
        await repo.renameDocumentTitle(file: incoming.file, title: newName);
        await repo.addOperationLog(
          action: 'Duplicidade de PDF',
          title: 'PDF renomeado',
          detail: 'O novo PDF "${incoming.title}" foi mantido como "$newName".',
        );
      }
    }
  }

  Future<void> _checkLogCacheHealth() async {
    final repo = ref.read(pdfRepositoryProvider);
    final logs = await repo.getOperationLogs();
    if (!mounted || logs.length < 100) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        icon: const Icon(Icons.cleaning_services_rounded, color: Color(0xFF1565C0)),
        title: const Text('Limpar cache de histórico?'),
        content: const Text(
          'O Folhear mantém um histórico em memória local para permitir desfazer ações recentes. Há muitos registros armazenados; limpar o cache deixa a aplicação mais leve, mas remove os pontos de restauração antigos. O próprio Folhear também remove automaticamente registros com mais de 48 horas.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Manter por enquanto')),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_sweep_rounded),
            label: const Text('Limpar cache'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await repo.clearOperationLogs();
      if (mounted) {
        _showElegantToast(icon: Icons.cleaning_services_rounded, message: 'Cache de histórico limpo com segurança.');
      }
    }
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
      icon:
          document.isFavorite ? Icons.star_border_rounded : Icons.star_rounded,
      message: document.isFavorite
          ? 'Documento removido dos favoritos.'
          : 'Documento favoritado.',
    );
  }

  Future<bool> _confirmDeleteDocument(PdfDocument document) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
        contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFD32F2F), Color(0xFFFF7043)]),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(color: const Color(0xFFD32F2F).withOpacity(0.20), blurRadius: 18, offset: const Offset(0, 8)),
                ],
              ),
              child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Excluir PDF da biblioteca?'),
                  const SizedBox(height: 6),
                  Text(
                    'A remoção é segura e pode ser desfeita logo em seguida.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF607D8B), height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Container(
          width: 520,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFFFF4F4), Color(0xFFFFFBFB)]),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFFFCDD2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(document.title, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF7F1D1D))),
              const SizedBox(height: 10),
              const Text(
                'Este PDF será removido da lista principal e de todas as pastas em que estiver vinculado. Depois da confirmação, o Folhear exibirá um aviso com contador regressivo de 3 segundos para desfazer a ação.',
                style: TextStyle(color: Color(0xFF3F3F46), height: 1.45),
              ),
              const SizedBox(height: 12),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoBadge(badge: _InfoBadgeData(label: 'Desfazer disponível', icon: Icons.undo_rounded, color: Color(0xFF1565C0))),
                  _InfoBadge(badge: _InfoBadgeData(label: 'Remove vínculos', icon: Icons.link_off_rounded, color: Color(0xFFD32F2F))),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
              onPressed: () => Navigator.of(context).pop(false),
              icon: const Icon(Icons.close_rounded),
              label: const Text('Cancelar')),
          FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white),
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Excluir PDF')),
        ],
      ),
    );
    return confirm ?? false;
  }


  Future<void> _deleteDocumentWithUndo(PdfDocument document) async {
    final logId = await ref.read(pdfRepositoryProvider).addOperationLog(
      action: 'Exclusão de PDF',
      title: document.title,
      detail: 'PDF removido da biblioteca. É possível restaurar pelo histórico enquanto o registro estiver no cache de 48h.',
    );
    await ref.read(pdfRepositoryProvider).deleteDocument(document.file);
    await _refreshFolders();
    await ref.read(pdfViewModelProvider.notifier).reload();
    if (!mounted) return;
    _showUndoToast(
      icon: Icons.delete_outline_rounded,
      message: 'PDF removido da biblioteca.',
      actionLabel: 'Desfazer',
      onUndo: () async {
        await _restoreOperationAndRefresh(logId);
      },
    );
  }

  Future<String?> _askFolderName(
      {String title = 'Nova pasta', String initialValue = ''}) async {
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
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Salvar')),
        ],
      ),
    );
    controller.dispose();
    final cleaned = value?.trim();
    if (cleaned == null || cleaned.isEmpty) return null;
    return cleaned;
  }


  List<_PresetFolderTemplate> _presetFolderTemplates() => const [
        _PresetFolderTemplate(
          title: 'Documentos Pessoais',
          colorValue: 0xFF1565C0,
          icon: Icons.badge_rounded,
          description:
              'Estrutura recomendada para concentrar os documentos mais recorrentes da vida pessoal. Esta categoria funciona bem para guardar desde registros de identificação e saúde até comprovantes patrimoniais, contas fixas e materiais financeiros que precisam de consulta rápida em momentos importantes.',
          children: [
            'Identificação',
            'Saúde',
            'Finanças Pessoais',
            'Contas Fixas',
            'Bens e Propriedades',
          ],
        ),
        _PresetFolderTemplate(
          title: 'Documentos Escolares / Acadêmicos',
          colorValue: 0xFF2E7D32,
          icon: Icons.school_rounded,
          description:
              'Modelo pensado para estudantes, professores e pesquisadores que precisam separar histórico, matrícula, disciplinas, projetos e certificados. A estrutura favorece consultas por etapa da formação e ajuda a manter registros acadêmicos sempre localizáveis.',
          children: [
            'Histórico e Diplomas',
            'Matrícula',
            'Disciplinas',
            'Pesquisa e Projetos',
            'Cursos Extracurriculares',
          ],
        ),
        _PresetFolderTemplate(
          title: 'Documentos de Escritório e Normativos',
          colorValue: 0xFF6A1B9A,
          icon: Icons.business_center_rounded,
          description:
              'Estrutura robusta para ambientes administrativos, operacionais e institucionais. Ela foi desenhada para acomodar normas, POPs, manuais, contratos, acordos, documentos de RH e materiais de apoio que normalmente exigem organização por tipo documental e frequência de uso.',
          children: [
            'Normas',
            'POP',
            'Procedimentos',
            'Manuais',
            'Cartilhas',
            'Acordos',
            'Contratos',
            'Carreira e RH',
            'Administrativo',
          ],
        ),
        _PresetFolderTemplate(
          title: 'Financeiro e Contábil',
          colorValue: 0xFFF9A825,
          icon: Icons.account_balance_wallet_rounded,
          description:
              'Ideal para organizar fluxo financeiro, obrigações fiscais e controle contábil. Essa estrutura atende bem tanto uso pessoal quanto profissional, separando comprovantes, notas, impostos, extratos, planejamento orçamentário e documentos de prestação de contas.',
          children: [
            'Extratos Bancários',
            'Notas Fiscais',
            'Impostos e Tributos',
            'Boletos e Comprovantes',
            'Orçamentos',
            'Relatórios Contábeis',
          ],
        ),
        _PresetFolderTemplate(
          title: 'Jurídico e Contratual',
          colorValue: 0xFFC62828,
          icon: Icons.gavel_rounded,
          description:
              'Voltada para contratos, processos, pareceres e documentação jurídica de acompanhamento contínuo. A proposta aqui é facilitar o arquivamento por natureza do documento, reduzindo o tempo gasto para localizar peças, termos, notificações e evidências anexadas.',
          children: [
            'Contratos Ativos',
            'Contratos Encerrados',
            'Processos',
            'Procurações',
            'Pareceres',
            'Notificações e Ofícios',
          ],
        ),
        _PresetFolderTemplate(
          title: 'Projetos e Clientes',
          colorValue: 0xFF00838F,
          icon: Icons.handshake_rounded,
          description:
              'Estrutura indicada para profissionais autônomos, consultorias e equipes que trabalham com múltiplos clientes ou projetos em paralelo. Ela ajuda a agrupar propostas, escopos, entregas, reuniões e documentos finais dentro de um mesmo contexto operacional.',
          children: [
            'Propostas',
            'Contratos do Cliente',
            'Briefings',
            'Entregas',
            'Atas e Reuniões',
            'Relatórios Finais',
          ],
        ),
        _PresetFolderTemplate(
          title: 'Imóveis, Veículos e Patrimônio',
          colorValue: 0xFF5D4037,
          icon: Icons.home_work_rounded,
          description:
              'Estrutura focada em bens patrimoniais e documentação de longo prazo. É útil para manter registros de compra, propriedade, manutenção, seguros e taxas relacionadas a imóveis, veículos e outros ativos que exigem histórico organizado.',
          children: [
            'Escrituras e Registros',
            'IPTU / Taxas',
            'Financiamentos',
            'Seguros',
            'Manutenção',
            'Documentação de Veículos',
          ],
        ),
        _PresetFolderTemplate(
          title: 'Saúde e Família',
          colorValue: 0xFF455A64,
          icon: Icons.favorite_rounded,
          description:
              'Modelo pensado para centralizar exames, receitas, laudos, vacinação, convênios e documentos familiares sensíveis. A organização por tema facilita o acesso rápido em atendimentos, viagens, emergências ou revisões periódicas de histórico médico.',
          children: [
            'Exames',
            'Receitas e Prescrições',
            'Laudos e Relatórios',
            'Vacinação',
            'Convênios',
            'Documentos da Família',
          ],
        ),
      ];

  Future<void> _createPresetFolderTemplates() async {
    final templates = _presetFolderTemplates();
    final selected = await showModalBottomSheet<_PresetFolderSelection>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        final selectedChildren = <String, Set<String>>{
          for (final template in templates)
            template.title: template.children.toSet(),
        };

        return StatefulBuilder(
          builder: (context, setModalState) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: ListView(
              shrinkWrap: true,
              children: [
                const Text(
                  'Pastas pré-nomeadas',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Expanda uma estrutura para revisar a descrição completa, manter todas as subpastas sugeridas ou desligar apenas as que não fazem sentido para a sua organização antes da criação.',
                ),
                const SizedBox(height: 14),
                for (final template in templates)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PresetFolderTemplateExpander(
                      template: template,
                      selectedChildren:
                          selectedChildren[template.title] ?? <String>{},
                      onToggleAll: (enabled) {
                        setModalState(() {
                          selectedChildren[template.title] = enabled
                              ? template.children.toSet()
                              : <String>{};
                        });
                      },
                      onToggleChild: (child, enabled) {
                        setModalState(() {
                          final current =
                              selectedChildren[template.title] ?? <String>{};
                          if (enabled) {
                            current.add(child);
                          } else {
                            current.remove(child);
                          }
                          selectedChildren[template.title] = current;
                        });
                      },
                      onCreate: () {
                        final current =
                            selectedChildren[template.title] ?? <String>{};
                        Navigator.of(context).pop(
                          _PresetFolderSelection(
                            template: template,
                            selectedChildren: template.children
                                .where(current.contains)
                                .toList(),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null) return;
    final repo = ref.read(pdfRepositoryProvider);
    final duplicateResolution = await _resolveFolderDuplicate(name: selected.template.title, parentId: _selectedFolderId);
    if (duplicateResolution == null) {
      _showElegantToast(icon: Icons.info_outline_rounded, message: 'A estrutura original foi mantida. Nenhuma pasta padrão foi criada.');
      return;
    }
    await repo.addOperationLog(
      action: 'Criação de pasta padrão',
      title: duplicateResolution['name'] as String,
      detail: 'Estrutura padrão criada com ${selected.selectedChildren.length} subpasta(s).',
    );
    final replaceFolderId = duplicateResolution['replaceFolderId'] as String?;
    if (replaceFolderId != null) await repo.deleteFolder(replaceFolderId);
    final root = await repo.createFolder(
      name: duplicateResolution['name'] as String,
      parentId: _selectedFolderId,
    );
    await repo.updateFolderColor(
      folderId: root.id,
      colorValue: selected.template.colorValue,
    );
    for (final child in selected.selectedChildren) {
      final created = await repo.createFolder(name: child, parentId: root.id);
      await repo.updateFolderColor(
        folderId: created.id,
        colorValue: selected.template.colorValue,
      );
    }
    await _refreshFolders();
    if (mounted) {
      setState(() {
        _selectedFolderId = root.id;
        _showFoldersPanel = true;
      });
    }
    await _checkLogCacheHealth();
    _showElegantToast(
      icon: Icons.auto_awesome_rounded,
      message:
          'Estrutura "${root.name}" criada com ${selected.selectedChildren.length} subpasta(s).',
    );
  }

  Future<void> _createFolder(
      [List<PdfDocument> availableDocuments = const <PdfDocument>[]]) async {
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
        String selectedParentId = _selectedFolderId;
        final selectedFiles = <String>{};

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Nova pasta'),
                ),
                body: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 980;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1280),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [
                                    Color(0xFFEAF4FF),
                                    Color(0xFFF7FBFF)
                                  ]),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                      color: const Color(0xFFB8D9FF)),
                                  boxShadow: [
                                    BoxShadow(
                                        color: selectedColor.withOpacity(0.08),
                                        blurRadius: 14,
                                        offset: const Offset(0, 6))
                                  ],
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(colors: [
                                          selectedColor,
                                          selectedColor.withOpacity(0.72)
                                        ]),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: const Icon(
                                          Icons.create_new_folder_rounded,
                                          color: Colors.white,
                                          size: 24),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('Criar pasta inteligente',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w900)),
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
                                        _TinyPill(
                                            icon: Icons.palette_outlined,
                                            label: 'Cor'),
                                        _TinyPill(
                                            icon: Icons.picture_as_pdf_rounded,
                                            label: 'PDFs'),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              _FolderParentSelector(
                                folders: _folders,
                                selectedParentId: selectedParentId,
                                onChanged: (value) => setModalState(() => selectedParentId = value),
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      Navigator.of(context).pop();
                                      await Future<void>.delayed(const Duration(milliseconds: 120));
                                      await _createPresetFolderTemplates();
                                    },
                                    icon: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF6A1B9A)),
                                    label: const Text('Criar pastas padrão'),
                                  ),
                                  const Text('Use este atalho para montar estruturas prontas de documentos pessoais, acadêmicos e normativos.'),
                                ],
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
                                        onColorChanged: (color) =>
                                            setModalState(
                                                () => selectedColor = color),
                                      ),
                                    ),
                                    const SizedBox(width: 18),
                                    Expanded(
                                      flex: 7,
                                      child: _FolderDocumentsSection(
                                        availableDocuments: availableDocuments,
                                        folders: _folders,
                                        selectedFiles: selectedFiles,
                                        currentFolderId: _selectedFolderId,
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
                                  onColorChanged: (color) => setModalState(
                                      () => selectedColor = color),
                                ),
                                const SizedBox(height: 18),
                                _FolderDocumentsSection(
                                  availableDocuments: availableDocuments,
                                  folders: _folders,
                                  selectedFiles: selectedFiles,
                                  currentFolderId: _selectedFolderId,
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
                bottomNavigationBar: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      onPressed: () {
                        final cleaned = nameController.text.trim();
                        if (cleaned.isEmpty) return;
                        Navigator.of(context).pop(<String, dynamic>{
                          'name': cleaned,
                          'colorValue': selectedColor.value,
                          'parentId': selectedParentId,
                          'selectedFiles': selectedFiles.toList(),
                        });
                      },
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: const Text('Criar pasta'),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (result == null) return;
    final repo = ref.read(pdfRepositoryProvider);
    final requestedName = result['name'] as String;
    final parentId = result['parentId'] as String? ?? _selectedFolderId;
    final duplicateResolution = await _resolveFolderDuplicate(name: requestedName, parentId: parentId);
    if (duplicateResolution == null) {
      _showElegantToast(icon: Icons.info_outline_rounded, message: 'A pasta original foi mantida. Nenhuma nova pasta foi criada.');
      return;
    }
    final replaceFolderId = duplicateResolution['replaceFolderId'] as String?;
    await repo.addOperationLog(
      action: 'Criação de pasta',
      title: 'Nova pasta',
      detail: replaceFolderId == null
          ? 'Criação da pasta "${duplicateResolution['name']}".'
          : 'Substituição da pasta existente por "${duplicateResolution['name']}".',
    );
    if (replaceFolderId != null) await repo.deleteFolder(replaceFolderId);
    final folder = await repo.createFolder(
        name: duplicateResolution['name'] as String,
        parentId: parentId);
    await repo.updateFolderColor(
        folderId: folder.id, colorValue: result['colorValue'] as int);
    final selectedFiles =
        (result['selectedFiles'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => e.toString())
            .toList();
    for (final file in selectedFiles) {
      await repo.toggleDocumentInFolder(folderId: folder.id, documentFile: file);
    }
    await _refreshFolders();
    await ref.read(pdfViewModelProvider.notifier).reload();
    if (mounted) {
      setState(() {
        _selectedFolderId = folder.id;
        _showFoldersPanel = false;
      });
    }
    await _checkLogCacheHealth();
    _showElegantToast(
        icon: Icons.create_new_folder_rounded,
        message: 'Pasta "${folder.name}" criada com sucesso.');
  }

  Future<void> _renameFolder(PdfFolder folder) async {
    if (folder.id == 'root') {
      _showElegantToast(
          icon: Icons.info_outline_rounded,
          message: 'A pasta Documentos é fixa.');
      return;
    }
    final name = await _askFolderName(
        title: 'Renomear pasta', initialValue: folder.name);
    if (name == null) return;
    await ref.read(pdfRepositoryProvider).addOperationLog(
      action: 'Renomear pasta',
      title: folder.name,
      detail: 'Pasta renomeada para "$name".' ,
    );
    await ref
        .read(pdfRepositoryProvider)
        .renameFolder(folderId: folder.id, name: name);
    await _refreshFolders();
    _showElegantToast(
        icon: Icons.drive_file_rename_outline_rounded,
        message: 'Pasta renomeada.');
  }

  Future<void> _renameFolderCategory(PdfFolder folder) async {
    if (folder.id == 'root' || folder.parentId != 'root') return;
    final controller = TextEditingController(
      text: (folder.categoryName?.trim().isNotEmpty ?? false)
          ? folder.categoryName!.trim()
          : folder.name,
    );
    final color = Color(folder.colorValue);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.folder_copy_rounded, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Renomear categoria'),
                  const SizedBox(height: 4),
                  Text(
                    'Categoria atual: ${_categoryLabelForFolder(folder)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF607D8B),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withOpacity(0.18)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ao renomear a categoria, apenas o título do expander principal será alterado. O nome da pasta "${folder.name}" continuará independente, assim como as subpastas e os PDFs já vinculados.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          height: 1.4,
                          color: const Color(0xFF355C7D),
                        ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _TinyPill(
                        icon: Icons.label_outline_rounded,
                        label: 'Só muda o expander',
                      ),
                      _TinyPill(
                        icon: Icons.folder_open_rounded,
                        label: 'Pastas preservadas',
                      ),
                      _TinyPill(
                        icon: Icons.picture_as_pdf_rounded,
                        label: 'PDFs permanecem',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      _InfoBadge(
                        badge: _InfoBadgeData(
                          label: 'Sem mover arquivos',
                          icon: Icons.drive_file_move_rounded,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                      _InfoBadge(
                        badge: _InfoBadgeData(
                          label: 'Sem excluir vínculos',
                          icon: Icons.link_rounded,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Novo título da categoria',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.edit_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(controller.text),
            icon: const Icon(Icons.check_circle_outline_rounded),
            label: const Text('Salvar categoria'),
          ),
        ],
      ),
    );
    controller.dispose();
    final cleaned = value?.trim();
    if (cleaned == null || cleaned.isEmpty) return;
    await ref.read(pdfRepositoryProvider).renameFolderCategory(
          folderId: folder.id,
          categoryName: cleaned,
        );
    await _refreshFolders();
    if (!mounted) return;
    _showElegantToast(
      icon: Icons.label_rounded,
      message: 'Categoria renomeada para "$cleaned".',
    );
  }

  Future<void> _deleteFolder(PdfFolder folder) async {
    if (folder.id == 'root') {
      _showElegantToast(
          icon: Icons.info_outline_rounded,
          message: 'A pasta Documentos é fixa.');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
        contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFD32F2F), Color(0xFFFF7043)]),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(color: const Color(0xFFD32F2F).withOpacity(0.20), blurRadius: 18, offset: const Offset(0, 8)),
                ],
              ),
              child: const Icon(Icons.folder_delete_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Excluir pasta "${folder.name}"?'),
                  const SizedBox(height: 6),
                  Text(
                    'A exclusão remove a pasta e os vínculos, mas preserva os PDFs na biblioteca.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF607D8B), height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Container(
          width: 540,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFFFF4F4), Color(0xFFFFFBFB)]),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFFFCDD2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(folder.name, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF7F1D1D))),
              const SizedBox(height: 10),
              const Text(
                'A pasta será removida da hierarquia. Os documentos continuam salvos na biblioteca principal e poderão ser movidos novamente para outra pasta. Após confirmar, o Folhear exibirá um aviso com contador de 3 segundos e botão para desfazer.',
                style: TextStyle(color: Color(0xFF3F3F46), height: 1.45),
              ),
              const SizedBox(height: 12),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoBadge(badge: _InfoBadgeData(label: 'Desfazer disponível', icon: Icons.undo_rounded, color: Color(0xFF1565C0))),
                  _InfoBadge(badge: _InfoBadgeData(label: 'PDFs preservados', icon: Icons.picture_as_pdf_rounded, color: Color(0xFF2E7D32))),
                  _InfoBadge(badge: _InfoBadgeData(label: 'Remove vínculos', icon: Icons.link_off_rounded, color: Color(0xFFD32F2F))),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.close_rounded),
            label: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.folder_delete_rounded),
            label: const Text('Excluir pasta'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final logId = await ref.read(pdfRepositoryProvider).addOperationLog(
      action: 'Exclusão de pasta',
      title: folder.name,
      detail: 'Pasta removida. Os PDFs não foram apagados, apenas os vínculos e a estrutura da pasta foram alterados.',
    );
    await ref.read(pdfRepositoryProvider).deleteFolder(folder.id);
    setState(() => _selectedFolderId = 'root');
    await _refreshFolders();
    _showUndoToast(
        icon: Icons.folder_delete_rounded,
        message: 'Pasta excluída.',
        actionLabel: 'Desfazer',
        onUndo: () async => _restoreOperationAndRefresh(logId));
  }

  Future<void> _changeFolderColor(PdfFolder folder) async {
    final colors = <Color>[
      const Color(0xFF0B5CAD),
      const Color(0xFF00A2C7),
      const Color(0xFF2E7D32),
      const Color(0xFFF9A825),
      const Color(0xFFC62828),
      const Color(0xFF6A1B9A)
    ];
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
                child: CircleAvatar(
                    backgroundColor: color,
                    child: folder.colorValue == color.value
                        ? const Icon(Icons.check, color: Colors.white)
                        : null),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await ref
        .read(pdfRepositoryProvider)
        .updateFolderColor(folderId: folder.id, colorValue: selected.value);
    await _refreshFolders();
  }

  Future<void> _importPdfsFromDevice() async {
    final repo = ref.read(pdfRepositoryProvider);
    final targetFolder = _findFolderById(_selectedFolderId);
    final targetIsFolder = targetFolder != null && targetFolder.id != 'root';
    final beforeDocuments = ref.read(pdfViewModelProvider).value?.documents ?? const <PdfDocument>[];
    final logId = await repo.addOperationLog(
      action: 'Importação de PDF',
      title: targetIsFolder ? 'Importação em pasta' : 'Importação em Documentos',
      detail: targetIsFolder
          ? 'Estado anterior salvo antes de importar arquivos diretamente para a pasta "${targetFolder.name}".'
          : 'Estado anterior salvo antes de importar arquivos para a categoria principal Documentos.',
    );
    final imported = await repo.importPdfsFromDevice();

    if (imported.isNotEmpty && targetIsFolder) {
      for (final document in imported) {
        await repo.moveDocumentToFolder(
          folderId: targetFolder.id,
          documentFile: document.file,
        );
      }
    }
    await _resolveImportedDuplicates(imported: imported, previousDocuments: beforeDocuments);

    await ref.read(pdfViewModelProvider.notifier).reload();
    await _refreshFolders();
    if (!mounted) return;

    if (imported.isEmpty) {
      _showElegantToast(
        icon: Icons.info_outline_rounded,
        message: targetIsFolder
            ? 'Nenhum PDF foi importado para "${targetFolder.name}".'
            : 'Nenhum PDF foi importado.',
      );
      return;
    }

    if (targetIsFolder) {
      setState(() {
        _selectedFolderId = targetFolder.id;
        _selectedIndex = 0;
        _showFoldersPanel = true;
      });
    }

    await _checkLogCacheHealth();
    _showUndoToast(
      icon: Icons.upload_file_rounded,
      message: targetIsFolder
          ? '${imported.length} PDF(s) importado(s) diretamente para "${targetFolder.name}".'
          : '${imported.length} PDF(s) importado(s) com sucesso em Documentos.',
      actionLabel: 'Desfazer',
      onUndo: () async => _restoreOperationAndRefresh(logId),
    );
  }

  void _openFoldersBrowserSheet(List<PdfDocument> documents) {
    if (!mounted) return;
    setState(() {
      _showFoldersPanel = true;
      _selectedIndex = 2;
    });
  }

  List<Widget> _buildFolderCategorySlivers(BuildContext context, bool isMobile) {
    final categories = _folders
        .where((folder) => folder.id != 'root' && folder.parentId == 'root')
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (categories.isEmpty) {
      return [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(isMobile ? 14 : 24, 0, isMobile ? 14 : 24, 124),
          sliver: SliverToBoxAdapter(
            child: _RichEmptyState(
              icon: Icons.folder_copy_outlined,
            title: 'Nenhuma categoria criada',
            subtitle:
                'Crie uma pasta para começar a organizar a biblioteca em categorias principais e subpastas.',
            pills: const [
              'Criação rápida',
              'Hierarquia simples',
              'Organização visual',
            ],
            badges: const [
              _InfoBadgeData(
                label: 'Pastas personalizadas',
                icon: Icons.create_new_folder_rounded,
                color: Color(0xFF1565C0),
              ),
              _InfoBadgeData(
                label: 'Cores por contexto',
                icon: Icons.palette_outlined,
                color: Color(0xFF6A1B9A),
              ),
              _InfoBadgeData(
                label: 'Vínculo com PDFs',
                icon: Icons.picture_as_pdf_rounded,
                color: Color(0xFF2E7D32),
              ),
            ],
              details: const [
                'Use o botão "Criar pasta" para adicionar a primeira categoria da biblioteca.',
                'Cada categoria pode receber subpastas e documentos vinculados para facilitar a consulta.',
              ],
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding:
            EdgeInsets.fromLTRB(isMobile ? 14 : 24, 0, isMobile ? 14 : 24, 124),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final folder = categories[index];
              return Padding(
                padding: EdgeInsets.only(bottom: index == categories.length - 1 ? 0 : 12),
                child: _FolderCategoryExpander(
                  folder: folder,
                  folders: _folders,
                  selectedFolderId: _selectedFolderId,
                  onSelect: (selectedFolder) {
                    setState(() {
                      _selectedFolderId = selectedFolder.id;
                      _selectedIndex = 0;
                      _showFoldersPanel = true;
                    });
                  },
                  onOptions: _openFolderOptionsSheet,
                  onMove: _openMoveFolderSheet,
                ),
              );
            },
            childCount: categories.length,
          ),
        ),
      ),
    ];
  }


  Future<void> _openMoveFolderSheet(PdfFolder folder) async {
    if (folder.id == 'root') return;
    final candidates = _folders
        .where((item) => item.id != folder.id)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: ListView(
          shrinkWrap: true,
          children: [
            _MoreOptionCard(
              icon: Icons.drive_file_move_rounded,
              iconColor: const Color(0xFF1565C0),
              backgroundColor: const Color(0xFFEAF4FF),
              title: 'Mover pasta',
              subtitle: 'Escolha uma pasta de destino para colocar "${folder.name}" dentro dela ou envie de volta para a raiz da biblioteca.',
              onTap: () {},
            ),
            _QuickActionTile(
              icon: Icons.home_filled,
              iconColor: const Color(0xFF455A64),
              backgroundColor: const Color(0xFFF4F7FA),
              title: 'Mover para a raiz',
              subtitle: 'Remove o vínculo com a pasta atual e deixa esta pasta diretamente na biblioteca principal.',
              onTap: () async {
                Navigator.of(context).pop();
                await ref.read(pdfRepositoryProvider).moveFolderToParent(folderId: folder.id, newParentId: 'root');
                await _refreshFolders();
              },
            ),
            for (final target in candidates)
              _QuickActionTile(
                icon: Icons.folder_rounded,
                iconColor: Color(target.colorValue),
                backgroundColor: Color(target.colorValue).withOpacity(0.08),
                title: target.name,
                subtitle: 'Mover "${folder.name}" para dentro desta pasta.',
                onTap: () async {
                  Navigator.of(context).pop();
                  await ref.read(pdfRepositoryProvider).moveFolderToParent(folderId: folder.id, newParentId: target.id);
                  await _refreshFolders();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFolderOptionsSheet(PdfFolder folder) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: ListView(
          shrinkWrap: true,
          children: [
            _MoreOptionCard(
              icon: folder.id == 'root'
                  ? Icons.folder_special_rounded
                  : Icons.folder_rounded,
              iconColor: Color(folder.colorValue),
              backgroundColor: Color(folder.colorValue).withOpacity(0.10),
              title: folder.name,
              subtitle: folder.id == 'root'
                  ? 'Pasta principal da biblioteca.'
                  : 'Gerencie nome, cor, posição e documentos vinculados desta pasta.',
              onTap: () {},
            ),
            _QuickActionTile(
              icon: Icons.visibility_rounded,
              iconColor: const Color(0xFF1565C0),
              backgroundColor: const Color(0xFFEAF4FF),
              title: 'Abrir pasta',
              subtitle: 'Seleciona esta pasta e volta para a biblioteca filtrada.',
              onTap: () {
                Navigator.of(context).pop();
                setState(() {
                  _selectedFolderId = folder.id;
                  _selectedIndex = 0;
                  _showFoldersPanel = true;
                });
              },
            ),
            if (folder.id != 'root')
              _QuickActionTile(
                icon: Icons.upload_file_rounded,
                iconColor: const Color(0xFF2E7D32),
                backgroundColor: const Color(0xFFEAF7EC),
                title: 'Importar PDFs para esta pasta',
                subtitle:
                    'Busca arquivos no dispositivo e já vincula os novos PDFs diretamente a "${folder.name}".',
                onTap: () async {
                  Navigator.of(context).pop();
                  await _importPdfsToFolder(folder);
                },
              ),
            if (folder.id != 'root' && folder.parentId == 'root')
              _QuickActionTile(
                icon: Icons.label_rounded,
                iconColor: const Color(0xFF5E35B1),
                backgroundColor: const Color(0xFFF3EAFE),
                title: 'Renomear categoria',
                subtitle:
                    'Altera apenas o título do expander da categoria, sem renomear a pasta principal nem as subpastas.',
                onTap: () async {
                  Navigator.of(context).pop();
                  await _renameFolderCategory(folder);
                },
              ),
            if (folder.id != 'root')
              _QuickActionTile(
                icon: Icons.drive_file_rename_outline_rounded,
                iconColor: const Color(0xFF00838F),
                backgroundColor: const Color(0xFFE7F7F8),
                title: 'Renomear pasta',
                subtitle: 'Altere o nome exibido para esta pasta.',
                onTap: () async {
                  Navigator.of(context).pop();
                  await _renameFolder(folder);
                },
              ),
            if (folder.id != 'root')
              _QuickActionTile(
                icon: Icons.palette_outlined,
                iconColor: const Color(0xFF6A1B9A),
                backgroundColor: const Color(0xFFF3EAFE),
                title: 'Trocar cor',
                subtitle: 'Defina uma nova cor para facilitar a identificação visual.',
                onTap: () async {
                  Navigator.of(context).pop();
                  await _changeFolderColor(folder);
                },
              ),
            if (folder.id != 'root')
              _QuickActionTile(
                icon: Icons.drive_file_move_rounded,
                iconColor: const Color(0xFFEF6C00),
                backgroundColor: const Color(0xFFFFF1E6),
                title: 'Mover pasta',
                subtitle: 'Escolha outra pasta de destino ou leve de volta para a raiz.',
                onTap: () async {
                  Navigator.of(context).pop();
                  await _openMoveFolderSheet(folder);
                },
              ),
            if (folder.id != 'root')
              _QuickActionTile(
                icon: Icons.delete_outline_rounded,
                iconColor: const Color(0xFFC62828),
                backgroundColor: const Color(0xFFFFEBEE),
                title: 'Excluir pasta',
                subtitle: 'Remove a pasta e os vínculos sem apagar os PDFs da biblioteca.',
                onTap: () async {
                  Navigator.of(context).pop();
                  await _deleteFolder(folder);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDocumentMoveSheet(PdfDocument document) async {
    final folders = _folders.where((folder) => folder.id != 'root').toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final repo = ref.read(pdfRepositoryProvider);

    if (folders.isEmpty) {
      _showElegantToast(
        icon: Icons.folder_off_rounded,
        message: 'Crie uma pasta antes de mover este PDF.',
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: ListView(
          shrinkWrap: true,
          children: [
            _MoreOptionCard(
              icon: Icons.drive_file_move_rounded,
              iconColor: const Color(0xFF1565C0),
              backgroundColor: const Color(0xFFEAF4FF),
              title: 'Mover PDF para pasta',
              subtitle: 'Escolha a pasta de destino para "${document.title}". A ação fica disponível para desfazer no toast e no histórico.',
              onTap: () {},
            ),
            const SizedBox(height: 8),
            for (final folder in folders)
              _QuickActionTile(
                icon: Icons.folder_rounded,
                iconColor: Color(folder.colorValue),
                backgroundColor: Color(folder.colorValue).withOpacity(0.08),
                title: folder.name,
                subtitle: folder.parentId == 'root'
                    ? 'Categoria principal'
                    : 'Subpasta vinculada a outra categoria',
                onTap: () async {
                  Navigator.of(context).pop();
                  final logId = await repo.addOperationLog(
                    action: 'Mover PDF',
                    title: document.title,
                    detail: 'PDF movido para a pasta "${folder.name}".',
                  );
                  await repo.moveDocumentToFolder(
                    folderId: folder.id,
                    documentFile: document.file,
                  );
                  await _refreshFolders();
                  await ref.read(pdfViewModelProvider.notifier).reload();
                  if (!mounted) return;
                  setState(() {
                    _selectedFolderId = folder.id;
                    _showFoldersPanel = false;
                  });
                  _showUndoToast(
                    icon: Icons.drive_file_move_rounded,
                    message: 'PDF movido para "${folder.name}".',
                    onUndo: () async => _restoreOperationAndRefresh(logId),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDocumentOptionsSheet(PdfDocument document) async {
    final folders = _folders.where((folder) => folder.id != 'root').toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final repo = ref.read(pdfRepositoryProvider);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: ListView(
          shrinkWrap: true,
          children: [
            _MoreOptionCard(
              icon: Icons.picture_as_pdf_rounded,
              iconColor: const Color(0xFFD32F2F),
              backgroundColor: const Color(0xFFFFF4F4),
              title: document.title,
              subtitle: '${document.pageCount} página(s) • ${document.version}',
              onTap: () {},
            ),
            _QuickActionTile(
              icon: Icons.open_in_new_rounded,
              iconColor: const Color(0xFF1565C0),
              backgroundColor: const Color(0xFFEAF4FF),
              title: 'Abrir PDF',
              subtitle: 'Abre o documento no visualizador.',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(this.context).push(
                  MaterialPageRoute(
                    builder: (_) => PdfViewerPage(document: document),
                  ),
                );
              },
            ),
            _QuickActionTile(
              icon: document.isFavorite
                  ? Icons.star_border_rounded
                  : Icons.star_rounded,
              iconColor: const Color(0xFFFFA000),
              backgroundColor: const Color(0xFFFFF4DB),
              title: document.isFavorite
                  ? 'Remover dos favoritos'
                  : 'Adicionar aos favoritos',
              subtitle: 'Alterna o destaque deste documento na biblioteca.',
              onTap: () async {
                Navigator.of(context).pop();
                await _toggleDocumentFavorite(document);
              },
            ),
            if (folders.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Mover para pasta',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const SizedBox(height: 8),
              for (final folder in folders)
                _QuickActionTile(
                  icon: Icons.folder_rounded,
                  iconColor: Color(folder.colorValue),
                  backgroundColor:
                      Color(folder.colorValue).withOpacity(0.08),
                  title: folder.name,
                  subtitle: 'Envia este PDF para esta pasta e remove dos demais vínculos.',
                  onTap: () async {
                    Navigator.of(context).pop();
                    final logId = await repo.addOperationLog(
                      action: 'Mover PDF',
                      title: document.title,
                      detail: 'PDF movido para a pasta "${folder.name}".',
                    );
                    await repo.moveDocumentToFolder(
                      folderId: folder.id,
                      documentFile: document.file,
                    );
                    await _refreshFolders();
                    await ref.read(pdfViewModelProvider.notifier).reload();
                    if (!mounted) return;
                    setState(() {
                      _selectedFolderId = folder.id;
                      _showFoldersPanel = false;
                    });
                    _showUndoToast(
                      icon: Icons.drive_file_move_rounded,
                      message: 'PDF movido para "${folder.name}".',
                      onUndo: () async => _restoreOperationAndRefresh(logId),
                    );
                  },
                ),
            ],
            _QuickActionTile(
              icon: Icons.delete_outline_rounded,
              iconColor: const Color(0xFFC62828),
              backgroundColor: const Color(0xFFFFEBEE),
              title: 'Excluir da biblioteca',
              subtitle: 'Remove este PDF da biblioteca com opção de desfazer.',
              onTap: () async {
                Navigator.of(context).pop();
                final confirm = await _confirmDeleteDocument(document);
                if (confirm) {
                  await _deleteDocumentWithUndo(document);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openQuickActions() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        final docs = ref.read(pdfViewModelProvider).value?.documents ?? const <PdfDocument>[];
        final activeFolder = _findFolderById(_selectedFolderId);
        final hasActiveFolder = activeFolder != null && activeFolder.id != 'root';
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _QuickActionTile(
                icon: Icons.create_new_folder_rounded,
                iconColor: const Color(0xFF1565C0),
                backgroundColor: const Color(0xFFEAF4FF),
                title: hasActiveFolder ? 'Criar subpasta aqui' : 'Criar pasta de organização',
                subtitle: hasActiveFolder
                    ? 'Crie uma subpasta dentro de "${activeFolder.name}" para manter a hierarquia da categoria sem sair do contexto atual.'
                    : 'Crie uma nova pasta personalizada para organizar documentos por matéria, cliente, assunto, projeto ou qualquer categoria que faça sentido para a sua rotina.',
                onTap: () {
                  Navigator.of(context).pop();
                  Future<void>.delayed(const Duration(milliseconds: 120), () => _createFolder(docs));
                },
              ),
              _QuickActionTile(
                icon: Icons.file_upload_outlined,
                iconColor: const Color(0xFF2E7D32),
                backgroundColor: const Color(0xFFEAF7EC),
                title: hasActiveFolder ? 'Importar nesta pasta' : 'Importar PDFs em Documentos',
                subtitle: hasActiveFolder
                    ? 'Selecione PDFs e vincule automaticamente os arquivos à pasta aberta: "${activeFolder.name}".'
                    : 'Selecione um ou vários arquivos PDF do armazenamento do aparelho ou computador para adicioná-los imediatamente à biblioteca local do Folhear.',
                onTap: () {
                  Navigator.of(context).pop();
                  Future<void>.delayed(
                    const Duration(milliseconds: 120),
                    hasActiveFolder ? () => _importPdfsToFolder(activeFolder) : _importPdfsFromDevice,
                  );
                },
              ),
              _QuickActionTile(
                icon: Icons.search_rounded,
                iconColor: const Color(0xFF6A1B9A),
                backgroundColor: const Color(0xFFF3EAFE),
                title: 'Pesquisar na biblioteca',
                subtitle: 'Abra a busca para localizar PDFs pelo nome e acessar mais rápido o conteúdo que você precisa revisar, consultar ou editar.',
                onTap: () {
                  Navigator.of(context).pop();
                  Future<void>.delayed(const Duration(milliseconds: 120), _openSearch);
                },
              ),
              _QuickActionTile(
                icon: Icons.star_rounded,
                iconColor: const Color(0xFFFFA000),
                backgroundColor: const Color(0xFFFFF4DB),
                title: 'Abrir favoritos',
                subtitle: 'Mostra documentos e páginas marcados com estrela, sem duplicar as opções administrativas do menu Mais.',
                onTap: () {
                  Navigator.of(context).pop();
                  _onNavTap(1);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _onNavTap(int index) {
    if (_searchOpen) _closeSearch();
    setState(() => _selectedIndex = index);

    final state = ref.read(pdfViewModelProvider).value;
    if (index == 1) {
      if (state != null && !state.showOnlyFavorites) {
        ref.read(pdfViewModelProvider.notifier).toggleFavoriteFilter();
      }
      return;
    }

    if (index == 0 || index == 2) {
      if (state != null && state.showOnlyFavorites) {
        ref.read(pdfViewModelProvider.notifier).toggleFavoriteFilter();
      }
      if (index == 2) {
        Future<void>.microtask(() {
          final currentState = ref.read(pdfViewModelProvider).value;
          _openFoldersBrowserSheet(currentState?.documents ?? const <PdfDocument>[]);
        });
      }
      return;
    }

    _openMoreSheet();
  }

  Future<void> _openResetDialog(List<PdfDocument> documents) async {
    final keepDocs = documents.map((doc) => doc.file).toSet();
    final keepFolders =
        _folders.map((folder) => folder.id).where((id) => id != 'root').toSet();
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
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'O reset remove favoritos, páginas salvas, post-its, marcações locais e preferências. Abaixo você escolhe quais PDFs e pastas quer manter visíveis depois do reset.'),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => setDialogState(() {
                            selectedDocs
                              ..clear()
                              ..addAll(keepDocs);
                            selectedFolders
                              ..clear()
                              ..addAll(keepFolders);
                          }),
                          icon: const Icon(Icons.select_all_rounded),
                          label: const Text('Marcar tudo'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => setDialogState(() {
                            selectedDocs.clear();
                            selectedFolders.clear();
                          }),
                          icon: const Icon(Icons.deselect_rounded),
                          label: const Text('Desmarcar tudo'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView(shrinkWrap: true, children: [
                        Text('PDFs a manter',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900)),
                        for (final doc in documents)
                          SwitchListTile(
                            dense: true,
                            value: selectedDocs.contains(doc.file),
                            title: Text(doc.title),
                            subtitle: Text(doc.file,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            onChanged: (value) => setDialogState(() {
                              value
                                  ? selectedDocs.add(doc.file)
                                  : selectedDocs.remove(doc.file);
                            }),
                          ),
                        const Divider(),
                        Text('Pastas a manter',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900)),
                        for (final folder
                            in _folders.where((folder) => folder.id != 'root'))
                          SwitchListTile(
                            dense: true,
                            value: selectedFolders.contains(folder.id),
                            secondary: Icon(Icons.folder_rounded,
                                color: Color(folder.colorValue)),
                            title: Text(folder.name),
                            onChanged: (value) => setDialogState(() {
                              value
                                  ? selectedFolders.add(folder.id)
                                  : selectedFolders.remove(folder.id);
                            }),
                          ),
                      ]),
                    ),
                  ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar')),
              FilledButton.icon(
                  onPressed: () => Navigator.of(context)
                          .pop(<String, Set<String>>{
                        'docs': selectedDocs,
                        'folders': selectedFolders
                      }),
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Resetar')),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    final logId = await ref.read(pdfRepositoryProvider).addOperationLog(
      action: 'Reset de configurações',
      title: 'Manutenção local',
      detail: 'Configurações redefinidas com seleção de documentos e pastas preservadas.',
    );
    await ref.read(pdfRepositoryProvider).resetApplicationSettings(
        keepDocumentFiles: result['docs'], keepFolderIds: result['folders']);
    await _refreshFolders();
    await ref.read(pdfViewModelProvider.notifier).reload();
    if (!mounted) return;
    _showUndoToast(
        icon: Icons.restart_alt_rounded,
        message: 'Configurações resetadas.',
        actionLabel: 'Desfazer',
        onUndo: () async => _restoreOperationAndRefresh(logId));
  }

  void _openAboutPage() {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(title: const Text('Sobre o Folhear'), actions: [
            IconButton(
                tooltip: 'Fechar',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded))
          ]),
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
                        decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [Color(0xFFEAF4FF), Color(0xFFF8FBFF)]),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: const Color(0xFFB8D9FF))),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                  width: 64,
                                  height: 64,
                                  decoration: const BoxDecoration(
                                      gradient: LinearGradient(colors: [
                                        Color(0xFF0B5CAD),
                                        Color(0xFF2EA7FF)
                                      ]),
                                      borderRadius: BorderRadius.all(
                                          Radius.circular(22))),
                                  child: const Icon(
                                      Icons.picture_as_pdf_rounded,
                                      color: Colors.white,
                                      size: 34)),
                              const SizedBox(width: 16),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text('${AppInfo.name} ${AppInfo.badge}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w900)),
                                    const SizedBox(height: 8),
                                    const Text(
                                        'Biblioteca inteligente para leitura, consulta e organização de documentos PDF, criada para transformar arquivos soltos em uma experiência prática, visual e acessível.'),
                                    const SizedBox(height: 12),
                                    Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: const [
                                          _TinyPill(
                                              icon: Icons.folder_copy_rounded,
                                              label: 'Pastas'),
                                          _TinyPill(
                                              icon: Icons.star_rounded,
                                              label: 'Favoritos'),
                                          _TinyPill(
                                              icon: Icons.sticky_note_2_rounded,
                                              label: 'Post-its'),
                                          _TinyPill(
                                              icon: Icons.search_rounded,
                                              label: 'Busca'),
                                          _TinyPill(
                                              icon: Icons.upload_file_rounded,
                                              label: 'Importação local'),
                                        ]),
                                  ])),
                            ]),
                      ),
                      const SizedBox(height: 18),
                      _AboutSection(
                          icon: Icons.account_circle_outlined,
                          color: Color(0xFF1565C0),
                          title: 'Desenvolvedor da aplicação',
                          paragraphs: const [
                            'Eu, Hagliberto Alves de Oliveira, desenvolvi o Folhear para facilitar minha rotina de consulta, leitura e organização de documentos em PDF. A proposta nasceu da necessidade de reunir materiais importantes em uma biblioteca simples, visual e prática, evitando que arquivos relevantes fiquem espalhados em pastas do computador, downloads do celular ou locais difíceis de localizar rapidamente.',
                            'O aplicativo foi pensado para uso cotidiano, especialmente em cenários de estudo, trabalho, análise documental e consulta recorrente. A ideia é permitir que o usuário importe seus próprios PDFs, organize por pastas, marque documentos favoritos, salve páginas relevantes e registre observações em post-its, mantendo uma experiência leve e direta.',
                          ]),
                      const SizedBox(height: 14),
                      _AboutSection(
                          icon: Icons.auto_awesome_rounded,
                          color: Color(0xFF2E7D32),
                          title: 'Propósito do Folhear',
                          paragraphs: const [
                            'O Folhear não é apenas um visualizador de PDF. Ele funciona como uma biblioteca pessoal inteligente, voltada para leitura orientada e organização progressiva. O usuário começa importando arquivos, depois pode separá-los em pastas, destacar documentos importantes, salvar páginas específicas e criar anotações conforme a leitura evolui.',
                            'A aplicação busca reduzir o tempo gasto procurando documentos e aumentar a produtividade em consultas rápidas. Em vez de depender apenas do nome do arquivo ou da pasta original, o usuário passa a construir uma camada própria de organização, com favoritos, post-its, páginas salvas e agrupamentos personalizados.',
                          ]),
                      const SizedBox(height: 14),
                      _AboutSection(
                          icon: Icons.new_releases_outlined,
                          color: Color(0xFFFFA000),
                          title: 'Versão da aplicação',
                          paragraphs: const [
                            '${AppInfo.name} ${AppInfo.version}',
                            'Atualizada em ${AppInfo.versionDate}.',
                            'Notas da versão: ${AppInfo.releaseNote}.',
                            'Esta versão revisa a experiência das telas principais, adiciona botão Desfazer aos toasts com contador regressivo, transforma pills informativos em atalhos clicáveis, diferencia o botão + do menu Mais e deixa os cards da página Sobre mais coloridos e destacados.',
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


  String _formatOperationDate(String raw) {
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return raw;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
  }

  Color _operationColor(String action) {
    final lower = action.toLowerCase();
    if (lower.contains('exclus')) return const Color(0xFFD32F2F);
    if (lower.contains('cria')) return const Color(0xFF2E7D32);
    if (lower.contains('mov')) return const Color(0xFF1565C0);
    if (lower.contains('import')) return const Color(0xFF6A1B9A);
    if (lower.contains('duplic')) return const Color(0xFFFF8F00);
    return const Color(0xFF455A64);
  }

  void _openOperationLogPage() {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Histórico e desfazer'),
            actions: [
              IconButton(
                tooltip: 'Fechar',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          body: SafeArea(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: ref.read(pdfRepositoryProvider).getOperationLogs(),
              builder: (context, snapshot) {
                final logs = snapshot.data ?? const <Map<String, dynamic>>[];
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFFEAF4FF), Color(0xFFF8FBFF)]),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(color: const Color(0xFFB8D9FF)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1565C0).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: const Icon(Icons.history_rounded, color: Color(0xFF1565C0), size: 30),
                                ),
                                const SizedBox(width: 14),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Registro local de operações', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                                      SizedBox(height: 6),
                                      Text('Exibe criação, exclusão, importação, movimentação, renomeação e ajustes importantes. Os registros ficam em memória local, podem restaurar o estado anterior e são limpos automaticamente após 48 horas para manter o aplicativo leve.'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: logs.isEmpty ? null : () async {
                                  final backup = logs.map((item) => Map<String, dynamic>.from(item)).toList();
                                  await ref.read(pdfRepositoryProvider).clearOperationLogs();
                                  if (context.mounted) Navigator.of(context).pop();
                                  if (mounted) {
                                    _showUndoToast(
                                      icon: Icons.cleaning_services_rounded,
                                      message: 'Histórico de operações limpo.',
                                      actionLabel: 'Desfazer limpeza',
                                      onUndo: () async {
                                        await ref.read(pdfRepositoryProvider).replaceOperationLogs(backup);
                                        if (mounted) setState(() {});
                                      },
                                    );
                                  }
                                },
                                icon: const Icon(Icons.delete_sweep_rounded),
                                label: const Text('Limpar histórico'),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed: logs.any((item) => item['canUndo'] == true) ? () async {
                                  final target = logs.firstWhere((item) => item['canUndo'] == true);
                                  await _restoreOperationAndRefresh(target['id'].toString(), offerUndo: true);
                                  if (context.mounted) Navigator.of(context).pop();
                                } : null,
                                icon: const Icon(Icons.restore_rounded),
                                label: const Text('Restaurar último ponto'),
                              ),
                              const SizedBox(width: 10),
                              Text('${logs.length} registro(s) ativos'),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (logs.isEmpty)
                            const _RichEmptyState(
                              icon: Icons.history_toggle_off_rounded,
                              title: 'Nenhuma operação registrada',
                              subtitle: 'Quando você importar, criar, mover, renomear ou excluir itens, o Folhear registrará aqui com data, hora e possibilidade de desfazer quando houver ponto de restauração disponível.',
                              pills: ['Cache 48h', 'Desfazer', 'Leve e local'],
                              badges: [],
                              details: [],
                            )
                          else
                            for (final log in logs)
                              Builder(builder: (context) {
                                final color = _operationColor(log['action']?.toString() ?? '');
                                final canUndo = log['canUndo'] == true;
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.08),
                                    border: Border.all(color: color.withOpacity(0.28)),
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(backgroundColor: color.withOpacity(0.15), child: Icon(Icons.bolt_rounded, color: color)),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(log['action']?.toString() ?? 'Operação', style: TextStyle(color: color, fontWeight: FontWeight.w900)),
                                            const SizedBox(height: 2),
                                            Text(log['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                                            const SizedBox(height: 4),
                                            Text(log['detail']?.toString() ?? ''),
                                            const SizedBox(height: 6),
                                            Text(_formatOperationDate(log['createdAt']?.toString() ?? ''), style: const TextStyle(fontSize: 12, color: Color(0xFF607D8B))),
                                          ],
                                        ),
                                      ),
                                      if (canUndo)
                                        TextButton.icon(
                                          onPressed: () async {
                                            await _restoreOperationAndRefresh(log['id'].toString(), offerUndo: true);
                                            if (context.mounted) Navigator.of(context).pop();
                                          },
                                          icon: const Icon(Icons.undo_rounded),
                                          label: const Text('Desfazer'),
                                        ),
                                      PopupMenuButton<String>(
                                        tooltip: 'Opções do registro',
                                        icon: const Icon(Icons.more_vert_rounded),
                                        onSelected: (value) async {
                                          if (value == 'remove') {
                                            final removed = Map<String, dynamic>.from(log);
                                            await ref.read(pdfRepositoryProvider).removeOperationLog(log['id'].toString());
                                            if (context.mounted) Navigator.of(context).pop();
                                            if (mounted) {
                                              _showUndoToast(
                                                icon: Icons.delete_sweep_rounded,
                                                message: 'Registro removido do histórico.',
                                                actionLabel: 'Desfazer',
                                                onUndo: () async {
                                                  final current = await ref.read(pdfRepositoryProvider).getOperationLogs();
                                                  await ref.read(pdfRepositoryProvider).replaceOperationLogs([removed, ...current]);
                                                  if (mounted) setState(() {});
                                                },
                                              );
                                            }
                                          }
                                        },
                                        itemBuilder: (context) => const [
                                          PopupMenuItem(
                                            value: 'remove',
                                            child: ListTile(
                                              dense: true,
                                              leading: Icon(Icons.delete_outline_rounded),
                                              title: Text('Remover este registro'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }),
                        ],
                      ),
                    ),
                  ),
                );
              },
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
      isScrollControlled: true,
      builder: (context) {
        final state = ref.read(pdfViewModelProvider).value;
        final documents = state?.documents ?? const <PdfDocument>[];

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: ListView(
            shrinkWrap: true,
            children: [
              _MoreOptionCard(
                icon: Icons.tune_rounded,
                iconColor: const Color(0xFF1565C0),
                backgroundColor: const Color(0xFFEAF4FF),
                title: 'Central de ajustes',
                subtitle: 'Reúne opções gerais do aplicativo, informações de versão, manutenção local e revisão dos PDFs já importados.',
                onTap: () {
                  Navigator.of(context).pop();
                  _showElegantToast(
                    icon: Icons.tune_rounded,
                    message: 'A central de ajustes está organizada no menu Mais.',
                  );
                },
              ),
              _MoreOptionCard(
                icon: Icons.info_outline_rounded,
                iconColor: const Color(0xFF5E35B1),
                backgroundColor: const Color(0xFFF1ECFF),
                title: 'Sobre o Folhear',
                subtitle: 'Veja informações completas sobre o aplicativo, recursos disponíveis, dados do desenvolvedor, versão atual e notas da versão.',
                onTap: () {
                  Navigator.of(context).pop();
                  Future<void>.delayed(const Duration(milliseconds: 120), _openAboutPage);
                },
              ),
              _MoreOptionCard(
                icon: Icons.history_rounded,
                iconColor: const Color(0xFF1565C0),
                backgroundColor: const Color(0xFFEAF4FF),
                title: 'Histórico e desfazer',
                subtitle: 'Veja tudo que foi criado, excluído, movido, importado ou renomeado, com data/hora e restauração do estado anterior quando disponível.',
                onTap: () {
                  Navigator.of(context).pop();
                  Future<void>.delayed(const Duration(milliseconds: 120), _openOperationLogPage);
                },
              ),
              const SizedBox(height: 10),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: false,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 6),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4DB),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFFFA000)),
                  ),
                  title: const Text('Versões dos PDFs',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: const Text('Lista recolhida para não alongar demais a página quando houver muitos documentos importados.'),
                  children: [
                    for (final doc in documents)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          doc.isLocal ? Icons.upload_file_rounded : Icons.picture_as_pdf_outlined,
                          color: doc.isLocal ? const Color(0xFF1565C0) : const Color(0xFFD32F2F),
                        ),
                        title: Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${doc.version} • ${doc.pageCount} páginas'),
                      ),
                  ],
                ),
              ),
              _MoreOptionCard(
                icon: Icons.restart_alt_rounded,
                iconColor: const Color(0xFFC62828),
                backgroundColor: const Color(0xFFFFECEC),
                title: 'Resetar configurações',
                subtitle: 'Remove favoritos, pastas, PDFs importados, post-its e preferências locais. Use apenas quando quiser começar a configuração novamente.',
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
    final isMobile = MediaQuery.of(context).size.width < 700;
    final navSelectedFolder = _folders.cast<PdfFolder?>().firstWhere(
          (folder) => folder?.id == _selectedFolderId,
          orElse: () => null,
        );
    final navFolderColor = Color(navSelectedFolder?.colorValue ?? 0xFF0B5CAD);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: isMobile ? 56 : 64,
        titleSpacing: isMobile ? 6 : 12,
        title: const _BrandTitle(),
        actions: [
          if (_selectedIndex != 2)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _AnimatedFoldersButton(
                onTap: () => _onNavTap(2),
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Atualizar pastas',
                  onPressed: _refreshFolders,
                  icon: const Icon(Icons.sync_rounded, color: Color(0xFF1565C0)),
                ),
                IconButton(
                  tooltip: 'Mais opções',
                  onPressed: _openMoreSheet,
                  icon: const Icon(Icons.tune_rounded, color: Color(0xFF5E35B1)),
                ),
                const SizedBox(width: 6),
              ],
            ),
        ],
      ),
      body: Stack(
        children: [
          pdfState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Center(
                child: Text('Erro ao carregar documentos:\n$error',
                    textAlign: TextAlign.center)),
            data: (state) {
              final selectedFolder = _folders.cast<PdfFolder?>().firstWhere(
                    (folder) => folder?.id == _selectedFolderId,
                    orElse: () => null,
                  );
              final selectedCategoryName = _categoryLabelForFolder(selectedFolder);
              final folderFiles =
                  selectedFolder?.documentFiles.toSet() ?? <String>{};
              final inRoot = _selectedFolderId == 'root';
              final documents = inRoot
                  ? state.filteredDocuments
                  : state.filteredDocuments
                      .where((doc) => folderFiles.contains(doc.file))
                      .toList();
              final isWide = MediaQuery.of(context).size.width >= 900;

              if (_selectedIndex == 2) {
                return SafeArea(
                  bottom: false,
                  child: RefreshIndicator(
                    onRefresh: _refreshFolders,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                              isMobile ? 14 : 24, 10, isMobile ? 14 : 24, 12),
                          sliver: SliverToBoxAdapter(
                            child: _FoldersOverviewExpander(
                              folders: _folders,
                              documentsCount: state.documents.length,
                              onCreate: () => _createFolder(state.documents),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                              isMobile ? 14 : 24, 0, isMobile ? 14 : 24, 12),
                          sliver: SliverToBoxAdapter(
                            child: _RootDocumentsHighlightExpander(
                              folders: _folders,
                              documentsCount: state.documents.length,
                              selectedFolderId: _selectedFolderId,
                              onSelect: (folder) {
                                setState(() {
                                  _selectedFolderId = folder.id;
                                  _selectedIndex = 0;
                                  _showFoldersPanel = true;
                                });
                              },
                            ),
                          ),
                        ),
                        ..._buildFolderCategorySlivers(context, isMobile),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                              isMobile ? 14 : 24, 8, isMobile ? 14 : 24, 124),
                          sliver: SliverToBoxAdapter(
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () => _createFolder(state.documents),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                icon: const Icon(Icons.add_circle_outline_rounded),
                                label: const Text('Criar pasta'),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return SafeArea(
                bottom: false,
                child: RefreshIndicator(
                  onRefresh: _refreshHome,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (false)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                              isMobile ? 14 : 24, 8, isMobile ? 14 : 24, 14),
                          sliver: SliverToBoxAdapter(
                            child: _FolderExplorer(
                              folders: _folders,
                              selectedFolderId: _selectedFolderId,
                              treeMode: _showFolderTree,
                              onSelect: (folder) =>
                                  setState(() => _selectedFolderId = folder.id),
                              onCreate: _createFolder,
                              onRename: _openFolderOptionsSheet,
                            ),
                          ),
                        ),
                      if (_selectedIndex == 1)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                              isMobile ? 14 : 24, 0, isMobile ? 14 : 24, 14),
                          sliver: SliverToBoxAdapter(
                              child: _FavoritesModeToggle(
                                selectedIndex: _favoriteSectionIndex,
                                onChanged: (index) => setState(() => _favoriteSectionIndex = index),
                              )),
                        ),
                      if (_selectedIndex == 1 && _favoriteSectionIndex == 0)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                              isMobile ? 14 : 24, 0, isMobile ? 14 : 24, 14),
                          sliver: SliverToBoxAdapter(
                              child: _FavoritePagesStrip(
                                  documents: state.documents)),
                        ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                            isMobile ? 14 : 24, 0, isMobile ? 14 : 24, 14),
                        sliver: SliverToBoxAdapter(
                          child: _RootDocumentsHighlightExpander(
                            folders: _folders,
                            documentsCount: state.documents.length,
                            selectedFolderId: _selectedFolderId,
                            onSelect: (folder) {
                              setState(() {
                                _selectedFolderId = folder.id;
                                _selectedIndex = 0;
                                _showFoldersPanel = true;
                              });
                            },
                          ),
                        ),
                      ),
                      if (documents.isNotEmpty)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                              isMobile ? 14 : 24, 4, isMobile ? 14 : 24, 14),
                          sliver: SliverToBoxAdapter(
                            child: _PageWorkspaceHeader(
                              favoriteMode: _selectedIndex == 1,
                              totalDocuments: documents.length,
                              selectedFolderName:
                                  selectedFolder?.name ?? 'Documentos',
                              categoryName: selectedCategoryName,
                              selectedFolderColor: _selectedIndex == 1
                                  ? (_favoriteSectionIndex == 0
                                      ? const Color(0xFF1565C0)
                                      : const Color(0xFFFFA000))
                                  : Color(selectedFolder?.colorValue ?? 0xFF0B5CAD),
                            ),
                          ),
                        ),
                      if (_selectedIndex == 1 && documents.isNotEmpty && _favoriteSectionIndex == 1)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                              isMobile ? 14 : 24, 0, isMobile ? 14 : 24, 12),
                          sliver: const SliverToBoxAdapter(
                              child: _FavoritesSectionTitle(
                                  icon: Icons.star_rounded,
                                  title: 'Documentos favoritos',
                                  description:
                                      'PDFs completos marcados com estrela para acesso rápido.')),
                        ),
                      if (documents.isEmpty)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(isMobile ? 14 : 24, 0, isMobile ? 14 : 24, 124),
                          sliver: SliverToBoxAdapter(
                            child: _selectedIndex == 1
                              ? _FavoritesEmptyState(documents: state.documents)
                              : _RichEmptyState(
                                  icon: selectedFolder == null || selectedFolder.id == 'root'
                                      ? Icons.upload_file_rounded
                                      : Icons.folder_open_rounded,
                                  title: selectedFolder == null || selectedFolder.id == 'root'
                                      ? 'Sua biblioteca está vazia no momento'
                                      : 'Pasta aberta: ${selectedFolder.name}',
                                  subtitle: selectedFolder == null || selectedFolder.id == 'root'
                                      ? 'Para começar a usar o Folhear, importe um ou mais arquivos PDF do seu dispositivo. Você pode montar uma biblioteca pessoal, separar por pastas e depois marcar itens importantes como favoritos.'
                                      : 'A categoria "$selectedCategoryName" está ativa e a pasta "${selectedFolder.name}" ainda não possui PDFs visíveis. Você pode importar arquivos diretamente para esta pasta, mover documentos existentes para cá ou voltar para outra pasta da mesma categoria.',
                                  pills: selectedFolder == null || selectedFolder.id == 'root'
                                      ? const [
                                          'Ações rápidas',
                                          'Importar PDF',
                                          'Criar pasta',
                                          'Abrir Pastas',
                                        ]
                                      : [
                                          'Ver categoria',
                                          'Importar nesta pasta',
                                          'Criar subpasta',
                                          'Mover PDF existente',
                                        ],
                                  pillActions: selectedFolder == null || selectedFolder.id == 'root'
                                      ? [
                                          _openQuickActions,
                                          _importPdfsFromDevice,
                                          () => _createFolder(state.documents),
                                          () => _onNavTap(2),
                                        ]
                                      : [
                                          () => _onNavTap(2),
                                          () => _importPdfsToFolder(selectedFolder),
                                          () => _createFolder(state.documents),
                                          () => _openFoldersBrowserSheet(state.documents),
                                        ],
                                  badges: const [],
                                  details: selectedFolder == null || selectedFolder.id == 'root'
                                      ? const [
                                          'A biblioteca só passa a exibir documentos depois que você importar arquivos PDF do armazenamento do aparelho ou do computador.',
                                          'Depois da importação, você poderá abrir o PDF, navegar entre páginas, criar post-its, marcar páginas favoritas e compartilhar documentos.',
                                          'Se desejar, crie pastas para agrupar conteúdos por tema, disciplina, processo, cliente, assunto ou qualquer outro critério de organização.',
                                        ]
                                      : [
                                          'Use “Importar nesta pasta” para selecionar um ou vários PDFs. Ao concluir, cada arquivo já será vinculado automaticamente à pasta aberta, sem precisar mover depois.',
                                          'Use “Mover PDF existente” quando o arquivo já estiver na biblioteca principal ou em outra pasta. O documento permanece salvo e apenas o vínculo de organização é atualizado.',
                                          'A área de contexto informa a categoria, o estado da pasta e o vínculo automático. Assim fica claro onde o novo PDF será exibido depois da importação.',
                                          'Caso importe um arquivo com nome repetido, o Folhear mantém o fluxo de duplicidade: preservar o original, substituir ou manter os dois com novo nome.',
                                        ],
                                ),
                          ),
                        )
                      else if (_selectedIndex == 1 && _favoriteSectionIndex == 0)
                        const SliverToBoxAdapter(child: SizedBox.shrink())
                      else if (_selectedIndex == 1 && _favoriteSectionIndex == 1)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(isMobile ? 14 : 24, 0, isMobile ? 14 : 24, 124),
                          sliver: SliverToBoxAdapter(
                            child: _FavoriteDocumentsGroupedExpanderList(
                              documents: documents,
                              folders: _folders,
                              onFavorite: _toggleDocumentFavorite,
                              onDelete: _deleteDocumentWithUndo,
                              confirmDelete: _confirmDeleteDocument,
                              onLongPress: _openDocumentOptionsSheet,
                              onMove: _openDocumentMoveSheet,
                              onBeforeOpen: _closeSearch,
                            ),
                          ),
                        )
                      else if (isWide)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 118),
                          sliver: SliverGrid.builder(
                            itemCount: documents.length,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                              mainAxisExtent: 150,
                            ),
                            itemBuilder: (context, index) => _PdfItem(
                              document: documents[index],
                              onFavorite: () =>
                                  _toggleDocumentFavorite(documents[index]),
                              onDelete: () =>
                                  _deleteDocumentWithUndo(documents[index]),
                              confirmDelete: () =>
                                  _confirmDeleteDocument(documents[index]),
                              onLongPress: () =>
                                  _openDocumentOptionsSheet(documents[index]),
                              onMove: () =>
                                  _openDocumentMoveSheet(documents[index]),
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
                              if (index.isOdd)
                                return const SizedBox(height: 12);
                              final document = documents[index ~/ 2];
                              return _PdfItem(
                                document: document,
                                onFavorite: () =>
                                    _toggleDocumentFavorite(document),
                                onDelete: () =>
                                    _deleteDocumentWithUndo(document),
                                confirmDelete: () =>
                                    _confirmDeleteDocument(document),
                                onLongPress: () =>
                                    _openDocumentOptionsSheet(document),
                                onMove: () =>
                                    _openDocumentMoveSheet(document),
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
          if (_searchOpen)
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
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: _HomeBottomArea(
          controller: _searchController,
          focusNode: _searchFocus,
          selectedIndex: _selectedIndex,
          searchOpen: _searchOpen,
          onOpenActions: _openQuickActions,
          onCloseSearch: _closeSearch,
          onChanged: (value) =>
              ref.read(pdfViewModelProvider.notifier).updateSearch(value),
          onNavTap: _onNavTap,
          selectedFolderColor: navFolderColor,
        ),
      ),
    );
  }
}

Color _paletteColor(int index) {
  const colors = <Color>[
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFFFFA000),
    Color(0xFF6A1B9A),
    Color(0xFFD32F2F),
    Color(0xFF00838F),
  ];
  return colors[index % colors.length];
}

int _folderPdfCountDeep(PdfFolder folder, List<PdfFolder> folders) {
  final children = folders.where((item) => item.parentId == folder.id);
  return folder.documentFiles.length +
      children.fold<int>(0, (total, child) => total + _folderPdfCountDeep(child, folders));
}

IconData _folderCategoryIcon(PdfFolder folder) {
  final text = '${folder.categoryName ?? ''} ${folder.name}'.toLowerCase();
  if (text.contains('juríd') || text.contains('jurid') || text.contains('contrat')) return Icons.gavel_rounded;
  if (text.contains('escolar') || text.contains('acad') || text.contains('curso')) return Icons.school_rounded;
  if (text.contains('pessoal') || text.contains('identifica')) return Icons.badge_rounded;
  if (text.contains('saúde') || text.contains('saude')) return Icons.favorite_rounded;
  if (text.contains('finance') || text.contains('contáb') || text.contains('contab')) return Icons.account_balance_wallet_rounded;
  if (text.contains('escritório') || text.contains('escritorio') || text.contains('norma')) return Icons.business_center_rounded;
  return Icons.folder_special_rounded;
}

String _folderPath(PdfFolder folder, List<PdfFolder> folders) {
  final names = <String>[folder.name];
  var parentId = folder.parentId;
  while (parentId != null && parentId != 'root') {
    final parent = folders.cast<PdfFolder?>().firstWhere(
      (item) => item?.id == parentId,
      orElse: () => null,
    );
    if (parent == null) break;
    names.insert(0, parent.name);
    parentId = parent.parentId;
  }
  return names.join(' / ');
}

int _folderHierarchyLevel(PdfFolder folder, List<PdfFolder> folders) {
  if (folder.id == 'root') return 0;
  var level = 1;
  var parentId = folder.parentId;
  while (parentId != null && parentId != 'root') {
    final parent = folders.cast<PdfFolder?>().firstWhere(
      (item) => item?.id == parentId,
      orElse: () => null,
    );
    if (parent == null) break;
    level += 1;
    parentId = parent.parentId;
  }
  return level;
}

String _folderPurposeDescription(PdfFolder folder) {
  final text = '${folder.categoryName ?? ''} ${folder.name}'.toLowerCase();
  if (folder.id == 'root') {
    return 'Biblioteca principal: reúne todos os PDFs importados e serve como ponto inicial para navegar pelas categorias, subpastas e documentos vinculados.';
  }
  if (text.contains('juríd') || text.contains('jurid') || text.contains('contrat') || text.contains('process')) {
    return 'Área indicada para contratos, processos, procurações, pareceres, notificações e documentos de acompanhamento jurídico ou administrativo.';
  }
  if (text.contains('escolar') || text.contains('acad') || text.contains('curso') || text.contains('disciplina') || text.contains('pesquisa')) {
    return 'Área voltada para materiais acadêmicos, matrículas, disciplinas, históricos, diplomas, cursos, pesquisas e documentos de estudo.';
  }
  if (text.contains('pessoal') || text.contains('identifica') || text.contains('saúde') || text.contains('saude') || text.contains('família') || text.contains('familia')) {
    return 'Área para documentos pessoais e familiares, como identificação, saúde, comprovantes, registros patrimoniais e arquivos de consulta rápida.';
  }
  if (text.contains('finance') || text.contains('contáb') || text.contains('contab') || text.contains('fiscal') || text.contains('boleto')) {
    return 'Área destinada a comprovantes, relatórios, notas, extratos, tributos e demais documentos financeiros ou contábeis.';
  }
  if (text.contains('escritório') || text.contains('escritorio') || text.contains('norma') || text.contains('manual') || text.contains('procedimento') || text.contains('pop')) {
    return 'Área preparada para documentos de escritório, normas, manuais, POPs, procedimentos, acordos e materiais institucionais.';
  }
  return 'Área personalizada para organizar PDFs relacionados a este tema, mantendo o caminho, a hierarquia e os vínculos de documentos sempre claros.';
}

String _folderDetailText(PdfFolder folder, List<PdfFolder> folders) {
  final level = _folderHierarchyLevel(folder, folders);
  final childrenCount = folders.where((item) => item.parentId == folder.id).length;
  final pdfCount = _folderPdfCountDeep(folder, folders);
  final levelLabel = level == 0 ? 'Nível raiz' : 'Nível $level da hierarquia';
  final path = folder.id == 'root' ? 'Documentos' : _folderPath(folder, folders);
  final childrenLabel = childrenCount == 1 ? '1 subpasta' : '$childrenCount subpasta(s)';
  final pdfLabel = pdfCount == 1 ? '1 PDF vinculado' : '$pdfCount PDFs vinculados';
  return '$levelLabel • Caminho: $path • $childrenLabel • $pdfLabel. ${_folderPurposeDescription(folder)}';
}

class _ToastCountdownPill extends StatelessWidget {
  final int seconds;
  const _ToastCountdownPill({required this.seconds});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: seconds.toDouble(), end: 0),
      duration: Duration(seconds: seconds),
      builder: (context, value, child) {
        final remaining = value.ceil().clamp(0, seconds);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.82),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFB8D9FF)),
          ),
          child: Text('${remaining}s',
              style: const TextStyle(
                  color: Color(0xFF0B5CAD),
                  fontWeight: FontWeight.w900,
                  fontFeatures: [FontFeature.tabularFigures()])),
        );
      },
    );
  }
}

class _ColorfulPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _ColorfulPill({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 520;
    final content = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: isNarrow ? 280 : 360),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isNarrow ? 10 : 12,
          vertical: isNarrow ? 7 : 8,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color.withOpacity(0.12), Colors.white]),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: isNarrow ? 14 : 16, color: color),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: isNarrow ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: color,
                  fontSize: isNarrow ? 13 : null,
                  height: 1.15,
                ),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.touch_app_rounded, size: isNarrow ? 13 : 14, color: color),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class _FolderParentSelector extends StatelessWidget {
  final List<PdfFolder> folders;
  final String selectedParentId;
  final ValueChanged<String> onChanged;

  const _FolderParentSelector({
    required this.folders,
    required this.selectedParentId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = folders.toList()
      ..sort((a, b) => _folderPath(a, folders).toLowerCase().compareTo(_folderPath(b, folders).toLowerCase()));
    final safeSelected = sorted.any((folder) => folder.id == selectedParentId) ? selectedParentId : 'root';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD7E7F7)),
      ),
      child: DropdownButtonFormField<String>(
        value: safeSelected,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Hierarquia da nova pasta',
          helperText: 'Escolha onde a pasta será inserida: raiz, categoria principal ou subpasta existente.',
          prefixIcon: Icon(Icons.account_tree_rounded),
          border: OutlineInputBorder(),
        ),
        items: [
          for (final folder in sorted)
            DropdownMenuItem(
              value: folder.id,
              child: Row(
                children: [
                  Icon(folder.id == 'root' ? Icons.home_rounded : Icons.folder_rounded, color: Color(folder.colorValue), size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(folder.id == 'root' ? 'Biblioteca principal / raiz' : _folderPath(folder, folders), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

class _PresetFolderTemplate {
  final String title;
  final int colorValue;
  final IconData icon;
  final String description;
  final List<String> children;

  const _PresetFolderTemplate({
    required this.title,
    required this.colorValue,
    required this.icon,
    required this.description,
    required this.children,
  });
}

class _PresetFolderSelection {
  final _PresetFolderTemplate template;
  final List<String> selectedChildren;

  const _PresetFolderSelection({
    required this.template,
    required this.selectedChildren,
  });
}

class _PresetFolderTemplateExpander extends StatelessWidget {
  final _PresetFolderTemplate template;
  final Set<String> selectedChildren;
  final ValueChanged<bool> onToggleAll;
  final void Function(String child, bool enabled) onToggleChild;
  final VoidCallback onCreate;

  const _PresetFolderTemplateExpander({
    required this.template,
    required this.selectedChildren,
    required this.onToggleAll,
    required this.onToggleChild,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(template.colorValue);
    final allSelected = selectedChildren.length == template.children.length;

    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(template.icon, color: color),
          ),
          title: Text(
            template.title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            '${selectedChildren.length} de ${template.children.length} subpastas selecionadas',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.description,
                    textAlign: TextAlign.justify,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          height: 1.45,
                          color: const Color(0xFF355C7D),
                        ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Selecionar todas as subpastas sugeridas',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Switch(
                        value: allSelected,
                        activeThumbColor: color,
                        onChanged: onToggleAll,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final child in template.children)
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: color,
                      value: selectedChildren.contains(child),
                      title: Text(child),
                      subtitle: Text(
                        'Inclui esta subpasta na criação automática da estrutura.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      onChanged: (enabled) => onToggleChild(child, enabled),
                    ),
                  if (selectedChildren.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 4, bottom: 10),
                      child: Text(
                        'Selecione pelo menos uma subpasta para criar a estrutura.',
                        style: TextStyle(
                          color: Color(0xFFC62828),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: selectedChildren.isEmpty ? null : onCreate,
                      style: FilledButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: Text(
                        selectedChildren.length == template.children.length
                            ? 'Criar estrutura completa'
                            : 'Criar estrutura personalizada',
                      ),
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
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD7E7F7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Dados da pasta',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          TextField(
            controller: nameController,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Nome da pasta',
              prefixIcon: Icon(Icons.drive_file_rename_outline_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          Text('Cor da pasta',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final color in colors)
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => onColorChanged(color),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: color,
                    child: selectedColor.value == color.value
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FolderDocumentsSection extends StatelessWidget {
  final List<PdfFolder> folders;
  final List<PdfDocument> availableDocuments;
  final Set<String> selectedFiles;
  final String currentFolderId;
  final void Function(String file, bool selected) onToggleFile;

  const _FolderDocumentsSection({
    required this.availableDocuments,
    required this.folders,
    required this.selectedFiles,
    required this.currentFolderId,
    required this.onToggleFile,
  });

  void _toggleFiles(Iterable<String> files, bool selected) {
    for (final file in files.toSet()) {
      onToggleFile(file, selected);
    }
  }

  Set<String> _collectFolderFiles(PdfFolder folder) {
    final visited = <String>{};
    final collected = <String>{};

    void visit(String folderId) {
      if (!visited.add(folderId)) return;
      final current = folders.cast<PdfFolder?>().firstWhere(
            (item) => item?.id == folderId,
            orElse: () => null,
          );
      if (current == null) return;
      collected.addAll(current.documentFiles);
      for (final child in folders.where((item) => item.parentId == current.id)) {
        visit(child.id);
      }
    }

    visit(folder.id);
    return collected;
  }

  @override
  Widget build(BuildContext context) {
    final docsByFile = {
      for (final doc in availableDocuments) doc.file: doc,
    };
    final topCategories = folders
        .where((folder) => folder.id != 'root' && folder.parentId == 'root')
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final reusableFolders = folders
        .where((folder) => folder.id != 'root' && folder.id != currentFolderId)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD7E7F7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('PDFs vinculados',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const Spacer(),
              _TinyPill(
                  icon: Icons.picture_as_pdf_rounded,
                  label: '${selectedFiles.length} selecionado(s)'),
            ],
          ),
          const SizedBox(height: 12),
          if (availableDocuments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Nenhum PDF disponível para vincular no momento.'),
            )
          else
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => _toggleFiles(
                          availableDocuments.map((doc) => doc.file),
                          true,
                        ),
                        icon: const Icon(Icons.select_all_rounded),
                        label: const Text('Selecionar todos'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _toggleFiles(
                          availableDocuments.map((doc) => doc.file),
                          false,
                        ),
                        icon: const Icon(Icons.deselect_rounded),
                        label: const Text('Limpar seleção'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    initiallyExpanded: true,
                    leading: const Icon(Icons.category_rounded,
                        color: Color(0xFF1565C0)),
                    title: const Text('Selecionar por categoria',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: const Text(
                      'Liga de uma vez todos os PDFs vinculados a uma categoria principal e às subpastas que pertencem a ela.',
                    ),
                    children: [
                      for (final category in topCategories)
                        Builder(
                          builder: (context) {
                            final categoryFiles = _collectFolderFiles(category)
                                .where(docsByFile.containsKey)
                                .toSet();
                            if (categoryFiles.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            final allSelected = categoryFiles
                                .every(selectedFiles.contains);
                            return SwitchListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: allSelected,
                              title: Text(category.name),
                              subtitle: Text(
                                '${categoryFiles.length} PDF(s) encontrados nessa categoria.',
                              ),
                              secondary: Icon(Icons.folder_copy_rounded,
                                  color: Color(category.colorValue)),
                              onChanged: (value) =>
                                  _toggleFiles(categoryFiles, value),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    initiallyExpanded: false,
                    leading: const Icon(Icons.drive_file_move_rounded,
                        color: Color(0xFFEF6C00)),
                    title: const Text('Selecionar de outra pasta',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: const Text(
                      'Reaproveita rapidamente os PDFs já vinculados em outra pasta existente.',
                    ),
                    children: [
                      if (reusableFolders.isEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(0, 0, 0, 12),
                          child: Text(
                            'Nenhuma outra pasta disponível para reaproveitar PDFs.',
                          ),
                        )
                      else
                        for (final folder in reusableFolders)
                          Builder(
                            builder: (context) {
                              final folderFiles = folder.documentFiles
                                  .where(docsByFile.containsKey)
                                  .toSet();
                              if (folderFiles.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              final allSelected =
                                  folderFiles.every(selectedFiles.contains);
                              return SwitchListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: allSelected,
                                title: Text(folder.name),
                                subtitle: Text(
                                  '${folderFiles.length} PDF(s) vinculados nesta pasta.',
                                ),
                                secondary: Icon(Icons.folder_rounded,
                                    color: Color(folder.colorValue)),
                                onChanged: (value) =>
                                    _toggleFiles(folderFiles, value),
                              );
                            },
                          ),
                    ],
                  ),
                ),
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    initiallyExpanded: false,
                    leading: const Icon(Icons.picture_as_pdf_rounded,
                        color: Color(0xFFD32F2F)),
                    title: const Text('Selecionar individualmente',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: const Text(
                      'Use os toggles abaixo para montar a seleção PDF por PDF.',
                    ),
                    children: [
                      for (final doc in availableDocuments)
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: selectedFiles.contains(doc.file),
                          title: Text(doc.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(doc.file,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          secondary: Icon(
                            doc.isFavorite
                                ? Icons.star_rounded
                                : Icons.picture_as_pdf_outlined,
                            color: doc.isFavorite
                                ? const Color(0xFFFFA000)
                                : const Color(0xFF1565C0),
                          ),
                          onChanged: (value) => onToggleFile(doc.file, value),
                        ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PageWorkspaceHeader extends StatelessWidget {
  final bool favoriteMode;
  final int totalDocuments;
  final String selectedFolderName;
  final String categoryName;
  final Color selectedFolderColor;
  const _PageWorkspaceHeader(
      {required this.favoriteMode,
      required this.totalDocuments,
      required this.selectedFolderName,
      required this.categoryName,
      required this.selectedFolderColor});
  @override
  Widget build(BuildContext context) {
    final title = favoriteMode ? 'Favoritos' : 'Biblioteca';
    final description = favoriteMode
        ? 'Acesse rapidamente PDFs marcados com estrela e páginas salvas para revisão e consulta recorrente.'
        : 'Gerencie seus PDFs importados, organize por pastas, abra documentos e marque favoritos para acesso rápido.';
    final headerColors = [selectedFolderColor.withOpacity(0.13), const Color(0xFFF8FBFF)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: headerColors),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: selectedFolderColor.withOpacity(0.28))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [selectedFolderColor, selectedFolderColor.withOpacity(0.72)]),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(
                favoriteMode ? Icons.star_rounded : Icons.library_books_rounded,
                color: Colors.white, size: 22)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (favoriteMode)
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900)),
              if (!favoriteMode)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: selectedFolderColor.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: selectedFolderColor.withOpacity(0.28)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_copy_rounded,
                          size: 15, color: selectedFolderColor),
                      const SizedBox(width: 6),
                      Text(categoryName,
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: selectedFolderColor)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(description,
              textAlign: TextAlign.justify,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: const Color(0xFF355C7D), height: 1.45)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _TinyPill(
                icon: Icons.picture_as_pdf_rounded,
                label: '$totalDocuments PDF(s)'),
            if (!favoriteMode)
              _TinyPill(
                  icon: Icons.folder_open_rounded, label: selectedFolderName),
            _TinyPill(
                icon:
                    favoriteMode ? Icons.bolt_rounded : Icons.touch_app_rounded,
                label: favoriteMode ? 'Acesso rápido' : 'Toque para abrir')
          ]),
        ])),
      ]),
    );
  }
}

class _FoldersPageHeader extends StatelessWidget {
  final int foldersCount;
  final int documentsCount;
  const _FoldersPageHeader(
      {required this.foldersCount, required this.documentsCount});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFEAF4FF), Color(0xFFF8FBFF)]),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFB8D9FF))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF0B5CAD), Color(0xFF42A5F5)]),
                borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.folder_copy_rounded, color: Colors.white)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Pastas da biblioteca',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text(
              'Use as pastas para localizar PDFs com mais rapidez, separar documentos por contexto e manter a biblioteca sempre organizada de forma visual.',
              textAlign: TextAlign.justify,
              style: TextStyle(color: Color(0xFF355C7D), height: 1.45)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _TinyPill(
                icon: Icons.folder_open_rounded,
                label: '$foldersCount pasta(s)'),
            _TinyPill(
                icon: Icons.picture_as_pdf_rounded,
                label: '$documentsCount PDF(s)')
          ]),
        ])),
      ]),
    );
  }
}

class _AboutSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> paragraphs;
  final Color color;
  const _AboutSection({
    required this.icon,
    required this.title,
    required this.paragraphs,
    this.color = const Color(0xFF0B5CAD),
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color.withOpacity(0.12), Colors.white]),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withOpacity(0.28)),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.10),
                blurRadius: 16,
                offset: const Offset(0, 7))
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900)))
        ]),
        const SizedBox(height: 12),
        for (final paragraph in paragraphs)
          Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(paragraph,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.48, color: const Color(0xFF263238)))),
      ]),
    );
  }
}

class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.of(context).size.width < 420;
    final iconSize = compact ? 36.0 : 42.0;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10, vertical: compact ? 6 : 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFFF9FBFF), Color(0xFFEEF6FF)]),
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
              gradient: LinearGradient(
                  colors: [scheme.primary, const Color(0xFF2EA7FF)]),
              borderRadius: BorderRadius.circular(compact ? 12 : 15),
              boxShadow: [
                BoxShadow(
                    color: scheme.primary.withOpacity(0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 4))
              ],
            ),
            child: Icon(Icons.picture_as_pdf_rounded,
                color: Colors.white, size: compact ? 20 : 23),
          ),
          SizedBox(width: compact ? 8 : 10),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(colors: [
              Color(0xFF0B315E),
              Color(0xFF0B5CAD),
              Color(0xFF2EA7FF)
            ]).createShader(bounds),
            child: Text(
              AppInfo.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (compact
                      ? Theme.of(context).textTheme.titleMedium
                      : Theme.of(context).textTheme.titleLarge)
                  ?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.2),
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
    final compact = MediaQuery.of(context).size.width < 430;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 9 : 12, vertical: compact ? 7 : 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: _hovered
                    ? [const Color(0xFFEAF4FF), const Color(0xFFD9EEFF)]
                    : [const Color(0xFFF5FAFF), const Color(0xFFEAF4FF)]),
            borderRadius: BorderRadius.circular(compact ? 15 : 18),
            border: Border.all(color: const Color(0xFFB8D9FF)),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF0B5CAD)
                      .withOpacity(_hovered ? 0.18 : 0.08),
                  blurRadius: _hovered ? 16 : 8,
                  offset: const Offset(0, 5))
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_copy_rounded, color: Color(0xFF0B5CAD)),
              if (!compact) ...[
                const SizedBox(width: 8),
                const Text('Pastas',
                    style: TextStyle(
                        fontWeight: FontWeight.w900, color: Color(0xFF0B315E))),
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

  const _FolderGridCard(
      {required this.folder,
      required this.selected,
      required this.treeMode,
      required this.path,
      required this.onTap,
      required this.onOptions});

  @override
  Widget build(BuildContext context) {
    final color = Color(folder.colorValue);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: selected
                ? [color.withOpacity(0.18), color.withOpacity(0.08)]
                : [Colors.white, const Color(0xFFF8FBFF)]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: selected ? color.withOpacity(0.7) : const Color(0xFFD9EAF9),
            width: selected ? 1.4 : 1),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(selected ? 0.18 : 0.08),
              blurRadius: selected ? 18 : 12,
              offset: const Offset(0, 8))
        ],
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
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(14)),
                    child: Icon(
                        folder.id == 'root'
                            ? Icons.home_filled
                            : Icons.folder_rounded,
                        color: color),
                  ),
                  const Spacer(),
                  IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: onOptions,
                      icon: const Icon(Icons.more_horiz_rounded)),
                ],
              ),
              const SizedBox(height: 8),
              Text(folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(path,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF546E7A))),
              const Spacer(),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TinyPill(
                      icon: Icons.picture_as_pdf_rounded,
                      label: '${folder.documentFiles.length} PDF(s)'),
                  _TinyPill(
                      icon: Icons.swipe_left_rounded,
                      label: 'Opções'),
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
  const _InfoBadgeData(
      {required this.label, required this.icon, required this.color});
}

class _RichEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> pills;
  final List<VoidCallback?>? pillActions;
  final List<_InfoBadgeData> badges;
  final List<String> details;

  const _RichEmptyState(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.pills,
      this.pillActions,
      required this.badges,
      required this.details});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 520;
        final horizontalPadding = isNarrow ? 18.0 : 24.0;
        final iconBox = isNarrow ? 52.0 : 66.0;
        final iconSize = isNarrow ? 26.0 : 32.0;
        final titleStyle = (isNarrow
                ? Theme.of(context).textTheme.titleMedium
                : Theme.of(context).textTheme.titleLarge)
            ?.copyWith(
          fontWeight: FontWeight.w900,
          color: const Color(0xFF0B315E),
          height: 1.12,
        );
        final bodyStyle = (isNarrow
                ? Theme.of(context).textTheme.bodyMedium
                : Theme.of(context).textTheme.bodyLarge)
            ?.copyWith(height: 1.45);
        final detailStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
              height: 1.42,
              fontSize: isNarrow ? 13.2 : null,
            );

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  isNarrow ? 12 : 20, 12, isNarrow ? 12 : 20, 120),
              child: Container(
                padding: EdgeInsets.all(horizontalPadding),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFF7FBFF), Color(0xFFEAF4FF)]),
                  borderRadius: BorderRadius.circular(isNarrow ? 26 : 32),
                  border: Border.all(color: const Color(0xFFB8D9FF)),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xFF0B5CAD).withOpacity(0.10),
                        blurRadius: 28,
                        offset: const Offset(0, 14))
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flex(
                      direction: isNarrow ? Axis.vertical : Axis.horizontal,
                      crossAxisAlignment: isNarrow
                          ? CrossAxisAlignment.center
                          : CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: iconBox,
                          height: iconBox,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [
                              Color(0xFF0B5CAD),
                              Color(0xFF42A5F5)
                            ]),
                            borderRadius: BorderRadius.circular(isNarrow ? 18 : 22),
                            boxShadow: [
                              BoxShadow(
                                  color: const Color(0xFF0B5CAD).withOpacity(0.20),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8))
                            ],
                          ),
                          child: Icon(icon, size: iconSize, color: Colors.white),
                        ),
                        SizedBox(width: isNarrow ? 0 : 16, height: isNarrow ? 14 : 0),
                        Flexible(
                          fit: FlexFit.loose,
                          child: Column(
                            crossAxisAlignment: isNarrow
                                ? CrossAxisAlignment.center
                                : CrossAxisAlignment.start,
                            children: [
                              Align(
                                alignment: isNarrow
                                    ? Alignment.center
                                    : Alignment.centerLeft,
                                child: Container(
                                  constraints: BoxConstraints(
                                    maxWidth: isNarrow
                                        ? constraints.maxWidth - 72
                                        : double.infinity,
                                  ),
                                  padding: EdgeInsets.symmetric(
                                      horizontal: isNarrow ? 12 : 14,
                                      vertical: isNarrow ? 7 : 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0B5CAD).withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                        color: const Color(0xFF0B5CAD)
                                            .withOpacity(0.25)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(icon,
                                          size: isNarrow ? 15 : 18,
                                          color: const Color(0xFF0B5CAD)),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          title,
                                          maxLines: isNarrow ? 2 : 3,
                                          overflow: TextOverflow.ellipsis,
                                          softWrap: true,
                                          style: titleStyle,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                subtitle,
                                textAlign: isNarrow ? TextAlign.left : TextAlign.justify,
                                softWrap: true,
                                style: bodyStyle,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (pills.isNotEmpty && pillActions != null) ...[
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (var i = 0; i < pills.length; i++)
                            if (i < pillActions!.length && pillActions![i] != null)
                              _ColorfulPill(
                                icon: Icons.touch_app_rounded,
                                label: pills[i],
                                color: _paletteColor(i),
                                onTap: pillActions![i],
                              )
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(isNarrow ? 12 : 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.72),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0xFFD6E9FF)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.info_outline_rounded,
                                  color: Color(0xFF0B5CAD), size: 18),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Como usar este espaço',
                                  style: TextStyle(
                                    color: Color(0xFF0B315E),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ...details.map((detail) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(top: 2),
                                      child: Icon(Icons.arrow_right_rounded,
                                          color: Color(0xFF0B5CAD)),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        detail,
                                        textAlign: isNarrow
                                            ? TextAlign.left
                                            : TextAlign.justify,
                                        softWrap: true,
                                        style: detailStyle,
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                        ],
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
          title: hasFavoritePages
              ? 'Você ainda não favoritou documentos completos'
              : 'Sua área de favoritos está vazia',
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
          badges: const [],
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
      decoration: BoxDecoration(
          color: badge.color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: badge.color.withOpacity(0.28))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badge.icon, size: 16, color: badge.color),
          const SizedBox(width: 8),
          Text(badge.label,
              style:
                  TextStyle(fontWeight: FontWeight.w800, color: badge.color)),
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
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFD8E6F3))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF0B5CAD)),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: Color(0xFF355C7D))),
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
        gradient: LinearGradient(
            colors: [scheme.primaryContainer, scheme.surfaceContainerHighest]),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            favoriteMode ? 'Favoritos' : 'Biblioteca',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 4),
          Text('$total documento(s) importado(s)',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onPrimaryContainer)),
        ],
      ),
    );
  }
}


class _RootDocumentsHighlightExpander extends StatelessWidget {
  final List<PdfFolder> folders;
  final int documentsCount;
  final String selectedFolderId;
  final ValueChanged<PdfFolder> onSelect;

  const _RootDocumentsHighlightExpander({
    required this.folders,
    required this.documentsCount,
    required this.selectedFolderId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final root = folders.cast<PdfFolder?>().firstWhere(
          (folder) => folder?.id == 'root',
          orElse: () => null,
        ) ??
        PdfFolder(
          id: 'root',
          name: 'Documentos',
          parentId: null,
          documentFiles: const <String>[],
          createdAt: '',
          colorValue: 0xFF1565C0,
        );
    final categories = folders
        .where((folder) => folder.id != 'root' && folder.parentId == 'root')
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    const color = Color(0xFF1565C0);

    return Card(
        elevation: 0,
        color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: color.withOpacity(0.25)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF0B5CAD), Color(0xFF42A5F5)]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.folder_special_rounded, color: Colors.white, size: 22),
          ),
          title: Text(
            'Documentos',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          subtitle: const Text(
            'Categoria principal da biblioteca. Use este painel para voltar à visão geral ou entrar rapidamente nas categorias principais.',
            style: TextStyle(height: 1.35),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('$documentsCount PDF(s)', style: TextStyle(color: color, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.expand_more_rounded, color: color),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _QuickActionTile(
                    icon: Icons.home_filled,
                    iconColor: color,
                    backgroundColor: const Color(0xFFEAF4FF),
                    title: 'Abrir Documentos',
                    subtitle: 'Mostra todos os PDFs importados, independentemente da pasta ou categoria em que foram organizados.',
                    onTap: () => onSelect(root),
                  ),
                  if (categories.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('Categorias principais', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final category in categories)
                          ActionChip(
                            avatar: Icon(_folderCategoryIcon(category), color: Color(category.colorValue), size: 18),
                            label: Text((category.categoryName?.trim().isNotEmpty ?? false) ? category.categoryName!.trim() : category.name),
                            side: BorderSide(color: Color(category.colorValue).withOpacity(0.28)),
                            backgroundColor: Color(category.colorValue).withOpacity(0.08),
                            onPressed: () => onSelect(category),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoldersOverviewExpander extends StatelessWidget {
  final List<PdfFolder> folders;
  final int documentsCount;
  final VoidCallback onCreate;

  const _FoldersOverviewExpander({
    required this.folders,
    required this.documentsCount,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final topCount = folders.where((f) => f.parentId == 'root').length;
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF0B5CAD), Color(0xFF42A5F5)]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.folder_copy_rounded, color: Colors.white),
          ),
          title: Text('Pastas da biblioteca',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          subtitle: const Text(
            'Abra este painel para entender os gestos de arrastar, a lógica das categorias e a forma correta de reorganizar pastas e documentos.',
            style: TextStyle(height: 1.35),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  _MoreOptionCard(
                    icon: Icons.swipe_rounded,
                    iconColor: const Color(0xFF5E35B1),
                    backgroundColor: const Color(0xFFF2ECFF),
                    title: 'Arraste para gerenciar',
                    subtitle: 'Deslize para a esquerda para abrir ações da pasta e para a direita quando quiser iniciar o fluxo de movimentação para dentro ou para fora de outra pasta.',
                    onTap: () {},
                  ),
                  _MoreOptionCard(
                    icon: Icons.drive_file_move_rounded,
                    iconColor: const Color(0xFF1565C0),
                    backgroundColor: const Color(0xFFEAF4FF),
                    title: 'Mover arquivos e pastas',
                    subtitle: 'Use os modais de movimentação para escolher uma pasta de destino e manter toda a hierarquia organizada por categoria.',
                    onTap: () {},
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _TinyPill(icon: Icons.folder_open_rounded, label: '$topCount categoria(s)'),
                      _TinyPill(icon: Icons.picture_as_pdf_rounded, label: '$documentsCount PDF(s)'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderCategoryExpander extends StatelessWidget {
  final PdfFolder folder;
  final List<PdfFolder> folders;
  final String selectedFolderId;
  final ValueChanged<PdfFolder> onSelect;
  final ValueChanged<PdfFolder> onOptions;
  final ValueChanged<PdfFolder> onMove;

  const _FolderCategoryExpander({
    required this.folder,
    required this.folders,
    required this.selectedFolderId,
    required this.onSelect,
    required this.onOptions,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    final subfolders = folders.where((item) => item.parentId == folder.id).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final color = Color(folder.colorValue);
    final categoryTitle =
        (folder.categoryName?.trim().isNotEmpty ?? false)
            ? folder.categoryName!.trim()
            : folder.name;
    final totalPdfCount = _folderPdfCountDeep(folder, folders);
    return Dismissible(
      key: ValueKey('folder-category-expander-${folder.id}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onMove(folder);
          return false;
        }
        onOptions(folder);
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF4FF),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.drive_file_move_rounded, color: Color(0xFF1565C0)),
            SizedBox(width: 8),
            Text('Mover', style: TextStyle(color: Color(0xFF1565C0), fontWeight: FontWeight.w800)),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: const Color(0xFFF3EAFE),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Opções', style: TextStyle(color: Color(0xFF6A1B9A), fontWeight: FontWeight.w800)),
            SizedBox(width: 8),
            Icon(Icons.tune_rounded, color: Color(0xFF6A1B9A)),
          ],
        ),
      ),
      child: Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: color.withOpacity(0.18)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_folderCategoryIcon(folder), color: color, size: 20),
          ),
          title: Text(categoryTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          subtitle: Text(
            _folderDetailText(folder, folders),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(height: 1.35),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('${totalPdfCount} PDF(s)',
                    style: TextStyle(color: color, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 6),
              Icon(Icons.expand_more_rounded, color: color),
            ],
          ),

          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _FolderTreeList(
                root: folder,
                folders: folders,
                selectedFolderId: selectedFolderId,
                onSelect: onSelect,
                onOptions: onOptions,
                onMove: onMove,
              ),

            ),
          ],
        ),
      ),
    ),
    );
  }
}


class _FolderTreeList extends StatelessWidget {
  final PdfFolder root;
  final List<PdfFolder> folders;
  final String selectedFolderId;
  final ValueChanged<PdfFolder> onSelect;
  final ValueChanged<PdfFolder> onOptions;
  final ValueChanged<PdfFolder> onMove;

  const _FolderTreeList({
    required this.root,
    required this.folders,
    required this.selectedFolderId,
    required this.onSelect,
    required this.onOptions,
    required this.onMove,
  });

  List<PdfFolder> _childrenOf(String parentId) {
    return folders.where((item) => item.parentId == parentId).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  List<Widget> _buildBranch(PdfFolder folder, int depth) {
    final children = _childrenOf(folder.id);
    return [
      _FolderSwipeItem(
        folder: folder,
        selected: selectedFolderId == folder.id,
        isChild: depth > 0,
        depth: depth,
        folders: folders,
        onTap: () => onSelect(folder),
        onOptions: () => onOptions(folder),
        onMove: () => onMove(folder),
      ),
      for (final child in children) ...[
        const SizedBox(height: 8),
        ..._buildBranch(child, depth + 1),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildBranch(root, 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          items[i],
        ],
      ],
    );
  }
}

class _FolderSwipeItem extends StatelessWidget {
  final PdfFolder folder;
  final List<PdfFolder> folders;
  final bool selected;
  final bool isChild;
  final int depth;
  final VoidCallback onTap;
  final VoidCallback onOptions;
  final VoidCallback onMove;

  const _FolderSwipeItem({
    required this.folder,
    required this.folders,
    required this.selected,
    this.isChild = false,
    this.depth = 0,
    required this.onTap,
    required this.onOptions,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(folder.colorValue);
    return Dismissible(
      key: ValueKey('folder-swipe-${folder.id}'),
      direction: folder.id == 'root' ? DismissDirection.none : DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onMove();
          return false;
        }
        onOptions();
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF4FF),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.drive_file_move_rounded, color: Color(0xFF1565C0)),
            SizedBox(width: 8),
            Text('Mover', style: TextStyle(color: Color(0xFF1565C0), fontWeight: FontWeight.w800)),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFF3EAFE),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Opções', style: TextStyle(color: Color(0xFF6A1B9A), fontWeight: FontWeight.w800)),
            SizedBox(width: 8),
            Icon(Icons.tune_rounded, color: Color(0xFF6A1B9A)),
          ],
        ),
      ),
      child: Material(
        color: selected ? color.withOpacity(0.10) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.fromLTRB(14 + (depth * 22.0), 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? color.withOpacity(0.45) : const Color(0xFFDCE8F5),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.folder_rounded, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(folder.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text(
                        _folderDetailText(folder, folders),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF607D8B), height: 1.35),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F8FB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('${_folderPdfCountDeep(folder, folders)} PDF(s)',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF355C7D))),
                ),
              ],
            ),
          ),
        ),
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
    final rootFolder = folders.cast<PdfFolder?>().firstWhere(
          (folder) => folder?.id == 'root',
          orElse: () => null,
        );
    final categories = folders
        .where((folder) => folder.id != 'root' && folder.parentId == 'root')
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.55),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: Icon(Icons.folder_open_rounded, color: Theme.of(context).colorScheme.primary),
          title: Text('Pastas', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
          subtitle: const Text('Abra para acessar rapidamente a pasta atual, trocar o filtro da biblioteca e criar novas pastas.'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(tooltip: 'Criar pasta', onPressed: onCreate, icon: const Icon(Icons.create_new_folder_rounded)),
              const Icon(Icons.expand_more_rounded),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  if (rootFolder != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _FolderChip(
                        folder: rootFolder,
                        selected: rootFolder.id == selectedFolderId,
                        onTap: () => onSelect(rootFolder),
                        onLongPress: () => onRename(rootFolder),
                      ),
                    ),
                  for (final category in categories)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _FolderExplorerCategory(
                        folder: category,
                        folders: folders,
                        selectedFolderId: selectedFolderId,
                        onSelect: onSelect,
                        onLongPress: onRename,
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
}

class _FolderExplorerCategory extends StatelessWidget {
  final PdfFolder folder;
  final List<PdfFolder> folders;
  final String selectedFolderId;
  final ValueChanged<PdfFolder> onSelect;
  final ValueChanged<PdfFolder> onLongPress;

  const _FolderExplorerCategory({
    required this.folder,
    required this.folders,
    required this.selectedFolderId,
    required this.onSelect,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(folder.colorValue);
    final categoryTitle =
        (folder.categoryName?.trim().isNotEmpty ?? false)
            ? folder.categoryName!.trim()
            : folder.name;
    final subfolders = folders.where((item) => item.parentId == folder.id).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.folder_copy_rounded, color: color),
          ),
          title: Text(
            categoryTitle,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            _folderDetailText(folder, folders),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, height: 1.35),
          ),
          children: [
            _FolderChip(
              folder: folder,
              selected: selectedFolderId == folder.id,
              onTap: () => onSelect(folder),
              onLongPress: () => onLongPress(folder),
            ),
            const SizedBox(height: 8),
            for (final child in subfolders)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _FolderChip(
                  folder: child,
                  selected: selectedFolderId == child.id,
                  onTap: () => onSelect(child),
                  onLongPress: () => onLongPress(child),
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

  const _FolderChip(
      {required this.folder,
      required this.selected,
      required this.onTap,
      required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: FilterChip(
        selected: selected,
        avatar: Icon(
            folder.id == 'root'
                ? Icons.folder_special_rounded
                : Icons.folder_rounded,
            size: 18,
            color: Color(folder.colorValue)),
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
  final VoidCallback onMove;
  final VoidCallback? onBeforeOpen;

  const _PdfItem(
      {required this.document,
      required this.onFavorite,
      required this.onDelete,
      required this.confirmDelete,
      required this.onLongPress,
      required this.onMove,
      this.onBeforeOpen});

  @override
  Widget build(BuildContext context) {
    void openDocument() {
      onBeforeOpen?.call();
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PdfViewerPage(document: document)));
    }

    return Dismissible(
      key: ValueKey('pdf-${document.file}-${document.isFavorite}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onMove();
          return false;
        }
        return confirmDelete();
      },
      onDismissed: (_) async => onDelete(),
      background: const _SwipeMovePdfBackground(alignment: Alignment.centerLeft),
      secondaryBackground: const _SwipeDeleteBackground(),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        scale: 1,
        child: PdfCard(
            document: document,
            onFavoriteTap: onFavorite,
            onOpenTap: openDocument,
            onLongPress: onLongPress),
      ),
    );
  }
}


class _SwipeMovePdfBackground extends StatelessWidget {
  final Alignment alignment;

  const _SwipeMovePdfBackground({required this.alignment});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4FF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.drive_file_move_rounded, color: Color(0xFF1565C0)),
          SizedBox(width: 8),
          Text(
            'Mover para pasta',
            style: TextStyle(color: Color(0xFF1565C0), fontWeight: FontWeight.w800),
          ),
        ],
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
      decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(18)),
      child: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
    );
  }
}

class _SwipeFavoriteBackground extends StatelessWidget {
  final bool isFavorite;
  final Alignment alignment;

  const _SwipeFavoriteBackground(
      {required this.isFavorite, required this.alignment});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
          color: isFavorite ? scheme.errorContainer : scheme.primaryContainer,
          borderRadius: BorderRadius.circular(18)),
      child: Icon(isFavorite ? Icons.star_border_rounded : Icons.star_rounded,
          color:
              isFavorite ? scheme.onErrorContainer : scheme.onPrimaryContainer),
    );
  }
}


class _FavoriteDocumentsGroupedExpanderList extends StatelessWidget {
  final List<PdfFolder> folders;
  final List<PdfDocument> documents;
  final Future<void> Function(PdfDocument document) onFavorite;
  final Future<void> Function(PdfDocument document) onDelete;
  final Future<bool> Function(PdfDocument document) confirmDelete;
  final void Function(PdfDocument document) onLongPress;
  final void Function(PdfDocument document) onMove;
  final VoidCallback onBeforeOpen;

  const _FavoriteDocumentsGroupedExpanderList({
    required this.documents,
    required this.folders,
    required this.onFavorite,
    required this.onDelete,
    required this.confirmDelete,
    required this.onLongPress,
    required this.onMove,
    required this.onBeforeOpen,
  });

  PdfFolder? _folderFor(PdfDocument document) {
    for (final folder in folders) {
      if (folder.documentFiles.contains(document.file)) return folder;
    }
    return folders.cast<PdfFolder?>().firstWhere(
          (folder) => folder?.id == 'root',
          orElse: () => null,
        );
  }

  String _groupName(PdfDocument document) {
    final folder = _folderFor(document);
    if (folder == null || folder.id == 'root') return 'Documentos';
    final parent = folders.cast<PdfFolder?>().firstWhere(
          (item) => item?.id == folder.parentId,
          orElse: () => null,
        );
    if (parent == null || parent.id == 'root') return folder.name;
    return '${parent.name} › ${folder.name}';
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<PdfDocument>>{};
    for (final document in documents) {
      grouped.putIfAbsent(_groupName(document), () => <PdfDocument>[]).add(document);
    }
    final keys = grouped.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in keys)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: const BorderSide(color: Color(0xFFDCE8F5)),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: false,
                  leading: const Icon(Icons.star_rounded, color: Color(0xFFFFA000)),
                  title: Text(group, style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text('${grouped[group]!.length} favorito(s) nesta seção'),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 760;
                        final width = wide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final document in grouped[group]!)
                              SizedBox(
                                width: width,
                                child: _PdfItem(
                                  document: document,
                                  onFavorite: () => onFavorite(document),
                                  onDelete: () => onDelete(document),
                                  confirmDelete: () => confirmDelete(document),
                                  onLongPress: () => onLongPress(document),
                                  onMove: () => onMove(document),
                                  onBeforeOpen: onBeforeOpen,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FavoritesSectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  const _FavoritesSectionTitle(
      {required this.icon, required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD7E7F7)),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF0B5CAD).withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 6))
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: const Color(0xFFEAF4FF),
                  borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: const Color(0xFF0B5CAD))),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(description,
                    textAlign: TextAlign.justify,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF355C7D), height: 1.35)),
              ])),
        ],
      ),
    );
  }
}


class _FavoritesModeToggle extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _FavoritesModeToggle({required this.selectedIndex, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E7F7)),
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () => onChanged(0),
              style: FilledButton.styleFrom(
                backgroundColor: selectedIndex == 0 ? const Color(0xFFEAF4FF) : Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: Icon(Icons.bookmark_added_rounded, color: selectedIndex == 0 ? const Color(0xFF1565C0) : const Color(0xFF607D8B)),
              label: Text('Páginas salvas', style: TextStyle(color: selectedIndex == 0 ? const Color(0xFF1565C0) : const Color(0xFF607D8B), fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () => onChanged(1),
              style: FilledButton.styleFrom(
                backgroundColor: selectedIndex == 1 ? const Color(0xFFFFF4DB) : Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: Icon(Icons.star_rounded, color: selectedIndex == 1 ? const Color(0xFFFFA000) : const Color(0xFF607D8B)),
              label: Text('Documentos favoritos', style: TextStyle(color: selectedIndex == 1 ? const Color(0xFF8A5A00) : const Color(0xFF607D8B), fontWeight: FontWeight.w800)),
            ),
          ),
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
            const _FavoritesSectionTitle(
              icon: Icons.bookmark_added_rounded,
              title: 'Páginas salvas',
              description: 'Trechos e páginas específicas que você marcou dentro dos PDFs para voltar exatamente ao ponto importante.',
            ),
            const SizedBox(height: 10),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                    side: const BorderSide(color: Color(0xFFD7E7F7)),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onLongPress: () async {
                      final doc = documents.firstWhere(
                        (doc) => doc.file == item.file,
                        orElse: () => PdfDocument(
                          file: item.file,
                          title: item.title,
                          description: '',
                          version: 'v1.0',
                          pageCount: item.page,
                        ),
                      );
                      await ref.read(pdfRepositoryProvider).togglePageFavorite(document: doc, page: item.page);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Página removida dos favoritos.')));
                    },
                    onTap: () {
                      final doc = documents.firstWhere(
                        (doc) => doc.file == item.file,
                        orElse: () => PdfDocument(
                          file: item.file,
                          title: item.title,
                          description: '',
                          version: 'v1.0',
                          pageCount: item.page,
                        ),
                      );
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PdfViewerPage(document: doc, initialPage: item.page)));
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF4FF),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF1565C0)),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF4FF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('PÁG. ${item.page}', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1565C0))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                                const SizedBox(height: 4),
                                Text(item.preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF607D8B), height: 1.35)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.open_in_new_rounded, color: Color(0xFF1565C0)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: backgroundColor,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: iconColor.withOpacity(0.15)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle, style: const TextStyle(height: 1.35)),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: iconColor),
        onTap: onTap,
      ),
    );
  }
}

class _MoreOptionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MoreOptionCard({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: iconColor.withOpacity(0.16)),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle, style: const TextStyle(height: 1.35)),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: iconColor),
        onTap: onTap,
      ),
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
  final Color selectedFolderColor;

  const _HomeBottomArea({
    required this.controller,
    required this.focusNode,
    required this.selectedIndex,
    required this.searchOpen,
    required this.onOpenActions,
    required this.onCloseSearch,
    required this.onChanged,
    required this.onNavTap,
    required this.selectedFolderColor,
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
                          trailing: [
                            IconButton(
                                tooltip: 'Fechar busca',
                                icon: const Icon(Icons.close),
                                onPressed: onCloseSearch)
                          ],
                        ),
                      )
                    : FloatingActionButton.small(
                        key: const ValueKey('home-actions-button'),
                        heroTag: 'home-actions-button',
                        tooltip: 'Ações rápidas',
                        onPressed: onOpenActions,
                        child: const Icon(Icons.add_rounded,
                            color: Color(0xFF0D47A1)),
                      ),
              ),
              const SizedBox(height: 6),
              NavigationBar(
                height: 64,
                selectedIndex: selectedIndex,
                onDestinationSelected: onNavTap,
                destinations: [
                  const NavigationDestination(
                      icon: Icon(Icons.menu_book_outlined,
                          color: Color(0xFF1565C0)),
                      selectedIcon: Icon(Icons.menu_book_rounded,
                          color: Color(0xFF0D47A1)),
                      label: 'Biblioteca'),
                  const NavigationDestination(
                      icon: Icon(Icons.star_border_rounded,
                          color: Color(0xFFFFA000)),
                      selectedIcon:
                          Icon(Icons.star_rounded, color: Color(0xFFFFA000)),
                      label: 'Favoritos'),
                  NavigationDestination(
                      icon: Icon(Icons.folder_copy_outlined,
                          color: selectedFolderColor),
                      selectedIcon: Icon(Icons.folder_copy_rounded,
                          color: selectedFolderColor),
                      label: 'Pastas'),
                  const NavigationDestination(
                      icon: Icon(Icons.more_horiz_rounded,
                          color: Color(0xFF5E35B1)),
                      selectedIcon: Icon(Icons.more_horiz_rounded,
                          color: Color(0xFF5E35B1)),
                      label: 'Mais'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
