// lib/modules/sistema/admin/admin_screen.dart

import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/permissions/permissao_service.dart';
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
import 'package:uai_capoeira/modules/sistema/migrations/migracao_participacoes_screen.dart';
import 'package:uai_capoeira/modules/eventos/admin/gerenciar_participacoes_screen.dart';
import 'package:uai_capoeira/modules/sistema/migrations/migracao_graduacoes_screen.dart';
import 'package:uai_capoeira/modules/site/admin/gerenciar_site_screen.dart';
import 'package:uai_capoeira/modules/site/admin/gerenciar_logo_screen.dart';
import 'package:uai_capoeira/modules/certificados/screens/certificado_preview_teste_screen.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/admin/controle_atualizacoes_screen.dart';
import 'package:uai_capoeira/modules/sistema/admin/indicadores_ausencia_screen.dart';
import 'package:uai_capoeira/modules/sistema/firebase_saude/admin/firebase_saude_screen.dart';
import 'package:uai_capoeira/modules/sistema/admin/modo_troll_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final PermissaoService _permissaoService = PermissaoService();
  late Future<_AdminPermissionState> _permissionFuture;

  @override
  void initState() {
    super.initState();
    _permissionFuture = _carregarPermissoes();
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

  Color _softFill(Color color, Color base, [double opacity = 0.11]) {
    return Color.alphaBlend(color.withValues(alpha: opacity), base);
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
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Painel Administrativo',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
      ),
      body: Center(child: CircularProgressIndicator(color: t.primary)),
    );
  }

  Widget _buildErrorScaffold(BuildContext context) {
    final t = context.uai;
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
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: t.error, size: 48),
              const SizedBox(height: 12),
              Text(
                'Não foi possível carregar suas permissões.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
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
        title: 'Gerenciar Site',
        subtitle: 'Regimento, biografia, graduações e inscrição',
        color: t.associacao,
        tela: const GerenciarSiteScreen(),
        permissions: const ['pode_gerenciar_site'],
      ),
      _AdminCardData(
        icon: Icons.image_rounded,
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
        icon: Icons.manage_accounts_rounded,
        title: 'Gerenciar Usuários',
        subtitle: 'Usuários, cargos e permissões do sistema',
        color: t.primary,
        tela: GerenciarUsuariosScreen(),
        permissions: const ['pode_gerenciar_usuarios'],
        critical: true,
      ),
      _AdminCardData(
        icon: Icons.health_and_safety_rounded,
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
        title: 'Controle de Atualizações',
        subtitle: 'Upload de APK, versões, histórico e obrigatoriedade',
        color: t.success,
        tela: const ControleAtualizacoesScreen(),
        permissions: const ['pode_controle_atualizacoes'],
        critical: true,
        adminOnly: true,
      ),
      _AdminCardData(
        icon: Icons.rule_rounded,
        title: 'Indicadores de Ausência',
        subtitle: 'Configure dias e cores do alerta de frequência',
        color: t.info,
        tela: const IndicadoresAusenciaScreen(),
        permissions: const ['pode_configurar_indicadores_ausencia'],
      ),
      _AdminCardData(
        icon: Icons.psychology_alt_rounded,
        title: 'Brincadeiras da Chamada',
        subtitle: 'Telepatia e chamada inversa com controle seguro',
        color: t.warning,
        tela: const ModoTrollScreen(),
        permissions: const ['pode_configurar_chamada'],
      ),
      _AdminCardData(
        icon: Icons.workspace_premium_rounded,
        title: 'Gerenciar Graduações',
        subtitle: 'Crie, edite e organize as graduações do app',
        color: t.warning,
        tela: GerenciarGraduacoesScreen(),
        permissions: const ['pode_gerenciar_graduacoes'],
      ),
      _AdminCardData(
        icon: Icons.business_rounded,
        title: 'Gerenciar Academias',
        subtitle: 'Academias, núcleos, turmas e horários',
        color: t.info,
        tela: GerenciarAcademiasScreen(),
        permissions: const ['pode_gerenciar_academias'],
      ),
      _AdminCardData(
        icon: Icons.event_rounded,
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
        icon: Icons.emoji_events_rounded,
        title: 'Gerenciar Participações',
        subtitle: 'Participações, pagamentos e certificados',
        color: t.warning,
        tela: const GerenciarParticipacoesScreen(),
        permissions: const [
          'pode_gerenciar_participantes_evento',
          'pode_adicionar_participante_evento',
          'pode_editar_participacao_evento',
          'pode_remover_participante_evento',
          'pode_concluir_participacao_evento',
        ],
      ),
      _AdminCardData(
        icon: Icons.history_edu_rounded,
        title: 'Configurar Certificados',
        subtitle: 'Templates, prévias e geração automática por SVG',
        color: t.inscricoes,
        tela: const CertificadoPreviewTesteScreen(),
        permissions: const ['pode_configurar_certificados'],
      ),
    ];
  }

  _AdminCardData _migrationLauncherCard(UaiThemeTokens t) {
    return _AdminCardData(
      icon: Icons.sync_alt_rounded,
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
    final siteCards = _siteCards(t);
    final appCards = _appCards(t);
    final migrationLauncher = _migrationLauncherCard(t);
    final visibleCount = [
      ...siteCards,
      ...appCards,
      migrationLauncher,
    ].where((item) => _podeVerCard(item, access)).length;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Painel Administrativo',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        actions: [
          if (_podeAbrirMigracoes(access))
            IconButton(
              tooltip: 'Migrações',
              onPressed: () => _abrirMigracoes(context, access),
              icon: const Icon(Icons.sync_alt_rounded),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth < 600 ? 14.0 : 22.0;

          return ListView(
            padding: EdgeInsets.fromLTRB(horizontal, 14, horizontal, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeaderResumo(context, access),
                      const SizedBox(height: 16),
                      if (visibleCount == 0) ...[
                        _buildEmptyAdminState(context),
                        const SizedBox(height: 14),
                      ],
                      _buildSection(
                        context: context,
                        icon: Icons.public_rounded,
                        title: 'Gerenciamento do Site',
                        subtitle: 'Conteúdo público, logo e páginas do site.',
                        children: [
                          _AdminCardData(
                            icon: Icons.web_rounded,
                            title: 'Gerenciar Site',
                            subtitle:
                                'Regimento, biografia, graduações e inscrição',
                            color: t.associacao,
                            tela: const GerenciarSiteScreen(),
                            permissions: const ['pode_gerenciar_site'],
                          ),
                          _AdminCardData(
                            icon: Icons.image_rounded,
                            title: 'Logo do Site',
                            subtitle: 'Troque a logo da página inicial',
                            color: t.inscricoes,
                            tela: const GerenciarLogoScreen(),
                            permissions: const ['pode_gerenciar_logo_site'],
                          ),
                        ],
                        access: access,
                      ),
                      const SizedBox(height: 14),
                      _buildSection(
                        context: context,
                        icon: Icons.phone_android_rounded,
                        title: 'Gerenciamento do App',
                        subtitle:
                            'Usuários, eventos, academias e dados internos.',
                        children: [
                          _AdminCardData(
                            icon: Icons.manage_accounts_rounded,
                            title: 'Gerenciar Usuários',
                            subtitle:
                                'Usuários, cargos e permissões do sistema',
                            color: t.primary,
                            tela: GerenciarUsuariosScreen(),
                            permissions: const ['pode_gerenciar_usuarios'],
                            critical: true,
                            deniedMessage:
                                'Você não tem permissão para gerenciar usuários.',
                          ),
                          _AdminCardData(
                            icon: Icons.health_and_safety_rounded,
                            title: 'Saúde Firebase',
                            subtitle:
                                'Banco, storage, funções, uso e integridade',
                            color: t.info,
                            tela: const FirebaseSaudeScreen(),
                            permissions: const ['pode_saude_firebase'],
                            critical: true,
                            adminOnly: true,
                          ),
                          _AdminCardData(
                            icon: Icons.system_update_alt_rounded,
                            title: 'Controle de Atualizações',
                            subtitle:
                                'Upload de APK, versões, histórico e obrigatoriedade',
                            color: t.success,
                            tela: const ControleAtualizacoesScreen(),
                            permissions: const ['pode_controle_atualizacoes'],
                            critical: true,
                            adminOnly: true,
                          ),
                          _AdminCardData(
                            icon: Icons.rule_rounded,
                            title: 'Indicadores de Ausência',
                            subtitle:
                                'Configure dias e cores do alerta de frequência',
                            color: t.info,
                            tela: const IndicadoresAusenciaScreen(),
                            permissions: const [
                              'pode_configurar_indicadores_ausencia',
                            ],
                          ),
                          _AdminCardData(
                            icon: Icons.psychology_alt_rounded,
                            title: 'Brincadeiras da Chamada',
                            subtitle:
                                'Telepatia e chamada inversa com controle seguro',
                            color: t.warning,
                            tela: const ModoTrollScreen(),
                            permissions: const ['pode_configurar_chamada'],
                          ),
                          _AdminCardData(
                            icon: Icons.workspace_premium_rounded,
                            title: 'Gerenciar Graduações',
                            subtitle:
                                'Crie, edite e organize as graduações do app',
                            color: t.warning,
                            tela: GerenciarGraduacoesScreen(),
                            permissions: const ['pode_gerenciar_graduacoes'],
                          ),
                          _AdminCardData(
                            icon: Icons.business_rounded,
                            title: 'Gerenciar Academias',
                            subtitle: 'Academias, núcleos, turmas e horários',
                            color: t.info,
                            tela: GerenciarAcademiasScreen(),
                            permissions: const ['pode_gerenciar_academias'],
                          ),
                          _AdminCardData(
                            icon: Icons.event_rounded,
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
                            icon: Icons.emoji_events_rounded,
                            title: 'Gerenciar Participações',
                            subtitle:
                                'Participações, pagamentos e certificados',
                            color: t.warning,
                            tela: const GerenciarParticipacoesScreen(),
                            permissions: const [
                              'pode_gerenciar_participantes_evento',
                              'pode_adicionar_participante_evento',
                              'pode_editar_participacao_evento',
                              'pode_remover_participante_evento',
                              'pode_concluir_participacao_evento',
                            ],
                          ),
                          _AdminCardData(
                            icon: Icons.history_edu_rounded,
                            title: 'Configurar Certificados',
                            subtitle:
                                'Templates, prévias e geração automática por SVG',
                            color: t.inscricoes,
                            tela: const CertificadoPreviewTesteScreen(),
                            permissions: const ['pode_configurar_certificados'],
                          ),
                        ],
                        access: access,
                      ),
                      const SizedBox(height: 14),
                      if (_podeVerCard(migrationLauncher, access))
                        _buildMigrationButton(
                          context,
                          migrationLauncher,
                          access,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderResumo(
    BuildContext context,
    _AdminPermissionState access,
  ) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        boxShadow: t.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final icon = Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: onPrimary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(t.cardRadius - 2),
              border: Border.all(color: onPrimary.withValues(alpha: 0.16)),
            ),
            child: Icon(
              Icons.admin_panel_settings_rounded,
              color: onPrimary,
              size: 34,
            ),
          );

          final text = Column(
            crossAxisAlignment: narrow
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                'Admin Uai Capoeira',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary,
                  fontSize: narrow ? 23 : 28,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Site, app, eventos, usuários, academias e migrações em um só lugar.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary.withValues(alpha: 0.82),
                  fontSize: 13,
                  height: 1.32,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _whiteChip(
                    context: context,
                    icon: Icons.security_rounded,
                    label: access.adminMaster
                        ? 'Acesso completo'
                        : 'Acesso personalizado',
                  ),
                  _whiteChip(
                    context: context,
                    icon: Icons.tune_rounded,
                    label: 'Configurações',
                  ),
                  _whiteChip(
                    context: context,
                    icon: Icons.sync_alt_rounded,
                    label: 'Migrações',
                  ),
                ],
              ),
            ],
          );

          if (narrow) {
            return Column(children: [icon, const SizedBox(height: 14), text]);
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSection({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<_AdminCardData> children,
    required _AdminPermissionState access,
  }) {
    final visibleChildren = children
        .where((item) => _podeVerCard(item, access))
        .toList(growable: false);

    if (visibleChildren.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: _sectionDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            context: context,
            icon: icon,
            title: title,
            subtitle: subtitle,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final useTwoColumns = constraints.maxWidth >= 720;
              const spacing = 10.0;

              if (!useTwoColumns) {
                return Column(
                  children: visibleChildren.map((item) {
                    return _buildAdminCard(
                      context: context,
                      item: item,
                      access: access,
                    );
                  }).toList(),
                );
              }

              final itemWidth = (constraints.maxWidth - spacing) / 2;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: visibleChildren.map((item) {
                  return SizedBox(
                    width: itemWidth,
                    child: _buildAdminCard(
                      context: context,
                      item: item,
                      access: access,
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.card);

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _softFill(accent, t.cardAlt, 0.12),
            borderRadius: BorderRadius.circular(t.buttonRadius),
            border: Border.all(color: accent.withValues(alpha: 0.12)),
          ),
          child: Icon(icon, color: accent),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
      ],
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
      padding: const EdgeInsets.only(bottom: 10),
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
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: visibleColor),
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

  Widget _whiteChip({
    required BuildContext context,
    required IconData icon,
    required String label,
  }) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: onPrimary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: onPrimary.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onPrimary, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: onPrimary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _sectionDecoration(BuildContext context) {
    final t = context.uai;

    return BoxDecoration(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      border: Border.all(color: t.border),
      boxShadow: t.softShadow,
    );
  }
}

class _AdminCardData {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Widget tela;
  final List<String> permissions;
  final bool critical;
  final bool adminOnly;
  final String? deniedMessage;

  const _AdminCardData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.tela,
    this.permissions = const [],
    this.critical = false,
    this.adminOnly = false,
    this.deniedMessage,
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
