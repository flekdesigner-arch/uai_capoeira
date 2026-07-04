import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/permissions/permission_access_guard.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/theme/app_theme_preset.dart';
import 'package:uai_capoeira/core/theme/app_theme_tokens.dart';
import 'package:uai_capoeira/core/theme/app_theme_controller.dart';
import 'package:uai_capoeira/core/theme/tema_global_config.dart';
import 'package:uai_capoeira/core/logo/uai_logo_config.dart';
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
    Color.alphaBlend(accent.withOpacity(0.12), surface);

Color _accessibleSoftBg(Color accent, Color baseSurface) {
  final surfaceIsDark = baseSurface.computeLuminance() < 0.45;
  final hsl = HSLColor.fromColor(accent);
  final strongerAccent = hsl
      .withLightness(surfaceIsDark ? 0.32 : 0.88)
      .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
      .toColor();

  return Color.alphaBlend(
    strongerAccent.withOpacity(surfaceIsDark ? 0.42 : 0.55),
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
    border: border.withOpacity(0.45),
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
  late TextEditingController _campanhaController;
  bool _saving = false;
  bool _dirty = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _accessFuture = _accessGuard.canAccess(
      permission: 'pode_gerenciar_temas_globais',
    );
    _draft = ThemeGlobalDraft.fromConfig(TemaGlobalService.instance.config);
    _campanhaController = TextEditingController(text: _draft.campanhaNome);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _carregarLogoTemaAtual();
    });
  }

  @override
  void dispose() {
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

            return Scaffold(
              backgroundColor: t.background,
              appBar: AppBar(
                title: const Text('Central de Temas'),
                backgroundColor: appBarBg,
                foregroundColor: appBarFg,
                iconTheme: IconThemeData(color: appBarFg),
                actionsIconTheme: IconThemeData(color: appBarFg),
              ),
              body: SafeArea(
                child: RefreshIndicator(
                  onRefresh: _reload,
                  color: previewTokens.primary,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return ListView(
                        padding: pagePadding,
                        children: [
                          Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: maxWidth),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                          child: _buildTemaPadraoCard(
                                            context,
                                            config,
                                            previewTokens,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: _buildRegrasCard(context),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    _buildLogoDinamicaCard(
                                      context,
                                      previewTokens,
                                    ),
                                    const SizedBox(height: 14),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: _buildTemasDisponiveisCard(
                                            context,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: _buildCampanhaCard(context),
                                        ),
                                      ],
                                    ),
                                  ] else ...[
                                    _buildTemaPadraoCard(
                                      context,
                                      config,
                                      previewTokens,
                                    ),
                                    const SizedBox(height: 14),
                                    _buildLogoDinamicaCard(
                                      context,
                                      previewTokens,
                                    ),
                                    const SizedBox(height: 14),
                                    _buildRegrasCard(context),
                                    const SizedBox(height: 14),
                                    _buildTemasDisponiveisCard(context),
                                    const SizedBox(height: 14),
                                    _buildCampanhaCard(context),
                                  ],
                                  const SizedBox(height: 14),
                                  _buildActions(context),
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
                  color: Color.alphaBlend(onHeader.withOpacity(0.10), headerBg),
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
                        color: onHeader.withOpacity(0.90),
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
    final preset = UaiThemePresetX.fromId(_draft.temaPadraoGlobal);
    final preview = previewTokens;

    return _buildSectionCard(
      context,
      title: 'Tema padrão global',
      icon: Icons.hdr_strong_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: UaiThemePresetX.isOfficialId(_draft.temaPadraoGlobal)
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
        color: Color.alphaBlend(t.error.withOpacity(0.10), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.error.withOpacity(0.25)),
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
                      accent.withOpacity(0.12),
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
    final bg = Color.alphaBlend(accent.withOpacity(0.08), t.cardAlt);
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
                activeColor: accent,
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
          color: _safePreviewAccent(safeAccent, chipBg).withOpacity(0.32),
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

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance())
        .abs();
    if (diff >= 0.26) return color;
    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Gradient _safeHeaderGradient(UaiThemeTokens theme) {
    final header = _safeHeaderBg(theme);
    return LinearGradient(
      colors: [
        Color.alphaBlend(header.withOpacity(0.82), theme.background),
        header,
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  Color _safeHeaderBg(UaiThemeTokens theme) {
    final primary = theme.primary;
    if (_temaPrimarioMuitoClaroEmFundoEscuro(primary, theme.background)) {
      return Color.alphaBlend(primary.withOpacity(0.52), theme.surface);
    }
    return primary;
  }

  Color _safeAppBarBg(UaiThemeTokens t) {
    final primary = t.primary;
    if (_temaPrimarioMuitoClaroEmFundoEscuro(primary, t.background)) {
      return Color.alphaBlend(primary.withOpacity(0.55), t.surface);
    }
    return primary;
  }

  bool _temaPrimarioMuitoClaroEmFundoEscuro(Color primary, Color surface) {
    final hsl = HSLColor.fromColor(primary);
    return primary.computeLuminance() > 0.50 &&
        surface.computeLuminance() < 0.36 &&
        hsl.saturation > 0.58;
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('cloud_firestore') ||
        text.contains('functions') ||
        text.contains('channel')) {
      return 'Não foi possível comunicar com o Firebase nesta versão.';
    }
    return text.replaceFirst('Exception: ', '').trim();
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
    final bg = Color.alphaBlend(accent.withOpacity(0.09), t.card);

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
              color: selected ? accent.withOpacity(0.52) : t.border,
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
                              t.warning.withOpacity(0.14),
                              t.cardAlt,
                            ),
                            border: _previewEnsureVisible(
                              t.warning,
                              t.cardAlt,
                            ).withOpacity(0.30),
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
