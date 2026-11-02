// lib/modules/sistema/admin/admin_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admin_panel_organization.dart';
import 'package:uai_capoeira/modules/disciplina/disciplina_admin_screen.dart';
import 'configurar_aniversariantes_screen.dart';
import 'package:uai_capoeira/modules/uniformes/admin/uniformes_configuracoes_screen.dart';

import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/dev_tools/creative_mode/creative_mode_launcher.dart';
import 'package:uai_capoeira/core/permissions/permission_catalog.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/theme/app_theme_tokens.dart';
import 'package:uai_capoeira/modules/graduacoes/admin/gerenciar_graduacoes_screen.dart';
import 'package:uai_capoeira/modules/usuarios/admin/gerenciar_usuarios_screen.dart';
import 'package:uai_capoeira/modules/sistema/migrations/migracao_triagem_screen.dart';
import 'package:uai_capoeira/modules/turmas/admin/gerenciar_academias_screen.dart';
import 'package:uai_capoeira/modules/sistema/migrations/migracao_chamadas_screen.dart';
import 'package:uai_capoeira/modules/sistema/migrations/migracao_eventos_screen.dart';
import 'package:uai_capoeira/modules/eventos/admin/gerenciar_eventos_screen.dart';
import 'package:uai_capoeira/modules/transportes/admin/configurar_transportes_screen.dart';
import 'package:uai_capoeira/modules/sistema/migrations/migracao_participacoes_screen.dart';
import 'package:uai_capoeira/modules/sistema/migrations/migracao_graduacoes_screen.dart';
import 'package:uai_capoeira/modules/site/admin/gerenciar_site_screen.dart';
import 'package:uai_capoeira/modules/site/admin/gerenciar_logo_screen.dart';
import 'package:uai_capoeira/modules/certificados/screens/certificados_admin_screen.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/admin/controle_atualizacoes_screen.dart';
import 'package:uai_capoeira/modules/sistema/admin/indicadores_ausencia_screen.dart';
import 'package:uai_capoeira/modules/sistema/admin/central_temas_screen.dart';
import 'package:uai_capoeira/modules/sistema/firebase_saude/admin/firebase_saude_screen.dart';
import 'package:uai_capoeira/modules/sistema/admin/modo_troll_screen.dart';
import 'package:uai_capoeira/modules/sistema/admin/caca_bug/caca_bug_screen.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/admin/gerenciar_estudos_fundamentos_screen.dart';
import 'package:uai_capoeira/modules/rhythm_studio/studio/rhythm_studio_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final PermissaoService _permissaoService = PermissaoService();
  late Future<_AdminPermissionState> _permissionFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<String> _favoriteIds = <String>[];
  Set<AdminPanelArea> _expandedAreas = {AdminPanelArea.essencial};

  String get _preferencesPrefix {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'sem_sessao';
    return 'uai_admin_painel_181_$uid';
  }

  Future<void> _loadPreferences() async {
    final prefix = _preferencesPrefix;
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedFavorites = preferences.getStringList('${prefix}_favoritos');
      final savedAreas = preferences.getStringList('${prefix}_secoes');
      if (!mounted || prefix != _preferencesPrefix) return;
      setState(() {
        _favoriteIds = savedFavorites ?? <String>[];
        if (savedAreas != null) {
          _expandedAreas = AdminPanelArea.values
              .where((area) => savedAreas.contains(area.name))
              .toSet();
        }
      });
    } catch (_) {
      // Preferências são opcionais; as rotas e permissões continuam operantes.
    }
  }

  Future<void> _saveFavorites() async {
    final prefix = _preferencesPrefix;
    final currentFavorites = List<String>.of(_favoriteIds);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList('${prefix}_favoritos', currentFavorites);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Não foi possível salvar os favoritos neste aparelho.'),
      ));
    }
  }

  Future<void> _saveExpandedAreas() async {
    final prefix = _preferencesPrefix;
    final currentAreas = _expandedAreas.map((area) => area.name).toList();
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList(
        '${prefix}_secoes',
        currentAreas,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Não foi possível salvar a organização das seções.'),
      ));
    }
  }

  void _toggleFavorite(String id, _AdminPermissionState access) {
    final allowedIds = [
      ..._siteCards(context.uai),
      ..._appCards(context.uai),
    ].where((item) => _podeVerCard(item, access)).map((item) => item.id);
    final current = AdminPanelOrganization.safeFavorites(
      saved: _favoriteIds,
      allowed: allowedIds,
    );
    if (!allowedIds.contains(id)) return;
    final alreadyFavorite = current.contains(id);
    if (!alreadyFavorite &&
        current.length >= AdminPanelOrganization.maxFavorites) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Você pode fixar até quatro ferramentas favoritas.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() {
      _favoriteIds = current;
      if (alreadyFavorite) {
        _favoriteIds.remove(id);
      } else {
        _favoriteIds.add(id);
      }
    });
    _saveFavorites();
  }

  void _toggleSection(AdminPanelArea area) {
    setState(() {
      if (!_expandedAreas.add(area)) _expandedAreas.remove(area);
    });
    _saveExpandedAreas();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _permissionFuture = _carregarPermissoes();
    _loadPreferences();
  }

  Future<_AdminPermissionState> _carregarPermissoes() async {
    final results = await Future.wait<dynamic>([
      _permissaoService.usuarioAtualEhAdmin(),
      _permissaoService.getTodasPermissoes(),
    ]);

    return _AdminPermissionState(
      adminMaster: results[0] == true,
      permissions: Map<String, bool>.from(results[1] as Map<String, bool>),
    );
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

  Color _softFill(Color color, Color base, [double opacity = 0.11]) {
    return Color.alphaBlend(color.withValues(alpha: opacity), base);
  }

  bool get _isWideDashboard {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 900;
  }

  bool get _isDesktopDashboard {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 1180;
  }

  double get _dashboardMaxWidth {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1600) return 1460;
    if (width >= 1180) return 1320;
    if (width >= 900) return 1080;
    return width;
  }

  EdgeInsets get _dashboardPagePadding {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1180) return const EdgeInsets.fromLTRB(22, 18, 22, 32);
    if (width >= 900) return const EdgeInsets.fromLTRB(18, 16, 18, 28);
    return const EdgeInsets.fromLTRB(14, 14, 14, 26);
  }

  Widget _dashboardWidthLimiter(Widget child) {
    if (!_isWideDashboard) return child;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _dashboardMaxWidth),
        child: child,
      ),
    );
  }

  int _dashboardColumns(
    double width, {
    double minItemWidth = 360,
    int maxColumns = 4,
  }) {
    if (width <= 0) return 1;
    return (width / minItemWidth).floor().clamp(1, maxColumns);
  }

  Widget _dashboardResponsiveWrap({
    required List<Widget> children,
    double minItemWidth = 360,
    int maxColumns = 4,
    double spacing = 12,
    double runSpacing = 12,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        if (width < 720) {
          return Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                SizedBox(width: double.infinity, child: children[i]),
                if (i != children.length - 1) SizedBox(height: runSpacing),
              ],
            ],
          );
        }

        final columns = _dashboardColumns(
          width,
          minItemWidth: minItemWidth,
          maxColumns: maxColumns,
        );
        final itemWidth = (width - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: children
              .map((child) => SizedBox(width: itemWidth, child: child))
              .toList(),
        );
      },
    );
  }

  bool _temPermissao(_AdminPermissionState access, List<String> permissions) {
    for (final permission in permissions) {
      if (access.permissions[permission] == true) return true;

      for (final definition in PermissionCatalog.all) {
        if (definition.key != permission &&
            !definition.aliases.contains(permission)) {
          continue;
        }

        for (final linkedKey in definition.linkedKeys) {
          if (access.permissions[linkedKey] == true) return true;
        }
      }
    }

    return false;
  }

  bool _podeVerCard(_AdminCardData item, _AdminPermissionState access) {
    if (access.adminMaster) return true;
    if (item.critical && item.adminOnly) return false;
    if (item.adminOnly) return false;
    if (item.permissions.isEmpty) return false;
    return _temPermissao(access, item.permissions);
  }

  bool _podeAbrirMigracoes(_AdminPermissionState access) {
    return access.adminMaster;
  }

  void _mostrarAcessoNegado(BuildContext context, [_AdminCardData? item]) {
    final mensagem =
        item?.deniedMessage ??
        'Você não tem permissão para acessar este módulo.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), behavior: SnackBarBehavior.floating),
    );
  }

  void _abrirTelaProtegida(
    BuildContext context,
    _AdminCardData item,
    _AdminPermissionState access,
  ) {
    if (!_podeVerCard(item, access)) {
      _mostrarAcessoNegado(context, item);
      return;
    }

    Navigator.push(context, MaterialPageRoute(builder: (_) => item.tela));
  }

  void _abrirMigracoes(BuildContext context, _AdminPermissionState access) {
    if (!_podeAbrirMigracoes(access)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Você não tem permissão para executar migrações.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final t = context.uai;

    final migrations = <_MigrationItem>[
      _MigrationItem(
        icon: Icons.people_alt_rounded,
        title: 'Migrar Alunos',
        subtitle: 'Importar ou corrigir dados antigos dos alunos',
        color: t.info,
        tela: MigracaoTriagemScreen(),
        permissions: const ['pode_migrar_alunos'],
        adminOnly: true,
      ),
      _MigrationItem(
        icon: Icons.workspace_premium_rounded,
        title: 'Migrar Graduações',
        subtitle: 'Importar graduações e faixas antigas',
        color: t.warning,
        tela: const MigracaoGraduacoesScreen(),
        permissions: const ['pode_migrar_graduacoes'],
        adminOnly: true,
      ),
      _MigrationItem(
        icon: Icons.history_edu_rounded,
        title: 'Migrar Chamadas',
        subtitle: 'Importar histórico de chamadas e presenças',
        color: t.associacao,
        tela: MigracaoChamadasScreen(),
        permissions: const ['pode_migrar_chamadas'],
        adminOnly: true,
      ),
      _MigrationItem(
        icon: Icons.event_available_rounded,
        title: 'Migrar Eventos',
        subtitle: 'Importar eventos antigos do sistema',
        color: t.success,
        tela: MigracaoEventosScreen(),
        permissions: const ['pode_migrar_eventos'],
        adminOnly: true,
      ),
      _MigrationItem(
        icon: Icons.emoji_events_rounded,
        title: 'Migrar Participações',
        subtitle: 'Importar participantes e vínculos de eventos',
        color: t.warning,
        tela: MigracaoParticipacoesScreen(),
        permissions: const ['pode_migrar_participacoes'],
        adminOnly: true,
      ),
    ];
    final visibleMigrations = migrations
        .where((item) => _podeVerCard(item.asCardData(), access))
        .toList(growable: false);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final t = sheetContext.uai;
        final maxHeight = MediaQuery.of(sheetContext).size.height * 0.84;
        final accent = _ensureVisible(t.primary, t.surface);

        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            constraints: BoxConstraints(maxHeight: maxHeight),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius + 4),
              border: Border.all(color: t.border),
              boxShadow: t.cardShadow,
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: t.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _softFill(accent, t.cardAlt, 0.13),
                          borderRadius: BorderRadius.circular(
                            t.buttonRadius + 1,
                          ),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.16),
                          ),
                        ),
                        child: Icon(Icons.sync_alt_rounded, color: accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ferramentas de Migração',
                              style: TextStyle(
                                color: t.textPrimary,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Importações e correções de dados antigos',
                              style: TextStyle(
                                color: t.textSecondary,
                                fontSize: 12,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: Icon(Icons.close_rounded, color: t.textSecondary),
                        tooltip: 'Fechar',
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: visibleMigrations.isEmpty
                      ? _buildEmptyMigrationState(sheetContext)
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                          itemCount: visibleMigrations.length,
                          itemBuilder: (context, index) {
                            final item = visibleMigrations[index];

                            return _buildMigrationTile(
                              context: sheetContext,
                              item: item,
                              access: access,
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
  }

  Widget _buildMigrationTile({
    required BuildContext context,
    required _MigrationItem item,
    required _AdminPermissionState access,
  }) {
    final t = context.uai;
    final visibleColor = _ensureVisible(item.color, t.card);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: _softFill(visibleColor, t.card, 0.07),
        borderRadius: BorderRadius.circular(t.cardRadius - 6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            final cardData = item.asCardData();
            if (!_podeVerCard(cardData, access)) {
              _mostrarAcessoNegado(context, cardData);
              return;
            }
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => item.tela),
            );
          },
          borderRadius: BorderRadius.circular(t.cardRadius - 6),
          splashColor: visibleColor.withValues(alpha: 0.12),
          highlightColor: visibleColor.withValues(alpha: 0.06),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.cardRadius - 6),
              border: Border.all(color: visibleColor.withValues(alpha: 0.14)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _softFill(visibleColor, t.cardAlt, 0.14),
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                    border: Border.all(
                      color: visibleColor.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Icon(item.icon, color: visibleColor, size: 22),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.24,
                          color: t.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: visibleColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyMigrationState(BuildContext context) {
    final t = context.uai;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline_rounded, color: t.textMuted, size: 42),
          const SizedBox(height: 10),
          Text(
            'Nenhuma migração disponível.',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            'Solicite ao administrador a liberação das permissões necessárias.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingScaffold(BuildContext context) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.card);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Painel Administrativo',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
      ),
      body: Center(
        child: Padding(
          padding: _dashboardPagePadding,
          child: _dashboardWidthLimiter(
            Container(
              padding: const EdgeInsets.all(24),
              decoration: _sectionDecoration(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: _softFill(accent, t.cardAlt, 0.14),
                      borderRadius: BorderRadius.circular(t.cardRadius),
                      border: Border.all(color: accent.withValues(alpha: 0.16)),
                    ),
                    child: Center(
                      child: CircularProgressIndicator(color: accent),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Carregando painel administrativo...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Buscando permissões e módulos liberados.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: t.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorScaffold(BuildContext context) {
    final t = context.uai;
    final accent = _ensureVisible(t.error, t.card);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Painel Administrativo',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
      ),
      body: Center(
        child: Padding(
          padding: _dashboardPagePadding,
          child: _dashboardWidthLimiter(
            Container(
              padding: const EdgeInsets.all(24),
              decoration: _sectionDecoration(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: _softFill(accent, t.cardAlt, 0.14),
                      borderRadius: BorderRadius.circular(t.cardRadius),
                      border: Border.all(color: accent.withValues(alpha: 0.16)),
                    ),
                    child: Icon(
                      Icons.error_outline_rounded,
                      color: accent,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Não foi possível carregar suas permissões.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Verifique a conexão e tente novamente.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: t.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _permissionFuture = _carregarPermissoes();
                      });
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyAdminState(BuildContext context) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _sectionDecoration(context),
      child: Column(
        children: [
          Icon(Icons.lock_outline_rounded, color: t.textMuted, size: 46),
          const SizedBox(height: 10),
          Text(
            'Você não possui módulos administrativos liberados.',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Solicite ao administrador a liberação das permissões necessárias.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  List<_AdminCardData> _siteCards(UaiThemeTokens t) {
    return [
      _AdminCardData(
        icon: Icons.web_rounded,
        id: 'site',
        title: 'Gerenciar Site',
        subtitle: 'Regimento, biografia, graduações e inscrição',
        color: t.associacao,
        tela: const GerenciarSiteScreen(),
        permissions: const ['pode_gerenciar_site'],
      ),
      _AdminCardData(
        icon: Icons.image_rounded,
        id: 'logo_site',
        title: 'Logo do Site',
        subtitle: 'Troque a logo da página inicial',
        color: t.inscricoes,
        tela: const GerenciarLogoScreen(),
        permissions: const ['pode_gerenciar_logo_site'],
      ),
    ];
  }

  List<_AdminCardData> _appCards(UaiThemeTokens t) {
    return [
      _AdminCardData(
        icon: Icons.gavel_rounded,
        id: 'disciplina',
        title: 'Disciplina e Suspensões',
        subtitle: 'Advertências, pontos, prazos e regras globais',
        color: t.warning,
        tela: const DisciplinaAdminScreen(),
        permissions: const [],
        adminOnly: true,
        critical: true,
      ),
      _AdminCardData(icon: Icons.inventory_2_rounded, id: 'uniformes',
        title: 'Configurar Uniformes', subtitle: 'Professores, permissões, catálogo, auditoria e manutenção protegida', color: t.associacao, tela: const UniformesConfiguracoesScreen(), permissions: const [], adminOnly: true, critical: true),
      _AdminCardData(icon: Icons.cake_rounded, id: 'aniversariantes',
        title: 'Configurar Aniversariantes', subtitle: 'Robô, notificações, artes e mensagens', color: t.primary, tela: const ConfigurarAniversariantesScreen(), permissions: const [], adminOnly: true),
      _AdminCardData(
        icon: Icons.graphic_eq_rounded,
        id: 'rhythm',
        title: 'UAI Rhythm Studio',
        subtitle: 'Crie beats, partituras e treinos musicais de capoeira',
        color: t.success,
        tela: const RhythmStudioScreen(),
        permissions: const [],
        adminOnly: true,
      ),
      _AdminCardData(
        icon: Icons.manage_accounts_rounded,
        id: 'usuarios',
        title: 'Gerenciar Usuários',
        subtitle: 'Usuários, cargos e permissões do sistema',
        color: t.primary,
        tela: GerenciarUsuariosScreen(),
        permissions: const ['pode_gerenciar_usuarios'],
        critical: true,
      ),
      _AdminCardData(
        icon: Icons.palette_rounded,
        id: 'temas',
        title: 'Central de Temas',
        subtitle: 'Defina o tema global e os temas disponíveis para usuários',
        color: t.associacao,
        tela: const CentralTemasScreen(),
        permissions: const ['pode_gerenciar_temas_globais'],
      ),
      _AdminCardData(
        icon: Icons.health_and_safety_rounded,
        id: 'firebase',
        title: 'Saúde Firebase',
        subtitle: 'Banco, storage, funções, uso e integridade',
        color: t.info,
        tela: const FirebaseSaudeScreen(),
        permissions: const ['pode_saude_firebase'],
        critical: true,
        adminOnly: true,
      ),
      _AdminCardData(
        icon: Icons.system_update_alt_rounded,
        id: 'atualizacoes',
        title: 'Controle de Atualizações',
        subtitle: 'Upload de APK, versões, histórico e obrigatoriedade',
        color: t.success,
        tela: const ControleAtualizacoesScreen(),
        permissions: const ['pode_controle_atualizacoes'],
        critical: true,
        adminOnly: true,
      ),
      _AdminCardData(
        icon: Icons.bug_report_rounded,
        id: 'caca_bug',
        title: 'Caça Bug',
        subtitle: 'Diagnóstico temporário de sessão e erros',
        color: t.warning,
        tela: const CacaBugScreen(),
        permissions: const [
          'pode_acessar_caca_bug',
          'pode_ver_relatorio_caca_bug',
          'pode_configurar_caca_bug',
        ],
        critical: true,
      ),
      _AdminCardData(
        icon: Icons.rule_rounded,
        id: 'ausencias',
        title: 'Indicadores de Ausência',
        subtitle: 'Configure dias e cores do alerta de frequência',
        color: t.info,
        tela: const IndicadoresAusenciaScreen(),
        permissions: const ['pode_configurar_indicadores_ausencia'],
      ),
      _AdminCardData(
        icon: Icons.psychology_alt_rounded,
        id: 'brincadeiras',
        title: 'Brincadeiras da Chamada',
        subtitle: 'Telepatia e chamada inversa com controle seguro',
        color: t.warning,
        tela: const ModoTrollScreen(),
        permissions: const ['pode_configurar_chamada'],
      ),
      _AdminCardData(
        icon: Icons.workspace_premium_rounded,
        id: 'graduacoes',
        title: 'Gerenciar Graduações',
        subtitle: 'Crie, edite e organize as graduações do app',
        color: t.warning,
        tela: GerenciarGraduacoesScreen(),
        permissions: const ['pode_gerenciar_graduacoes'],
      ),
      _AdminCardData(
        icon: Icons.business_rounded,
        id: 'academias',
        title: 'Gerenciar Academias',
        subtitle: 'Academias, núcleos, turmas e horários',
        color: t.info,
        tela: GerenciarAcademiasScreen(),
        permissions: const ['pode_gerenciar_academias'],
      ),
      _AdminCardData(
        icon: Icons.event_rounded,
        id: 'eventos',
        title: 'Gerenciar Eventos',
        subtitle: 'Cadastre, edite e acompanhe eventos',
        color: t.eventos,
        tela: const GerenciarEventosScreen(),
        permissions: const [
          'pode_ver_eventos',
          'pode_acessar_eventos',
          'pode_criar_evento',
          'pode_editar_evento',
          'pode_gerenciar_participantes_evento',
        ],
      ),
      _AdminCardData(
        icon: Icons.directions_bus_filled_rounded,
        id: 'transportes',
        title: 'Configurar Transportes',
        subtitle: 'Tipos de veículo e capacidade padrão',
        color: t.warning,
        tela: const ConfigurarTransportesScreen(),
        permissions: const ['pode_configurar_transportes'],
      ),
      _AdminCardData(
        icon: Icons.history_edu_rounded,
        id: 'estudos',
        title: 'Estudos e Fundamentos',
        subtitle: 'Ciclos, estudos, artigos, vídeos e avaliações teóricas',
        color: t.info,
        tela: const GerenciarEstudosFundamentosScreen(),
        permissions: const ['pode_gerenciar_estudos_fundamentos'],
      ),
      _AdminCardData(
        icon: Icons.history_edu_rounded,
        id: 'certificados',
        title: 'Central de Certificados',
        subtitle: 'Studio, templates, emissão, QR e autenticidade',
        color: t.inscricoes,
        tela: const CertificadosAdminScreen(),
        permissions: const [
          'pode_acessar_certificados', 'pode_configurar_certificados',
          'pode_configurar_certificados_evento', 'pode_gerar_certificados_evento',
          'pode_emitir_certificados', 'pode_visualizar_templates_certificados',
          'pode_configurar_qr_certificados',
        ],
      ),
    ];
  }

  _AdminCardData _migrationLauncherCard(UaiThemeTokens t) {
    return _AdminCardData(
      icon: Icons.sync_alt_rounded,
      id: 'migracoes',
        title: 'Ferramentas de Migração',
      subtitle: 'Importações e correções de dados antigos',
      color: t.primary,
      tela: const SizedBox.shrink(),
      permissions: const ['pode_executar_migracoes'],
      critical: true,
      adminOnly: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AdminPermissionState>(
      future: _permissionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingScaffold(context);
        }

        if (snapshot.hasError || snapshot.data == null) {
          return _buildErrorScaffold(context);
        }

        return _buildAdminScaffold(context, snapshot.data!);
      },
    );
  }

  Widget _buildAdminScaffold(
    BuildContext context,
    _AdminPermissionState access,
  ) {
    final t = context.uai;
    // Todas as decisões de visibilidade continuam passando pelo mesmo serviço.
    final cards = [..._siteCards(t), ..._appCards(t)];
    final visibleCards = cards
        .where((item) => _podeVerCard(item, access))
        .toList(growable: false);
    final migration = _migrationLauncherCard(t);
    final showMigration = _podeVerCard(migration, access);
    final allCount = visibleCards.length + (showMigration ? 1 : 0);
    final favoriteIds = AdminPanelOrganization.safeFavorites(
      saved: _favoriteIds,
      allowed: visibleCards.map((item) => item.id),
    );
    final favorites = [
      for (final id in favoriteIds)
        ...visibleCards.where((item) => item.id == id),
    ];
    final searching = _searchQuery.trim().isNotEmpty;
    final hasSearchResults = visibleCards.any(
      (item) {
        final area = AdminPanelOrganization.cardAreas[item.id] ?? AdminPanelArea.avancado;
        return AdminPanelOrganization.matches(
          query: _searchQuery,
          title: item.title,
          subtitle: item.subtitle,
          extra: '${_areaTitle(area)} ${_areaSubtitle(area)}',
        );
      },
    ) || (showMigration && AdminPanelOrganization.matches(
      query: _searchQuery,
      title: migration.title,
      subtitle: migration.subtitle,
      extra: '${_areaTitle(AdminPanelArea.avancado)} '
          '${_areaSubtitle(AdminPanelArea.avancado)}',
    )) || (CreativeModeLauncher.isAvailable &&
        AdminPanelOrganization.matches(
          query: _searchQuery,
          title: 'Modo Criativo',
          subtitle: 'Laboratório visual Windows Debug',
          extra: '${_areaTitle(AdminPanelArea.avancado)} '
              '${_areaSubtitle(AdminPanelArea.avancado)}',
        ));

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Painel Administrativo',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        actions: [
          if (CreativeModeLauncher.isAvailable)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: FilledButton.tonalIcon(
                onPressed: () => CreativeModeLauncher.open(context),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Criativo'),
              ),
            ),
          if (_podeAbrirMigracoes(access))
            IconButton(
              tooltip: 'Migrações',
              onPressed: () => _abrirMigracoes(context, access),
              icon: const Icon(Icons.sync_alt_rounded),
            ),
        ],
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: _dashboardPagePadding,
        children: [
          _dashboardWidthLimiter(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeaderResumo(context, access, allCount),
                const SizedBox(height: 14),
                _buildAdminSearch(context),
                if (allCount == 0 && !CreativeModeLauncher.isAvailable) ...[
                  const SizedBox(height: 14),
                  _buildEmptyAdminState(context),
                ] else ...[
                  if (!searching && favorites.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _buildFavoriteSection(context, favorites, access),
                  ],
                  if (searching && !hasSearchResults) ...[
                    const SizedBox(height: 14),
                    _buildNoSearchResults(context),
                  ],
                  for (final area in AdminPanelArea.values) ...[
                    _buildOrganizedSection(
                      context: context,
                      area: area,
                      children: visibleCards
                          .where((item) =>
                              (AdminPanelOrganization.cardAreas[item.id] ??
                                  AdminPanelArea.avancado) == area)
                          .toList(growable: false),
                      access: access,
                      migration: area == AdminPanelArea.avancado && showMigration
                          ? migration
                          : null,
                      showCreative: area == AdminPanelArea.avancado &&
                          CreativeModeLauncher.isAvailable,
                    ),
                  ],
                ],
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminSearch(BuildContext context) {
    final t = context.uai;
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      onChanged: (value) => setState(() => _searchQuery = value),
      style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: 'Buscar módulo ou ferramenta...',
        hintStyle: TextStyle(color: t.textSecondary),
        prefixIcon: Icon(Icons.search_rounded, color: t.textSecondary),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpar busca',
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                icon: Icon(Icons.close_rounded, color: t.textSecondary),
              ),
        filled: true,
        fillColor: t.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.cardRadius - 3),
          borderSide: BorderSide(color: t.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.cardRadius - 3),
          borderSide: BorderSide(color: t.border),
        ),
      ),
    );
  }

  Widget _buildNoSearchResults(BuildContext context) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: _sectionDecoration(context),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 35, color: t.textSecondary),
          const SizedBox(height: 9),
          Text(
            'Nenhuma ferramenta encontrada',
            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Tente outro termo. A busca mostra somente módulos autorizados.',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoriteSection(
    BuildContext context,
    List<_AdminCardData> favorites,
    _AdminPermissionState access,
  ) {
    final t = context.uai;
    return Container(
      padding: EdgeInsets.all(_isDesktopDashboard ? 17 : 14),
      decoration: _sectionDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star_rounded, color: _ensureVisible(t.warning, t.card), size: 22),
              const SizedBox(width: 9),
              Text(
                'Favoritos',
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 15.5,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${favorites.length}/${AdminPanelOrganization.maxFavorites}',
                style: TextStyle(color: t.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _dashboardResponsiveWrap(
            children: favorites
                .map((item) => _buildAdminCard(
                      context: context,
                      item: item,
                      access: access,
                    ))
                .toList(),
            minItemWidth: 390,
            maxColumns: _isDesktopDashboard ? 3 : 2,
          ),
        ],
      ),
    );
  }

  Widget _buildCreativeModeCard(BuildContext context) {
    final t = context.uai;
    final accent = _ensureVisible(t.warning, t.card);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => CreativeModeLauncher.open(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            border: Border.all(color: accent.withValues(alpha: 0.24)),
            borderRadius: BorderRadius.circular(t.cardRadius),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _softFill(accent, t.cardAlt, 0.15),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
                child: Icon(Icons.auto_awesome_rounded, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Modo Criativo',
                            style: TextStyle(
                              color: t.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            'WINDOWS • DEBUG',
                            style: TextStyle(
                              color: accent,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Laboratório visual para redesenhar telas e exportar referências Flutter sem alterar a produção.',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11.5,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.chevron_right_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderResumo(
    BuildContext context,
    _AdminPermissionState access,
    int visibleCount,
  ) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.card);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
      decoration: _sectionDecoration(context),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _softFill(accent, t.cardAlt, 0.12),
              borderRadius: BorderRadius.circular(t.buttonRadius),
            ),
            child: Icon(Icons.admin_panel_settings_rounded, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Central de administração',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  access.adminMaster
                      ? '$visibleCount ferramentas • Acesso de administrador'
                      : '$visibleCount ferramentas liberadas para sua conta',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _areaTitle(AdminPanelArea area) => switch (area) {
    AdminPanelArea.essencial => '01  Gestão essencial',
    AdminPanelArea.operacoes => '02  Operações e acompanhamento',
    AdminPanelArea.sistema => '03  Sistema e segurança',
    AdminPanelArea.conteudo => '04  Site e personalização',
    AdminPanelArea.experiencias => '05  Experiências e criatividade',
    AdminPanelArea.avancado => '06  Ferramentas avançadas',
  };

  String _areaSubtitle(AdminPanelArea area) => switch (area) {
    AdminPanelArea.essencial => 'Estrutura e administração diária',
    AdminPanelArea.operacoes => 'Rotinas e acompanhamento de atividades',
    AdminPanelArea.sistema => 'Versões, estabilidade e diagnóstico',
    AdminPanelArea.conteudo => 'Identidade, conteúdo e apresentação',
    AdminPanelArea.experiencias => 'Aprendizagem e experiências interativas',
    AdminPanelArea.avancado => 'Migrações e utilitários de desenvolvimento',
  };

  IconData _areaIcon(AdminPanelArea area) => switch (area) {
    AdminPanelArea.essencial => Icons.shield_outlined,
    AdminPanelArea.operacoes => Icons.fact_check_outlined,
    AdminPanelArea.sistema => Icons.security_rounded,
    AdminPanelArea.conteudo => Icons.palette_outlined,
    AdminPanelArea.experiencias => Icons.auto_awesome_outlined,
    AdminPanelArea.avancado => Icons.build_outlined,
  };

  Widget _buildOrganizedSection({
    required BuildContext context,
    required AdminPanelArea area,
    required List<_AdminCardData> children,
    required _AdminPermissionState access,
    _AdminCardData? migration,
    bool showCreative = false,
  }) {
    final searchActive = _searchQuery.trim().isNotEmpty;
    final matchesArea = searchActive && AdminPanelOrganization.matches(
      query: _searchQuery,
      title: _areaTitle(area),
      subtitle: _areaSubtitle(area),
    );
    final visibleChildren = children.where((item) =>
        matchesArea || AdminPanelOrganization.matches(
          query: _searchQuery,
          title: item.title,
          subtitle: item.subtitle,
        )).toList(growable: false);
    final matchesMigration = migration != null &&
        (matchesArea || AdminPanelOrganization.matches(
          query: _searchQuery,
          title: migration.title,
          subtitle: migration.subtitle,
        ));
    final matchesCreative = showCreative &&
        (matchesArea || AdminPanelOrganization.matches(
          query: _searchQuery,
          title: 'Modo Criativo',
          subtitle: 'Laboratório visual Windows Debug',
        ));
    if (visibleChildren.isEmpty && !matchesMigration && !matchesCreative) {
      return const SizedBox.shrink();
    }
    final count = visibleChildren.length +
        (matchesMigration ? 1 : 0) + (matchesCreative ? 1 : 0);
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.card);
    final expanded = searchActive || _expandedAreas.contains(area);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
      padding: EdgeInsets.all(_isDesktopDashboard ? 17 : 14),
      decoration: _sectionDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(t.buttonRadius),
            child: InkWell(
              onTap: searchActive ? null : () => _toggleSection(area),
              borderRadius: BorderRadius.circular(t.buttonRadius),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _softFill(accent, t.cardAlt, 0.10),
                        borderRadius: BorderRadius.circular(t.buttonRadius),
                        border: Border.all(color: accent.withValues(alpha: 0.10)),
                      ),
                      child: Icon(_areaIcon(area), color: accent, size: 22),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _areaTitle(area),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _areaSubtitle(area),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textSecondary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text('$count', style: TextStyle(color: t.textSecondary, fontSize: 12)),
                    const SizedBox(width: 6),
                    Icon(
                      expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: t.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 14),
            if (visibleChildren.isNotEmpty)
              _dashboardResponsiveWrap(
                children: visibleChildren.map((item) => _buildAdminCard(
                  context: context,
                  item: item,
                  access: access,
                )).toList(),
                minItemWidth: 390,
                maxColumns: _isDesktopDashboard ? 3 : 2,
                spacing: 12,
                runSpacing: 12,
              ),
            if (matchesMigration) ...[
              if (visibleChildren.isNotEmpty) const SizedBox(height: 12),
              _buildMigrationButton(context, migration, access),
            ],
            if (matchesCreative) ...[
              if (visibleChildren.isNotEmpty || matchesMigration)
                const SizedBox(height: 12),
              _buildCreativeModeCard(context),
            ],
          ],
        ],
      ),
      ),
    );
  }

  Widget _buildAdminCard({
    required BuildContext context,
    required _AdminCardData item,
    required _AdminPermissionState access,
  }) {
    final t = context.uai;
    final visibleColor = _ensureVisible(item.color, t.card);

    return Padding(
      padding: EdgeInsets.zero,
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius - 6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _abrirTelaProtegida(context, item, access),
          borderRadius: BorderRadius.circular(t.cardRadius - 6),
          splashColor: visibleColor.withValues(alpha: 0.12),
          highlightColor: visibleColor.withValues(alpha: 0.06),
          child: Container(
            constraints: const BoxConstraints(minHeight: 82),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.cardRadius - 6),
              border: Border.all(color: visibleColor.withValues(alpha: 0.12)),
              boxShadow: t.softShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _softFill(visibleColor, t.cardAlt, 0.13),
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                    border: Border.all(
                      color: visibleColor.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Icon(item.icon, size: 25, color: visibleColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 11.5,
                          height: 1.24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                IconButton(
                  icon: Icon(
                    _favoriteIds.contains(item.id)
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 21,
                    color: _favoriteIds.contains(item.id)
                        ? _ensureVisible(t.warning, t.card)
                        : t.textSecondary,
                  ),
                  tooltip: _favoriteIds.contains(item.id)
                      ? 'Remover ${item.title} dos favoritos'
                      : 'Fixar ${item.title} nos favoritos',
                  onPressed: () => _toggleFavorite(item.id, access),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minHeight: 38, minWidth: 38),
                ),
                Icon(Icons.chevron_right_rounded, color: visibleColor, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMigrationButton(
    BuildContext context,
    _AdminCardData item,
    _AdminPermissionState access,
  ) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.card);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius - 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (!_podeVerCard(item, access)) {
            _mostrarAcessoNegado(context, item);
            return;
          }
          _abrirMigracoes(context, access);
        },
        borderRadius: BorderRadius.circular(t.cardRadius - 6),
        splashColor: accent.withValues(alpha: 0.10),
        highlightColor: accent.withValues(alpha: 0.04),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.cardRadius - 6),
            border: Border.all(color: accent.withValues(alpha: 0.14)),
            boxShadow: t.softShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _softFill(accent, t.cardAlt, 0.12),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: accent.withValues(alpha: 0.12)),
                ),
                child: Icon(Icons.sync_alt_rounded, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Abrir ferramentas de migração',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _sectionDecoration(BuildContext context) {
    final t = context.uai;

    return BoxDecoration(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius + 2),
      border: Border.all(color: t.border),
      boxShadow: t.softShadow,
    );
  }
}

class _AdminCardData {
  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Widget tela;
  final List<String> permissions;
  final bool critical;
  final bool adminOnly;
  final String? deniedMessage = null;

  const _AdminCardData({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.tela,
    this.permissions = const [],
    this.critical = false,
    this.adminOnly = false,

  });
}

class _MigrationItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Widget tela;
  final List<String> permissions;
  final bool adminOnly;

  const _MigrationItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.tela,
    required this.permissions,
    this.adminOnly = true,
  });

  _AdminCardData asCardData() {
    return _AdminCardData(
      id: 'migracao_${title.toLowerCase().replaceAll(' ', '_')}',
      icon: icon,
      title: title,
      subtitle: subtitle,
      color: color,
      tela: tela,
      permissions: permissions,
      critical: true,
      adminOnly: adminOnly,
    );
  }
}

class _AdminPermissionState {
  final bool adminMaster;
  final Map<String, bool> permissions;

  const _AdminPermissionState({
    required this.adminMaster,
    required this.permissions,
  });
}

// ============================================================
// Tela refatorada visualmente em 03/07/2026 às 13:29
// Refatoração focada em tema dinâmico, responsividade e layout adaptativo.
// Lógica original preservada.
// ============================================================
