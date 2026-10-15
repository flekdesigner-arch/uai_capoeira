import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import 'package:uai_capoeira/core/permissions/permission_access_guard.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/theme/app_theme_preset.dart';
import 'package:uai_capoeira/core/theme/app_theme_tokens.dart';
import 'package:uai_capoeira/core/theme/app_theme_controller.dart';
import 'package:uai_capoeira/core/theme/cloud_global_theme.dart';
import 'package:uai_capoeira/core/theme/cloud_global_theme_service.dart';
import 'package:uai_capoeira/core/theme/tema_global_config.dart';
import 'package:uai_capoeira/core/logo/uai_logo_service.dart';
import 'package:uai_capoeira/core/theme/tema_global_service.dart';
import 'package:uai_capoeira/modules/sistema/admin/screens/uai_logo_editor_screen.dart';
import 'package:uai_capoeira/shared/widgets/uai_dynamic_logo.dart';

Color _previewReadableOn(Color background) {
  return background.computeLuminance() > 0.50
      ? const Color(0xFF111827)
      : const Color(0xFFFFFFFF);
}

Color _previewTextOn(Color background) => _previewReadableOn(background);

Color _strongTextOn(Color background) {
  return background.computeLuminance() > 0.50
      ? const Color(0xFF0F172A)
      : const Color(0xFFFFFFFF);
}

Color _previewEnsureVisible(Color color, Color background) {
  final diff = (color.computeLuminance() - background.computeLuminance()).abs();
  if (diff >= 0.22) return color;

  final bgIsDark = background.computeLuminance() < 0.45;
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withLightness(bgIsDark ? 0.74 : 0.30)
      .withSaturation((hsl.saturation + 0.08).clamp(0.0, 1.0))
      .toColor();
}

Color _safePreviewAccent(Color color, Color background) =>
    _previewEnsureVisible(color, background);

Color _softPreviewBg(Color accent, Color surface) =>
    Color.alphaBlend(accent.withAlpha(31), surface);

Color _accessibleSoftBg(Color accent, Color baseSurface) {
  final surfaceIsDark = baseSurface.computeLuminance() < 0.45;
  final hsl = HSLColor.fromColor(accent);
  final strongerAccent = hsl
      .withLightness(surfaceIsDark ? 0.32 : 0.88)
      .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
      .toColor();

  return Color.alphaBlend(
    strongerAccent.withAlpha(surfaceIsDark ? 107 : 140),
    baseSurface,
  );
}

Widget _accessiblePreviewPill({
  required String label,
  required Color accent,
  required Color baseSurface,
}) {
  final bg = _accessibleSoftBg(accent, baseSurface);
  final fg = _strongTextOn(bg);
  final border = _previewEnsureVisible(accent, bg);

  return _PreviewPill(
    label: label,
    foreground: fg,
    background: bg,
    border: border.withAlpha(115),
  );
}

class CentralTemasScreen extends StatefulWidget {
  const CentralTemasScreen({super.key});

  @override
  State<CentralTemasScreen> createState() => _CentralTemasScreenState();
}

class _CentralTemasScreenState extends State<CentralTemasScreen> {
  final PermissionAccessGuard _accessGuard = PermissionAccessGuard();
  late Future<bool> _accessFuture;
  late ThemeGlobalDraft _draft;
  late final ScrollController _scrollController;
  late TextEditingController _campanhaController;
  final GlobalKey _temaPadraoKey = GlobalKey();
  final GlobalKey _regrasKey = GlobalKey();
  final GlobalKey _logoKey = GlobalKey();
  final GlobalKey _temasDisponiveisKey = GlobalKey();
  final GlobalKey _campanhaKey = GlobalKey();
  final GlobalKey _bibliotecaKey = GlobalKey();
  final GlobalKey _actionsKey = GlobalKey();
  bool _saving = false;
  bool _dirty = false;
  bool _speedDialOpen = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _accessFuture = _accessGuard.canAccess(
      permission: 'pode_gerenciar_temas_globais',
    );
    _draft = ThemeGlobalDraft.fromConfig(TemaGlobalService.instance.config);
    _scrollController = ScrollController();
    _campanhaController = TextEditingController(text: _draft.campanhaNome);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _carregarLogoTemaAtual();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _campanhaController.dispose();
    super.dispose();
  }

  void _syncFromService() {
    final config = TemaGlobalService.instance.config;
    setState(() {
      _draft = ThemeGlobalDraft.fromConfig(config);
      _campanhaController.text = _draft.campanhaNome;
      _dirty = false;
      _message = null;
    });
    Future.microtask(() => _carregarLogoTemaAtual());
  }

  void _markDirty() {
    if (!_dirty) {
      setState(() => _dirty = true);
      return;
    }
    setState(() {});
  }

  Future<void> _carregarLogoTemaAtual({bool force = false}) async {
    final themeId = _draft.temaPadraoGlobal.trim();
    if (themeId.isEmpty) return;

    await UaiLogoService.instance.loadForTheme(themeId, force: force);
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    await TemaGlobalService.instance.refresh(silent: false);
    if (!mounted) return;
    _syncFromService();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configuração de tema recarregada.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _criarPadrao() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await TemaGlobalService.instance.criarConfiguracaoPadrao(
      uid: user.uid,
      nome: user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : (user.email ?? 'Admin'),
    );
    if (!mounted) return;
    _syncFromService();
  }

  Future<void> _salvar() async {
    if (_saving) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _saving = true;
      _message = null;
    });

    try {
      final config = _draft.toConfig().copyWith(
        campanhaNome: _campanhaController.text,
      );
      await TemaGlobalService.instance.salvarConfiguracao(
        config,
        uid: user.uid,
        nome: user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : (user.email ?? 'Admin'),
      );
      if (!mounted) return;
      _syncFromService();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuração global de tema salva.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyError(e)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.uai.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _adminDisplayName(User user) {
    return user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : (user.email ?? 'Admin');
  }

  void _showCloudThemeSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _showCloudThemeError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_friendlyCloudThemeError(error)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.uai.error,
      ),
    );
  }

  Future<void> _openCloudThemeForm({CloudGlobalTheme? theme}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final result = await showDialog<_CloudThemeFormResult>(
      context: context,
      builder: (dialogContext) => _CloudThemeFormDialog(theme: theme),
    );
    if (result == null) return;

    try {
      if (theme == null) {
        await CloudGlobalThemeService.instance.createGlobalTheme(
          nome: result.nome,
          descricao: result.descricao,
          ativo: result.ativo,
          disponivelParaUsuarios: result.disponivelParaUsuarios,
          disponivelParaEstudos: result.disponivelParaEstudos,
          settings: result.settings,
          success: result.success,
          warning: result.warning,
          error: result.error,
          criadoPorUid: user.uid,
          criadoPorNome: _adminDisplayName(user),
        );
        _showCloudThemeSuccess('Tema global criado.');
      } else {
        await CloudGlobalThemeService.instance.updateGlobalTheme(
          theme.id,
          nome: result.nome,
          descricao: result.descricao,
          ativo: result.ativo,
          disponivelParaUsuarios: result.disponivelParaUsuarios,
          disponivelParaEstudos: result.disponivelParaEstudos,
          settings: result.settings,
          success: result.success,
          warning: result.warning,
          error: result.error,
        );
        _showCloudThemeSuccess('Tema global atualizado.');
      }
      if (mounted) setState(() {});
    } catch (e) {
      _showCloudThemeError(e);
    }
  }

  Future<void> _toggleCloudThemeActive(CloudGlobalTheme theme) async {
    try {
      await CloudGlobalThemeService.instance.setActive(theme.id, !theme.ativo);
      _showCloudThemeSuccess(
        theme.ativo ? 'Tema global desativado.' : 'Tema global ativado.',
      );
      if (mounted) setState(() {});
    } catch (e) {
      _showCloudThemeError(e);
    }
  }

  Future<void> _archiveCloudTheme(CloudGlobalTheme theme) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final t = dialogContext.uai;
        return AlertDialog(
          backgroundColor: t.surface,
          surfaceTintColor: Colors.transparent,
          title: Text(
            'Arquivar tema global',
            style: TextStyle(color: t.textPrimary),
          ),
          content: Text(
            'O tema será desativado e removido das listas de usuários, sem exclusão física.',
            style: TextStyle(color: t.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.archive_rounded),
              label: const Text('Arquivar'),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;

    try {
      await CloudGlobalThemeService.instance.archiveGlobalTheme(theme.id);
      _showCloudThemeSuccess('Tema global arquivado.');
      if (mounted) setState(() {});
    } catch (e) {
      _showCloudThemeError(e);
    }
  }

  Future<void> _restaurarUaiClassico() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final t = dialogContext.uai;
        return AlertDialog(
          backgroundColor: t.surface,
          surfaceTintColor: Colors.transparent,
          title: Text(
            'Restaurar UAI Clássico?',
            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
          ),
          content: Text(
            'Esta ação volta o app para a configuração de segurança padrão.',
            style: TextStyle(color: t.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Restaurar'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() => _saving = true);
    try {
      await TemaGlobalService.instance.restaurarUaiClassico(
        uid: user.uid,
        nome: user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : (user.email ?? 'Admin'),
      );
      if (!mounted) return;
      _syncFromService();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('UAI Clássico restaurado com sucesso.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyError(e)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.uai.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _scrollToSection(GlobalKey key) async {
    _closeSpeedDial();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final targetContext = key.currentContext;
    if (targetContext == null || !targetContext.mounted) return;

    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOutCubic,
      alignment: 0.06,
    );
  }

  void _toggleSpeedDial() {
    if (!mounted) return;
    setState(() => _speedDialOpen = !_speedDialOpen);
  }

  void _closeSpeedDial() {
    if (!_speedDialOpen || !mounted) return;
    setState(() => _speedDialOpen = false);
  }

  Future<void> _runSpeedDialAction(FutureOr<void> Function() action) async {
    _closeSpeedDial();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    await action();
  }

  Widget _buildSpeedDialBackdrop(BuildContext context) {
    if (!_speedDialOpen) return const SizedBox.shrink();
    final t = context.uai;

    return Positioned.fill(
      child: Semantics(
        button: true,
        label: 'Fechar menu de atalhos',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _closeSpeedDial,
          child: ColoredBox(color: t.textPrimary.withValues(alpha: 0.06)),
        ),
      ),
    );
  }

  Widget _buildFloatingThemeMenu(BuildContext context) {
    return _ThemeSpeedDial(
      open: _speedDialOpen,
      dirty: _dirty,
      saving: _saving,
      onToggle: _toggleSpeedDial,
      actions: [
        _ThemeSpeedDialAction(
          icon: Icons.save_rounded,
          label: 'Salvar',
          tooltip: _dirty
              ? 'Salvar alterações pendentes'
              : 'Nenhuma alteração pendente',
          emphasized: _dirty,
          enabled: _dirty && !_saving,
          onPressed: () => _runSpeedDialAction(_salvar),
        ),
        _ThemeSpeedDialAction(
          icon: Icons.add_circle_rounded,
          label: 'Criar novo tema',
          tooltip: 'Criar novo tema global',
          enabled: !_saving,
          onPressed: () => _runSpeedDialAction(_openCloudThemeForm),
        ),
        _ThemeSpeedDialAction(
          icon: Icons.cloud_sync_rounded,
          label: 'Biblioteca',
          tooltip: 'Ir para biblioteca de temas da nuvem',
          onPressed: () => _scrollToSection(_bibliotecaKey),
        ),
        _ThemeSpeedDialAction(
          icon: Icons.campaign_rounded,
          label: 'Campanha',
          tooltip: 'Ir para modo campanha',
          onPressed: () => _scrollToSection(_campanhaKey),
        ),
        _ThemeSpeedDialAction(
          icon: Icons.palette_rounded,
          label: 'Temas disponíveis',
          tooltip: 'Ir para temas disponíveis',
          onPressed: () => _scrollToSection(_temasDisponiveisKey),
        ),
        _ThemeSpeedDialAction(
          icon: Icons.image_rounded,
          label: 'Logo',
          tooltip: 'Ir para logo dinâmica',
          onPressed: () => _scrollToSection(_logoKey),
        ),
        _ThemeSpeedDialAction(
          icon: Icons.rule_rounded,
          label: 'Regras',
          tooltip: 'Ir para regras de aplicação',
          onPressed: () => _scrollToSection(_regrasKey),
        ),
        _ThemeSpeedDialAction(
          icon: Icons.tune_rounded,
          label: 'Tema padrão',
          tooltip: 'Ir para tema padrão global',
          onPressed: () => _scrollToSection(_temaPadraoKey),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    return FutureBuilder<bool>(
      future: _accessFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoading(context);
        }
        if (snapshot.hasError || snapshot.data != true) {
          return _buildDenied(context);
        }

        return AnimatedBuilder(
          animation: TemaGlobalService.instance,
          builder: (context, _) {
            final service = TemaGlobalService.instance;
            final config = service.config;
            final previewTokens = _tokensDoTemaSelecionado();
            final currentAppPreset =
                AppThemeController.instance.effectivePreset;
            final isDesktop = MediaQuery.of(context).size.width >= 900;
            final pagePadding = _pagePaddingFor(
              MediaQuery.of(context).size.width,
            );
            final maxWidth = _maxWidthFor(MediaQuery.of(context).size.width);
            final appBarBg = _safeAppBarBg(t);
            final appBarFg = _readableOn(appBarBg);

            if (!_dirty &&
                !_saving &&
                _campanhaController.text != config.campanhaNome) {
              _campanhaController.text = config.campanhaNome;
            }

            return PopScope(
              canPop: !_speedDialOpen,
              onPopInvokedWithResult: (didPop, result) {
                if (!didPop && _speedDialOpen) _closeSpeedDial();
              },
              child: Scaffold(
                backgroundColor: t.background,
                appBar: AppBar(
                  title: const Text('Central de Temas'),
                  backgroundColor: appBarBg,
                  foregroundColor: appBarFg,
                  iconTheme: IconThemeData(color: appBarFg),
                  actionsIconTheme: IconThemeData(color: appBarFg),
                ),
                body: SafeArea(
                  child: Stack(
                    children: [
                      RefreshIndicator(
                        onRefresh: _reload,
                        color: previewTokens.primary,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final bottomPadding =
                                MediaQuery.paddingOf(context).bottom + 132;
                            return ListView(
                              controller: _scrollController,
                              padding: pagePadding.add(
                                EdgeInsets.only(bottom: bottomPadding),
                              ),
                              children: [
                                Align(
                                  alignment: Alignment.topCenter,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: maxWidth,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _buildHeader(
                                          context,
                                          config,
                                          previewTokens: previewTokens,
                                          currentAppPreset: currentAppPreset,
                                        ),
                                        const SizedBox(height: 14),
                                        if (!service.documentExists) ...[
                                          _buildMissingDocCard(context),
                                          const SizedBox(height: 14),
                                        ],
                                        if (isDesktop) ...[
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: KeyedSubtree(
                                                  key: _temaPadraoKey,
                                                  child: _buildTemaPadraoCard(
                                                    context,
                                                    config,
                                                    previewTokens,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: KeyedSubtree(
                                                  key: _regrasKey,
                                                  child: _buildRegrasCard(
                                                    context,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 14),
                                          KeyedSubtree(
                                            key: _logoKey,
                                            child: _buildLogoDinamicaCard(
                                              context,
                                              previewTokens,
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: KeyedSubtree(
                                                  key: _temasDisponiveisKey,
                                                  child:
                                                      _buildTemasDisponiveisCard(
                                                        context,
                                                      ),
                                                ),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: KeyedSubtree(
                                                  key: _campanhaKey,
                                                  child: _buildCampanhaCard(
                                                    context,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 14),
                                          KeyedSubtree(
                                            key: _bibliotecaKey,
                                            child: _buildCloudGlobalThemesCard(
                                              context,
                                            ),
                                          ),
                                        ] else ...[
                                          KeyedSubtree(
                                            key: _temaPadraoKey,
                                            child: _buildTemaPadraoCard(
                                              context,
                                              config,
                                              previewTokens,
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                          KeyedSubtree(
                                            key: _logoKey,
                                            child: _buildLogoDinamicaCard(
                                              context,
                                              previewTokens,
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                          KeyedSubtree(
                                            key: _regrasKey,
                                            child: _buildRegrasCard(context),
                                          ),
                                          const SizedBox(height: 14),
                                          KeyedSubtree(
                                            key: _temasDisponiveisKey,
                                            child: _buildTemasDisponiveisCard(
                                              context,
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                          KeyedSubtree(
                                            key: _campanhaKey,
                                            child: _buildCampanhaCard(context),
                                          ),
                                          const SizedBox(height: 14),
                                          KeyedSubtree(
                                            key: _bibliotecaKey,
                                            child: _buildCloudGlobalThemesCard(
                                              context,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 14),
                                        KeyedSubtree(
                                          key: _actionsKey,
                                          child: _buildActions(context),
                                        ),
                                        if (_message != null) ...[
                                          const SizedBox(height: 14),
                                          _buildErrorCard(context, _message!),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      _buildSpeedDialBackdrop(context),
                    ],
                  ),
                ),
                floatingActionButton: SafeArea(
                  minimum: const EdgeInsets.only(right: 12, bottom: 12),
                  child: _buildFloatingThemeMenu(context),
                ),
                floatingActionButtonLocation:
                    FloatingActionButtonLocation.endFloat,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    TemaGlobalConfig config, {
    required UaiThemeTokens previewTokens,
    required UaiThemePreset currentAppPreset,
  }) {
    final headerBg = _safeHeaderBg(previewTokens);
    final onHeader = _previewReadableOn(headerBg);
    final selectedPreset = UaiThemePresetX.fromId(config.temaPadraoGlobal);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: _safeHeaderGradient(previewTokens),
        borderRadius: BorderRadius.circular(24),
        boxShadow: context.uai.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(onHeader.withAlpha(26), headerBg),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.palette_rounded, color: onHeader),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Central de Temas do App',
                      style: TextStyle(
                        color: onHeader,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Controle a identidade visual global do app, campanhas e temas disponíveis para os usuários.',
                      style: TextStyle(
                        color: onHeader.withAlpha(230),
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _previewBadge(
                texto: 'Atual no app: ${currentAppPreset.label}',
                accent: AppTheme.tokensFor(currentAppPreset).primary,
                tokens: AppTheme.tokensFor(currentAppPreset),
                background: headerBg,
              ),
              _previewBadge(
                texto: 'Prévia: ${selectedPreset.label}',
                accent: previewTokens.primary,
                tokens: previewTokens,
                background: headerBg,
              ),
              _previewBadge(
                texto: config.forcarTemaGlobal
                    ? 'Tema global forçado'
                    : 'Tema global livre',
                accent: config.forcarTemaGlobal
                    ? previewTokens.warning
                    : previewTokens.success,
                tokens: previewTokens,
                background: headerBg,
              ),
              _previewBadge(
                texto: config.permitirUsuarioEscolher
                    ? 'Usuários podem escolher'
                    : 'Escolha bloqueada',
                accent: config.permitirUsuarioEscolher
                    ? previewTokens.info
                    : previewTokens.error,
                tokens: previewTokens,
                background: headerBg,
              ),
              _previewBadge(
                texto:
                    '${config.temasDisponiveisUsuario.length} temas liberados',
                accent: previewTokens.accent,
                tokens: previewTokens,
                background: headerBg,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTemaPadraoCard(
    BuildContext context,
    TemaGlobalConfig config,
    UaiThemeTokens previewTokens,
  ) {
    final t = context.uai;
    final preview = previewTokens;

    return _buildSectionCard(
      context,
      title: 'Tema padrão global',
      icon: Icons.hdr_strong_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: UaiThemePresetX.isOfficialId(_draft.temaPadraoGlobal)
                ? _draft.temaPadraoGlobal
                : UaiThemePreset.uaiClassico.id,
            dropdownColor: t.surface,
            decoration: InputDecoration(
              labelText: 'Tema padrão do app',
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: t.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: t.primary, width: 1.5),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: t.border),
              ),
            ),
            items: UaiThemePresetX.officialPresets
                .map(
                  (preset) => DropdownMenuItem(
                    value: preset.id,
                    child: Text(preset.label),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _draft = _draft.copyWith(temaPadraoGlobal: value);
                _dirty = true;
              });
            },
          ),
          const SizedBox(height: 12),
          _ThemePreview(theme: preview),
          if (!UaiThemePresetX.isOfficialId(_draft.temaPadraoGlobal)) ...[
            const SizedBox(height: 10),
            Text(
              'Tema inválido detectado. O app vai cair no UAI Clássico.',
              style: TextStyle(color: t.warning, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLogoDinamicaCard(
    BuildContext context,
    UaiThemeTokens previewTokens,
  ) {
    final t = context.uai;
    final themeId = _draft.temaPadraoGlobal.trim().isNotEmpty
        ? _draft.temaPadraoGlobal.trim()
        : 'uai_classico';

    return _buildSectionCard(
      context,
      title: 'Logo dinâmica do tema',
      icon: Icons.auto_awesome_motion_rounded,
      child: AnimatedBuilder(
        animation: UaiLogoService.instance,
        builder: (context, _) {
          final config = UaiLogoService.instance.configForTheme(themeId);
          final hasSlot =
              config.slotUaiAtivo && config.slotUaiUrl.trim().isNotEmpty;
          final hasOrnamento =
              config.ornamentoAtivo && config.ornamentoUrl.trim().isNotEmpty;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ajuste a identidade visual da logo do tema selecionado sem abrir a edição avançada.',
                style: TextStyle(color: t.textSecondary),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.cardAlt,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: t.border),
                ),
                child: Center(
                  child: UaiDynamicLogo(
                    height: 132,
                    padding: EdgeInsets.zero,
                    themeOverride: previewTokens,
                    logoConfig: config,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _accessiblePreviewPill(
                    label: config.ativo ? 'Config. ativa' : 'Padrão automático',
                    accent: config.ativo ? t.primary : t.warning,
                    baseSurface: t.card,
                  ),
                  _accessiblePreviewPill(
                    label: config.usarLogoPersonalizada
                        ? 'Personalizada'
                        : 'Sem override',
                    accent: config.usarLogoPersonalizada ? t.info : t.border,
                    baseSurface: t.card,
                  ),
                  if (hasSlot)
                    _accessiblePreviewPill(
                      label: 'UAI interno',
                      accent: t.success,
                      baseSurface: t.card,
                    ),
                  if (hasOrnamento)
                    _accessiblePreviewPill(
                      label: 'Ornamento',
                      accent: t.info,
                      baseSurface: t.card,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Tema em edição: $themeId',
                style: TextStyle(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => UaiLogoEditorScreen(
                                  themeId: themeId,
                                  previewTokens: previewTokens,
                                ),
                              ),
                            );
                            if (!mounted) return;
                            await UaiLogoService.instance.loadForTheme(
                              themeId,
                              force: true,
                            );
                            if (mounted) setState(() {});
                          },
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Personalizar logo deste tema'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRegrasCard(BuildContext context) {
    final t = context.uai;
    return _buildSectionCard(
      context,
      title: 'Regras de aplicação',
      icon: Icons.toggle_on_rounded,
      child: Column(
        children: [
          _buildSwitchRow(
            context,
            title: 'Ativar configuração global',
            subtitle:
                'Quando desligado, o app usa a configuração local segura.',
            value: _draft.ativo,
            accent: t.primary,
            onChanged: (value) => setState(() {
              _draft = _draft.copyWith(ativo: value);
              _dirty = true;
            }),
          ),
          const SizedBox(height: 8),
          _buildSwitchRow(
            context,
            title: 'Forçar tema global para todos',
            subtitle:
                'Quando ativado, todos os usuários veem o tema global mesmo com escolha própria.',
            value: _draft.forcarTemaGlobal,
            accent: t.warning,
            onChanged: (value) => setState(() {
              _draft = _draft.copyWith(forcarTemaGlobal: value);
              _dirty = true;
            }),
          ),
          const SizedBox(height: 8),
          _buildSwitchRow(
            context,
            title: 'Permitir que usuários escolham tema',
            subtitle:
                'Quando desativado, a seleção do usuário fica bloqueada pela administração.',
            value: _draft.permitirUsuarioEscolher,
            accent: t.info,
            onChanged: (value) => setState(() {
              _draft = _draft.copyWith(permitirUsuarioEscolher: value);
              _dirty = true;
            }),
          ),
          if (!_draft.permitirUsuarioEscolher || _draft.forcarTemaGlobal) ...[
            const SizedBox(height: 10),
            Text(
              _draft.forcarTemaGlobal
                  ? 'O tema global está ativo para todos os usuários no momento.'
                  : 'A escolha de tema está controlada pela administração no momento.',
              style: TextStyle(color: t.warning, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTemasDisponiveisCard(BuildContext context) {
    final t = context.uai;
    final allowed = _draft.temasDisponiveisUsuario.toSet();

    return _buildSectionCard(
      context,
      title: 'Temas disponíveis para usuários',
      icon: Icons.view_list_rounded,
      child: Column(
        children: [
          for (final preset in UaiThemePresetX.officialPresets) ...[
            _ThemeOptionRow(
              preset: preset,
              selected: preset == UaiThemePreset.uaiClassico
                  ? true
                  : allowed.contains(preset.id),
              locked: preset == UaiThemePreset.uaiClassico,
              onTap: preset == UaiThemePreset.uaiClassico
                  ? () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'O UAI Clássico é o tema de segurança do app e sempre ficará disponível.',
                          ),
                          backgroundColor: t.warning,
                        ),
                      );
                    }
                  : () {
                      setState(() {
                        final next = _draft.temasDisponiveisUsuario.toList(
                          growable: true,
                        );
                        if (allowed.contains(preset.id)) {
                          next.remove(preset.id);
                        } else {
                          next.add(preset.id);
                        }
                        _draft = _draft.copyWith(temasDisponiveisUsuario: next);
                        _dirty = true;
                      });
                    },
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildCloudGlobalThemesCard(BuildContext context) {
    final t = context.uai;
    return _buildSectionCard(
      context,
      title: 'Temas globais da nuvem',
      icon: Icons.cloud_sync_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Crie temas personalizados para disponibilizar a todos os usuários do app.',
            style: TextStyle(color: t.textSecondary, height: 1.3),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => _openCloudThemeForm(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Criar tema global'),
            ),
          ),
          const SizedBox(height: 14),
          FutureBuilder<List<CloudGlobalTheme>>(
            future: CloudGlobalThemeService.instance.listAllForAdmin(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return _buildErrorCard(
                  context,
                  _friendlyCloudThemeError(snapshot.error!),
                );
              }

              final themes = snapshot.data ?? const <CloudGlobalTheme>[];
              if (themes.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: t.cardAlt,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: t.border),
                  ),
                  child: Text(
                    'Nenhum tema global da nuvem cadastrado.',
                    style: TextStyle(color: t.textSecondary),
                  ),
                );
              }

              return Column(
                children: [
                  for (final theme in themes) ...[
                    _CloudGlobalThemeCard(
                      theme: theme,
                      onEdit: () => _openCloudThemeForm(theme: theme),
                      onToggleActive: () => _toggleCloudThemeActive(theme),
                      onArchive: () => _archiveCloudTheme(theme),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCampanhaCard(BuildContext context) {
    final t = context.uai;
    return _buildSectionCard(
      context,
      title: 'Modo campanha',
      icon: Icons.campaign_rounded,
      child: Column(
        children: [
          _buildSwitchRow(
            context,
            title: 'Ativar modo campanha',
            subtitle: 'Registra apenas o estado e o nome da campanha visual.',
            value: _draft.modoCampanha,
            accent: t.primary,
            onChanged: (value) => setState(() {
              _draft = _draft.copyWith(modoCampanha: value);
              _dirty = true;
            }),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _campanhaController,
            onChanged: (_) => setState(() => _dirty = true),
            decoration: const InputDecoration(
              labelText: 'Nome da campanha',
              hintText: 'Setembro Amarelo, Natal, Copa Brasil...',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final t = context.uai;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: _saving ? null : _salvar,
          icon: _saving
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _readableOn(t.primary),
                  ),
                )
              : const Icon(Icons.save_rounded),
          label: const Text('Salvar configuração'),
        ),
        OutlinedButton.icon(
          onPressed: _saving ? null : _restaurarUaiClassico,
          icon: const Icon(Icons.restart_alt_rounded),
          label: const Text('Restaurar UAI Clássico'),
        ),
        TextButton.icon(
          onPressed: _saving ? null : _reload,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Recarregar do Firebase'),
        ),
        if (!TemaGlobalService.instance.documentExists)
          FilledButton.tonalIcon(
            onPressed: _saving ? null : _criarPadrao,
            icon: const Icon(Icons.add_circle_outline_rounded),
            label: const Text('Criar configuração padrão'),
          ),
      ],
    );
  }

  Widget _buildMissingDocCard(BuildContext context) {
    final t = context.uai;
    final user = FirebaseAuth.instance.currentUser;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: t.info),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ainda não existe um documento de tema global. Você pode criar a configuração padrão agora.',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving || user == null ? null : _criarPadrao,
            icon: const Icon(Icons.add_circle_outline_rounded),
            label: const Text('Criar configuração padrão'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context, String error) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(t.error.withAlpha(26), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.error.withAlpha(64)),
      ),
      child: Text(
        _friendlyError(error),
        style: TextStyle(color: t.error, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    final t = context.uai;
    return Scaffold(
      backgroundColor: t.background,
      body: Center(child: CircularProgressIndicator(color: t.primary)),
    );
  }

  Widget _buildDenied(BuildContext context) {
    final t = context.uai;
    return Scaffold(
      backgroundColor: t.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, color: t.error, size: 48),
              const SizedBox(height: 12),
              Text(
                'Você não tem acesso à Central de Temas.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final t = context.uai;
    final accent = _safeAccent(t.primary, t.card);
    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: t.border),
          boxShadow: t.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      accent.withAlpha(31),
                      t.cardAlt,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accent, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchRow(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required Color accent,
    required ValueChanged<bool> onChanged,
  }) {
    final t = context.uai;
    final bg = Color.alphaBlend(accent.withAlpha(20), t.cardAlt);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(color: t.textSecondary, height: 1.25),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch.adaptive(
                value: value,
                onChanged: onChanged,
                activeThumbColor: switch (Theme.of(context).platform) {
                  TargetPlatform.iOS || TargetPlatform.macOS => null,
                  _ => accent,
                },
                activeTrackColor: switch (Theme.of(context).platform) {
                  TargetPlatform.iOS || TargetPlatform.macOS => accent,
                  _ => null,
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewBadge({
    required String texto,
    required Color accent,
    required UaiThemeTokens tokens,
    required Color background,
  }) {
    final safeAccent = _safePreviewAccent(accent, background);
    final chipBg = _softPreviewBg(safeAccent, tokens.cardAlt);
    final onChip = _previewTextOn(chipBg);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: chipBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _safePreviewAccent(safeAccent, chipBg).withAlpha(82),
        ),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: onChip,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  UaiThemeTokens _tokensDoTemaSelecionado() {
    return AppTheme.tokensFor(UaiThemePresetX.fromId(_draft.temaPadraoGlobal));
  }

  double _maxWidthFor(double width) {
    if (width >= 1600) return 1460;
    if (width >= 1180) return 1320;
    if (width >= 900) return 1080;
    return width;
  }

  EdgeInsets _pagePaddingFor(double width) {
    if (width >= 1180) return const EdgeInsets.fromLTRB(24, 18, 24, 32);
    if (width >= 900) return const EdgeInsets.fromLTRB(18, 16, 18, 28);
    return const EdgeInsets.fromLTRB(16, 14, 16, 28);
  }

  Color _previewReadableOn(Color background) {
    return background.computeLuminance() > 0.50
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _previewEnsureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance())
        .abs();
    if (diff >= 0.22) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness(bgIsDark ? 0.74 : 0.30)
        .withSaturation((hsl.saturation + 0.08).clamp(0.0, 1.0))
        .toColor();
  }

  Color _safeAccent(Color color, Color background) {
    return _previewEnsureVisible(color, background);
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }



  Gradient _safeHeaderGradient(UaiThemeTokens theme) {
    final header = _safeHeaderBg(theme);
    return LinearGradient(
      colors: [
        Color.alphaBlend(header.withAlpha(209), theme.background),
        header,
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  Color _safeHeaderBg(UaiThemeTokens theme) {
    final primary = theme.primary;
    if (_temaPrimarioMuitoClaroEmFundoEscuro(primary, theme.background)) {
      return Color.alphaBlend(primary.withAlpha(133), theme.surface);
    }
    return primary;
  }

  Color _safeAppBarBg(UaiThemeTokens t) {
    final primary = t.primary;
    if (_temaPrimarioMuitoClaroEmFundoEscuro(primary, t.background)) {
      return Color.alphaBlend(primary.withAlpha(140), t.surface);
    }
    return primary;
  }

  bool _temaPrimarioMuitoClaroEmFundoEscuro(Color primary, Color surface) {
    final hsl = HSLColor.fromColor(primary);
    return primary.computeLuminance() > 0.50 &&
        surface.computeLuminance() < 0.36 &&
        hsl.saturation > 0.58;
  }

  String _friendlyCloudThemeError(Object error) {
    debugPrint('[CentralTemasScreen] Erro em tema global da nuvem: $error');

    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'Você não tem permissão para gerenciar temas globais.';
        case 'unavailable':
        case 'deadline-exceeded':
          return 'Não foi possível conectar ao Firebase agora. Verifique a conexão e tente novamente.';
        default:
          return 'Não foi possível gerenciar o tema global agora.';
      }
    }

    final text = error.toString();
    if (text.contains('permission-denied')) {
      return 'Você não tem permissão para gerenciar temas globais.';
    }
    if (text.contains('unavailable') ||
        text.contains('deadline-exceeded') ||
        text.contains('channel')) {
      return 'Não foi possível conectar ao Firebase agora. Verifique a conexão e tente novamente.';
    }
    return 'Não foi possível gerenciar o tema global agora.';
  }

  String _friendlyError(Object error) {
    debugPrint('[CentralTemasScreen] Erro ao salvar Central de Temas: $error');

    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'Você não tem permissão para alterar a Central de Temas.';
        case 'unavailable':
        case 'deadline-exceeded':
          return 'Não foi possível conectar ao Firebase agora. Verifique a conexão e tente novamente.';
        default:
          return 'Não foi possível salvar a Central de Temas agora.';
      }
    }

    final text = error.toString();
    if (text.contains('permission-denied')) {
      return 'Você não tem permissão para alterar a Central de Temas.';
    }
    if (text.contains('unavailable') ||
        text.contains('deadline-exceeded') ||
        text.contains('channel')) {
      return 'Não foi possível conectar ao Firebase agora. Verifique a conexão e tente novamente.';
    }
    if (text.contains('cloud_firestore') || text.contains('functions')) {
      return 'Não foi possível salvar a Central de Temas agora.';
    }
    return text.replaceFirst('Exception: ', '').trim();
  }
}

class _CloudGlobalThemeCard extends StatelessWidget {
  final CloudGlobalTheme theme;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onArchive;

  const _CloudGlobalThemeCard({
    required this.theme,
    required this.onEdit,
    required this.onToggleActive,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final tokens = theme.toTokens();
    final updated = theme.atualizadoEm == null
        ? 'Sem atualização registrada'
        : '${theme.atualizadoEm!.day.toString().padLeft(2, '0')}/${theme.atualizadoEm!.month.toString().padLeft(2, '0')}/${theme.atualizadoEm!.year}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: theme.previewColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: t.border),
                ),
                child: Icon(
                  Icons.palette_rounded,
                  color: _previewReadableOn(theme.previewColor),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      theme.nome,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (theme.descricao.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        theme.descricao,
                        style: TextStyle(color: t.textSecondary, height: 1.25),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _PreviewPill(
                          label: theme.ativo ? 'Ativo' : 'Inativo',
                          foreground: _strongTextOn(
                            theme.ativo ? t.success : t.warning,
                          ),
                          background: Color.alphaBlend(
                            (theme.ativo ? t.success : t.warning).withValues(
                              alpha: 0.18,
                            ),
                            t.card,
                          ),
                          border: (theme.ativo ? t.success : t.warning)
                              .withValues(alpha: 0.35),
                        ),
                        _PreviewPill(
                          label: theme.disponivelParaUsuarios
                              ? 'Usuários'
                              : 'Usuários bloqueados',
                          foreground: t.textPrimary,
                          background: t.card,
                          border: t.border,
                        ),
                        _PreviewPill(
                          label: theme.disponivelParaEstudos
                              ? 'Estudos'
                              : 'Estudos bloqueado',
                          foreground: t.textPrimary,
                          background: t.card,
                          border: t.border,
                        ),
                        _PreviewPill(
                          label: theme.origem,
                          foreground: t.textPrimary,
                          background: t.card,
                          border: t.border,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _colorDot('Primary', theme.primary, t),
              if (theme.accent != null) _colorDot('Accent', theme.accent!, t),
              _colorDot('Background', theme.background, t),
              _colorDot('Card', theme.card, t),
              _colorDot('Texto', theme.textPrimary, t),
              if (theme.border != null) _colorDot('Borda', theme.border!, t),
            ],
          ),
          const SizedBox(height: 12),
          _CloudThemeMiniPreview(tokens: tokens),
          const SizedBox(height: 10),
          Text(updated, style: TextStyle(color: t.textMuted, fontSize: 12)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Editar'),
              ),
              FilledButton.tonalIcon(
                onPressed: onToggleActive,
                icon: Icon(
                  theme.ativo ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                label: Text(theme.ativo ? 'Desativar' : 'Ativar'),
              ),
              TextButton.icon(
                onPressed: onArchive,
                icon: const Icon(Icons.archive_rounded),
                label: const Text('Arquivar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _colorDot(String label, Color color, UaiThemeTokens t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: t.border),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: t.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _CloudThemeMiniPreview extends StatelessWidget {
  final UaiThemeTokens tokens;

  const _CloudThemeMiniPreview({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Prévia do tema',
            style: TextStyle(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Texto secundário e superfície do card.',
            style: TextStyle(color: tokens.textSecondary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () {},
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.primary,
                    foregroundColor: _strongTextOn(tokens.primary),
                  ),
                  child: const Text('Botão'),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tokens.accent,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tokens.success,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tokens.error,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CloudThemeFormResult {
  final String nome;
  final String descricao;
  final bool ativo;
  final bool disponivelParaUsuarios;
  final bool disponivelParaEstudos;
  final UserThemeSettings settings;
  final Color success;
  final Color warning;
  final Color error;

  const _CloudThemeFormResult({
    required this.nome,
    required this.descricao,
    required this.ativo,
    required this.disponivelParaUsuarios,
    required this.disponivelParaEstudos,
    required this.settings,
    required this.success,
    required this.warning,
    required this.error,
  });
}

class _CloudThemeFormDialog extends StatefulWidget {
  final CloudGlobalTheme? theme;

  const _CloudThemeFormDialog({this.theme});

  @override
  State<_CloudThemeFormDialog> createState() => _CloudThemeFormDialogState();
}

class _CloudThemeFormDialogState extends State<_CloudThemeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _random = math.Random();
  late final TextEditingController _nome;
  late final TextEditingController _descricao;
  late final TextEditingController _primary;
  late final TextEditingController _accent;
  late final TextEditingController _background;
  late final TextEditingController _card;
  late final TextEditingController _textPrimary;
  late final TextEditingController _textSecondary;
  late final TextEditingController _border;
  late final TextEditingController _success;
  late final TextEditingController _warning;
  late final TextEditingController _error;
  late bool _ativo;
  late bool _usuarios;
  late bool _estudos;
  late bool _dark;

  @override
  void initState() {
    super.initState();
    final theme = widget.theme;
    final defaults =
        theme?.toUserThemeSettings() ?? UserThemeSettings.defaultDark;
    _nome = TextEditingController(text: theme?.nome ?? '');
    _descricao = TextEditingController(text: theme?.descricao ?? '');
    _primary = TextEditingController(text: _hex(defaults.primary));
    _accent = TextEditingController(
      text: _hex(
        defaults.accent ?? UaiThemeTokens.lighten(defaults.primary, 0.18),
      ),
    );
    _background = TextEditingController(text: _hex(defaults.background));
    _card = TextEditingController(text: _hex(defaults.card));
    _textPrimary = TextEditingController(text: _hex(defaults.textPrimary));
    _textSecondary = TextEditingController(
      text: _hex(defaults.textSecondary ?? const Color(0xFFD5DAEA)),
    );
    _border = TextEditingController(
      text: _hex(defaults.border ?? const Color(0xFF3E4260)),
    );
    _success = TextEditingController(
      text: _hex(theme?.success ?? const Color(0xFF35D07F)),
    );
    _warning = TextEditingController(
      text: _hex(theme?.warning ?? const Color(0xFFE8B451)),
    );
    _error = TextEditingController(
      text: _hex(theme?.error ?? const Color(0xFFFF4D5E)),
    );
    _ativo = theme?.ativo ?? true;
    _usuarios = theme?.disponivelParaUsuarios ?? false;
    _estudos = theme?.disponivelParaEstudos ?? false;
    _dark = theme?.isDark ?? true;
  }

  @override
  void dispose() {
    _nome.dispose();
    _descricao.dispose();
    _primary.dispose();
    _accent.dispose();
    _background.dispose();
    _card.dispose();
    _textPrimary.dispose();
    _textSecondary.dispose();
    _border.dispose();
    _success.dispose();
    _warning.dispose();
    _error.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final settings = _settingsFromControllers();
    final preview = UaiThemeTokens.custom(
      primary: settings.primary,
      accent: settings.accent,
      background: settings.background,
      surface: settings.surface,
      card: settings.card,
      textPrimary: settings.textPrimary,
      textSecondary: settings.textSecondary,
      border: settings.border,
      success: _parseColor(_success.text) ?? const Color(0xFF35D07F),
      warning: _parseColor(_warning.text) ?? const Color(0xFFE8B451),
      error: _parseColor(_error.text) ?? const Color(0xFFFF4D5E),
    );
    final contrastWarning = _hasLowContrast(preview);

    return AlertDialog(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      title: Text(
        widget.theme == null ? 'Criar tema global' : 'Editar tema global',
      ),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nome,
                  decoration: const InputDecoration(labelText: 'Nome'),
                  validator: _required,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _descricao,
                  decoration: const InputDecoration(labelText: 'Descrição'),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                      label: const Text('Tema escuro'),
                      selected: _dark,
                      onSelected: _applyDarkDefaults,
                    ),
                    FilterChip(
                      label: const Text('Ativo'),
                      selected: _ativo,
                      onSelected: (v) => setState(() => _ativo = v),
                    ),
                    FilterChip(
                      label: const Text('Disponível para usuários'),
                      selected: _usuarios,
                      onSelected: (v) => setState(() => _usuarios = v),
                    ),
                    FilterChip(
                      label: const Text('Disponível para Estudos'),
                      selected: _estudos,
                      onSelected: (v) => setState(() => _estudos = v),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _generateMagicTheme,
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: const Text('Varinha mágica'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _colorField(_primary, 'Primary'),
                    _colorField(_accent, 'Accent'),
                    _colorField(_background, 'Background'),
                    _colorField(_card, 'Card'),
                    _colorField(_textPrimary, 'Texto principal'),
                    _colorField(_textSecondary, 'Texto secundário'),
                    _colorField(_border, 'Borda'),
                    _colorField(_success, 'Sucesso'),
                    _colorField(_warning, 'Aviso'),
                    _colorField(_error, 'Erro'),
                  ],
                ),
                const SizedBox(height: 14),
                _CloudThemeMiniPreview(tokens: preview),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _paletteDot(preview.primary),
                    _paletteDot(preview.accent),
                    _paletteDot(preview.background),
                    _paletteDot(preview.card),
                    _paletteDot(preview.textPrimary),
                    _paletteDot(preview.textSecondary),
                    _paletteDot(preview.success),
                    _paletteDot(preview.warning),
                    _paletteDot(preview.error),
                  ],
                ),
                if (contrastWarning) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: t.warning,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Atenção: o texto principal pode ficar pouco legível nesse card.',
                          style: TextStyle(
                            color: t.warning,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.save_rounded),
          label: const Text('Salvar'),
        ),
      ],
    );
  }

  Widget _paletteDot(Color color) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: _readableOn(color).withValues(alpha: 0.35)),
      ),
    );
  }

  Widget _colorField(TextEditingController controller, String label) {
    final color = _parseColor(controller.text) ?? Colors.grey;
    return SizedBox(
      width: 180,
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Tooltip(
            message: 'Selecionar cor',
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _pickThemeColor(controller, label),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _readableOn(color).withValues(alpha: 0.35),
                    ),
                  ),
                  child: const SizedBox(width: 18, height: 18),
                ),
              ),
            ),
          ),
          suffixIcon: IconButton(
            tooltip: 'Abrir seletor visual',
            icon: const Icon(Icons.colorize_rounded),
            onPressed: () => _pickThemeColor(controller, label),
          ),
        ),
        validator: _validColor,
        textCapitalization: TextCapitalization.characters,
        onChanged: (value) {
          final parsed = _parseColor(value);
          if (parsed != null) {
            controller.value = TextEditingValue(
              text: _hex(parsed),
              selection: TextSelection.collapsed(offset: _hex(parsed).length),
            );
          }
          setState(() {});
        },
      ),
    );
  }

  Future<void> _pickThemeColor(
    TextEditingController controller,
    String label,
  ) async {
    final initial = _parseColor(controller.text) ?? Colors.grey;
    final selected = await showDialog<Color>(
      context: context,
      builder: (context) =>
          _ThemeColorPickerDialog(title: label, initialColor: initial),
    );
    if (selected == null) return;
    setState(() => controller.text = _hex(selected));
  }

  void _generateMagicTheme() {
    final families = [
      'Capoeira Terra',
      'Mata Noturna',
      'Dourado Elegante',
      'Urbana Neon',
      'Pergaminho',
      'Bordô Premium',
      'Azul Cerimonial',
      'Infantil Alegre',
    ];
    final family = families[_random.nextInt(families.length)];
    final dark = _dark;
    final hue = _random.nextDouble() * 360;
    final accentHue = (hue + 35 + _random.nextDouble() * 55) % 360;
    final primary = HSLColor.fromAHSL(
      1,
      hue,
      0.58 + _random.nextDouble() * 0.18,
      dark ? 0.56 : 0.38,
    ).toColor();
    final accent = HSLColor.fromAHSL(
      1,
      accentHue,
      0.62 + _random.nextDouble() * 0.16,
      dark ? 0.62 : 0.44,
    ).toColor();
    final background = dark
        ? HSLColor.fromAHSL(
            1,
            hue,
            0.20,
            0.07 + _random.nextDouble() * 0.04,
          ).toColor()
        : HSLColor.fromAHSL(
            1,
            hue,
            0.20,
            0.94 + _random.nextDouble() * 0.03,
          ).toColor();
    final card = dark
        ? HSLColor.fromAHSL(
            1,
            hue,
            0.18,
            0.14 + _random.nextDouble() * 0.05,
          ).toColor()
        : HSLColor.fromAHSL(1, hue, 0.16, 0.985).toColor();
    final border = dark
        ? HSLColor.fromAHSL(1, hue, 0.20, 0.27).toColor()
        : HSLColor.fromAHSL(1, hue, 0.15, 0.84).toColor();
    final textPrimary = dark
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF111827);
    final textSecondary = dark
        ? const Color(0xFFD5DAEA)
        : const Color(0xFF4B5563);

    setState(() {
      _primary.text = _hex(primary);
      _accent.text = _hex(accent);
      _background.text = _hex(background);
      _card.text = _hex(card);
      _textPrimary.text = _hex(textPrimary);
      _textSecondary.text = _hex(textSecondary);
      _border.text = _hex(border);
      _success.text = _hex(
        HSLColor.fromAHSL(1, 145, 0.62, dark ? 0.55 : 0.35).toColor(),
      );
      _warning.text = _hex(
        HSLColor.fromAHSL(1, 42, 0.82, dark ? 0.60 : 0.45).toColor(),
      );
      _error.text = _hex(
        HSLColor.fromAHSL(1, 352, 0.76, dark ? 0.62 : 0.48).toColor(),
      );
      if (_nome.text.trim().isEmpty) _nome.text = family;
      if (_descricao.text.trim().isEmpty) {
        _descricao.text = dark
            ? 'Tema escuro gerado para o app.'
            : 'Tema claro gerado para o app.';
      }
    });
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.pop(
      context,
      _CloudThemeFormResult(
        nome: _nome.text.trim(),
        descricao: _descricao.text.trim(),
        ativo: _ativo,
        disponivelParaUsuarios: _usuarios,
        disponivelParaEstudos: _estudos,
        settings: _settingsFromControllers(),
        success: _parseColor(_success.text) ?? const Color(0xFF35D07F),
        warning: _parseColor(_warning.text) ?? const Color(0xFFE8B451),
        error: _parseColor(_error.text) ?? const Color(0xFFFF4D5E),
      ),
    );
  }

  UserThemeSettings _settingsFromControllers() {
    return UserThemeSettings(
      primary:
          _parseColor(_primary.text) ?? UserThemeSettings.defaultDark.primary,
      accent: _parseColor(_accent.text),
      background:
          _parseColor(_background.text) ??
          UserThemeSettings.defaultDark.background,
      surface: _parseColor(_card.text) ?? UserThemeSettings.defaultDark.surface,
      card: _parseColor(_card.text) ?? UserThemeSettings.defaultDark.card,
      textPrimary:
          _parseColor(_textPrimary.text) ??
          UserThemeSettings.defaultDark.textPrimary,
      textSecondary: _parseColor(_textSecondary.text),
      border: _parseColor(_border.text),
    );
  }

  void _applyDarkDefaults(bool value) {
    setState(() {
      _dark = value;
      if (value) {
        _background.text = '#07100B';
        _card.text = '#142219';
        _textPrimary.text = '#F4F0D8';
        _textSecondary.text = '#D5DAEA';
        _border.text = '#3E4260';
      } else {
        _background.text = '#F8FAFC';
        _card.text = '#FFFFFF';
        _textPrimary.text = '#111827';
        _textSecondary.text = '#4B5563';
        _border.text = '#E5E7EB';
      }
    });
  }

  bool _hasLowContrast(UaiThemeTokens tokens) {
    return _contrast(tokens.textPrimary, tokens.card) < 2.6 ||
        _contrast(tokens.textPrimary, tokens.background) < 2.6;
  }

  double _contrast(Color a, Color b) {
    final high = math.max(a.computeLuminance(), b.computeLuminance());
    final low = math.min(a.computeLuminance(), b.computeLuminance());
    return (high + 0.05) / (low + 0.05);
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Informe um nome.' : null;

  String? _validColor(String? value) =>
      _parseColor(value) == null ? 'Use HEX. Ex: #547A3B' : null;

  static Color? _parseColor(String? raw) {
    if (raw == null) return null;
    var value = raw
        .trim()
        .replaceAll('#', '')
        .replaceAll('0x', '')
        .replaceAll('0X', '');
    if (value.length != 6) return null;
    final parsed = int.tryParse('FF$value', radix: 16);
    return parsed == null ? null : Color(parsed);
  }

  static String _hex(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  static Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }
}

class _ThemeColorPickerDialog extends StatefulWidget {
  final String title;
  final Color initialColor;

  const _ThemeColorPickerDialog({
    required this.title,
    required this.initialColor,
  });

  @override
  State<_ThemeColorPickerDialog> createState() =>
      _ThemeColorPickerDialogState();
}

class _ThemeColorPickerDialogState extends State<_ThemeColorPickerDialog> {
  late Color _color;
  late final TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _color = widget.initialColor.withAlpha(255);
    _hexController = TextEditingController(text: _hex(_color));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    const pickerWidth = 320.0;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.transparent,
      child: FractionallySizedBox(
        widthFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
          child: Material(
            color: t.surface,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Cor: ${widget.title}',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: _hexController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'HEX',
                              hintText: '#547A3B',
                            ),
                            onChanged: (value) {
                              final parsed = _parseColor(value);
                              if (parsed == null) return;
                              setState(() => _color = parsed);
                            },
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.center,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: pickerWidth,
                              ),
                              child: ColorPicker(
                                pickerColor: _color,
                                enableAlpha: false,
                                hexInputBar: false,
                                labelTypes: const [],
                                displayThumbColor: true,
                                portraitOnly: true,
                                colorPickerWidth: pickerWidth,
                                pickerAreaHeightPercent: 0.72,
                                onColorChanged: (color) {
                                  final opaque = color.withAlpha(255);
                                  setState(() {
                                    _color = opaque;
                                    _hexController.text = _hex(opaque);
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, _color.withAlpha(255)),
                        child: const Text('Aplicar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Color? _parseColor(String? raw) {
    if (raw == null) return null;
    var value = raw
        .trim()
        .replaceAll('#', '')
        .replaceAll('0x', '')
        .replaceAll('0X', '');
    if (value.length != 6) return null;
    final parsed = int.tryParse('FF$value', radix: 16);
    return parsed == null ? null : Color(parsed);
  }

  static String _hex(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }
}

class _ThemeSpeedDialAction {
  final IconData icon;
  final String label;
  final String tooltip;
  final bool enabled;
  final bool emphasized;
  final FutureOr<void> Function() onPressed;

  const _ThemeSpeedDialAction({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.enabled = true,
    this.emphasized = false,
  });
}

class _ThemeSpeedDial extends StatelessWidget {
  final bool open;
  final bool dirty;
  final bool saving;
  final VoidCallback onToggle;
  final List<_ThemeSpeedDialAction> actions;

  const _ThemeSpeedDial({
    required this.open,
    required this.dirty,
    required this.saving,
    required this.onToggle,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final availableWidth = media.size.width - media.padding.horizontal - 32;
    final maxLabelWidth = availableWidth < 340 ? availableWidth - 72 : 230.0;

    return Semantics(
      container: true,
      label: 'Menu de atalhos da Central de Temas',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IgnorePointer(
            ignoring: !open,
            child: AnimatedOpacity(
              opacity: open ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: AnimatedSlide(
                offset: open ? Offset.zero : const Offset(0, 0.08),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: AnimatedScale(
                  scale: open ? 1 : 0.96,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.bottomRight,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: availableWidth),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final action in actions.reversed) ...[
                          _SpeedDialActionButton(
                            action: action,
                            maxLabelWidth: maxLabelWidth.clamp(128.0, 230.0),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Tooltip(
            message: open ? 'Fechar atalhos' : 'Abrir atalhos da Central',
            child: Semantics(
              button: true,
              toggled: open,
              label: open ? 'Fechar atalhos' : 'Abrir atalhos da Central',
              child: _SpeedDialMainButton(
                open: open,
                dirty: dirty,
                saving: saving,
                onPressed: onToggle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedDialMainButton extends StatelessWidget {
  final bool open;
  final bool dirty;
  final bool saving;
  final VoidCallback onPressed;

  const _SpeedDialMainButton({
    required this.open,
    required this.dirty,
    required this.saving,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final bg = dirty && !saving
        ? _previewEnsureVisible(t.warning, t.background)
        : _previewEnsureVisible(t.primary, t.background);
    final fg = _strongTextOn(bg);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: bg,
          elevation: open ? 10 : 7,
          shadowColor: Colors.black.withValues(alpha: 0.24),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 58,
              height: 58,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: saving
                      ? SizedBox(
                          key: const ValueKey('saving'),
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            valueColor: AlwaysStoppedAnimation<Color>(fg),
                          ),
                        )
                      : AnimatedRotation(
                          key: ValueKey(open ? 'close' : 'settings'),
                          turns: open ? 0.125 : 0,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            open ? Icons.close_rounded : Icons.settings_rounded,
                            color: fg,
                            size: 28,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
        if (dirty && !saving)
          Positioned(
            right: 2,
            top: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.error,
                shape: BoxShape.circle,
                border: Border.all(color: t.background, width: 2),
              ),
              child: const SizedBox(width: 15, height: 15),
            ),
          ),
      ],
    );
  }
}

class _SpeedDialActionButton extends StatelessWidget {
  final _ThemeSpeedDialAction action;
  final double maxLabelWidth;

  const _SpeedDialActionButton({
    required this.action,
    required this.maxLabelWidth,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final baseAccent = action.emphasized ? t.warning : t.primary;
    final accent = _previewEnsureVisible(baseAccent, t.background);
    final buttonBg = action.enabled
        ? accent
        : Color.alphaBlend(t.textSecondary.withValues(alpha: 0.12), t.card);
    final buttonFg = action.enabled ? _strongTextOn(buttonBg) : t.textSecondary;
    final labelBg = Color.alphaBlend(
      t.card.withValues(alpha: 0.94),
      t.background,
    );
    final labelFg = action.enabled ? t.textPrimary : t.textSecondary;

    return Tooltip(
      message: action.tooltip,
      child: Semantics(
        button: true,
        enabled: action.enabled,
        label: action.tooltip,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxLabelWidth),
                child: Material(
                  color: labelBg,
                  elevation: 5,
                  shadowColor: Colors.black.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: action.enabled ? () => action.onPressed() : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 9,
                      ),
                      child: Text(
                        action.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: labelFg,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: buttonBg,
              elevation: 6,
              shadowColor: Colors.black.withValues(alpha: 0.18),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: action.enabled ? () => action.onPressed() : null,
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: Icon(action.icon, color: buttonFg, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ThemeGlobalDraft {
  final bool ativo;
  final String temaPadraoGlobal;
  final bool forcarTemaGlobal;
  final bool permitirUsuarioEscolher;
  final List<String> temasDisponiveisUsuario;
  final String fallbackTema;
  final bool modoCampanha;
  final String campanhaNome;

  const ThemeGlobalDraft({
    required this.ativo,
    required this.temaPadraoGlobal,
    required this.forcarTemaGlobal,
    required this.permitirUsuarioEscolher,
    required this.temasDisponiveisUsuario,
    required this.fallbackTema,
    required this.modoCampanha,
    required this.campanhaNome,
  });

  factory ThemeGlobalDraft.fromConfig(TemaGlobalConfig config) {
    return ThemeGlobalDraft(
      ativo: config.ativo,
      temaPadraoGlobal: config.temaPadraoGlobal,
      forcarTemaGlobal: config.forcarTemaGlobal,
      permitirUsuarioEscolher: config.permitirUsuarioEscolher,
      temasDisponiveisUsuario: List<String>.from(
        config.temasDisponiveisUsuario,
      ),
      fallbackTema: config.fallbackTema,
      modoCampanha: config.modoCampanha,
      campanhaNome: config.campanhaNome,
    );
  }

  ThemeGlobalDraft copyWith({
    bool? ativo,
    String? temaPadraoGlobal,
    bool? forcarTemaGlobal,
    bool? permitirUsuarioEscolher,
    List<String>? temasDisponiveisUsuario,
    String? fallbackTema,
    bool? modoCampanha,
    String? campanhaNome,
  }) {
    return ThemeGlobalDraft(
      ativo: ativo ?? this.ativo,
      temaPadraoGlobal: temaPadraoGlobal ?? this.temaPadraoGlobal,
      forcarTemaGlobal: forcarTemaGlobal ?? this.forcarTemaGlobal,
      permitirUsuarioEscolher:
          permitirUsuarioEscolher ?? this.permitirUsuarioEscolher,
      temasDisponiveisUsuario:
          temasDisponiveisUsuario ?? this.temasDisponiveisUsuario,
      fallbackTema: fallbackTema ?? this.fallbackTema,
      modoCampanha: modoCampanha ?? this.modoCampanha,
      campanhaNome: campanhaNome ?? this.campanhaNome,
    );
  }

  TemaGlobalConfig toConfig() {
    return TemaGlobalConfig(
      ativo: ativo,
      temaPadraoGlobal: temaPadraoGlobal,
      forcarTemaGlobal: forcarTemaGlobal,
      permitirUsuarioEscolher: permitirUsuarioEscolher,
      temasDisponiveisUsuario: temasDisponiveisUsuario,
      fallbackTema: fallbackTema,
      modoCampanha: modoCampanha,
      campanhaNome: campanhaNome,
      atualizadoEm: null,
      atualizadoPorUid: null,
      atualizadoPorNome: null,
    );
  }
}

class _ThemePreview extends StatelessWidget {
  final UaiThemeTokens theme;

  const _ThemePreview({required this.theme});

  @override
  Widget build(BuildContext context) {
    final onPrimary = _strongTextOn(theme.primary);
    final dangerBg = _accessibleSoftBg(theme.error, theme.cardAlt);
    final dangerFg = _strongTextOn(dangerBg);
    final previewBg = theme.background;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: previewBg,
        borderRadius: BorderRadius.circular(theme.cardRadius),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: theme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.menu_rounded, color: onPrimary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AppBar de prévia',
                    style: TextStyle(
                      color: onPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Icon(Icons.more_vert_rounded, color: onPrimary, size: 18),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.card,
              borderRadius: BorderRadius.circular(theme.cardRadius),
              border: Border.all(color: theme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Texto principal',
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Texto secundário',
                  style: TextStyle(color: theme.textSecondary),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _accessiblePreviewPill(
                      label: 'Sucesso',
                      accent: theme.success,
                      baseSurface: theme.cardAlt,
                    ),
                    _accessiblePreviewPill(
                      label: 'Alerta',
                      accent: theme.warning,
                      baseSurface: theme.cardAlt,
                    ),
                    _accessiblePreviewPill(
                      label: 'Perigo',
                      accent: theme.error,
                      baseSurface: theme.cardAlt,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primary,
                          foregroundColor: onPrimary,
                        ),
                        child: const Text('Primário'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () {},
                        icon: const Icon(Icons.delete_rounded),
                        style: FilledButton.styleFrom(
                          backgroundColor: dangerBg,
                          foregroundColor: dangerFg,
                        ),
                        label: const Text('Perigo'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeOptionRow extends StatelessWidget {
  final UaiThemePreset preset;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  const _ThemeOptionRow({
    required this.preset,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final preview = AppTheme.tokensFor(preset);
    final accent = _previewEnsureVisible(preview.primary, t.card);
    final bg = Color.alphaBlend(accent.withAlpha(23), t.card);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? accent.withAlpha(133) : t.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: selected,
                onChanged: locked ? (_) => onTap() : (_) => onTap(),
                activeColor: accent,
                checkColor: _previewReadableOn(accent),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            preset.label,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (locked)
                          _PreviewPill(
                            label: 'Seguro',
                            foreground: _previewReadableOn(t.warning),
                            background: Color.alphaBlend(
                              t.warning.withAlpha(36),
                              t.cardAlt,
                            ),
                            border: _previewEnsureVisible(
                              t.warning,
                              t.cardAlt,
                            ).withAlpha(77),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      preset.description,
                      style: TextStyle(color: t.textSecondary, height: 1.25),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewPill extends StatelessWidget {
  final String label;
  final Color foreground;
  final Color background;
  final Color border;

  const _PreviewPill({
    required this.label,
    required this.foreground,
    required this.background,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
