// lib/screens/admin/admin_screen.dart

import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
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

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance()).abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _softFill(Color color, Color base, [double opacity = 0.11]) {
    return Color.alphaBlend(color.withOpacity(opacity), base);
  }

  void _abrirTela(BuildContext context, Widget tela) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => tela),
    );
  }

  void _abrirMigracoes(BuildContext context) {
    final t = context.uai;

    final migrations = <_MigrationItem>[
      _MigrationItem(
        icon: Icons.people_alt_rounded,
        title: 'Migrar Alunos',
        subtitle: 'Importar ou corrigir dados antigos dos alunos',
        color: t.info,
        tela: MigracaoTriagemScreen(),
      ),
      _MigrationItem(
        icon: Icons.workspace_premium_rounded,
        title: 'Migrar Graduações',
        subtitle: 'Importar graduações e faixas antigas',
        color: t.warning,
        tela: const MigracaoGraduacoesScreen(),
      ),
      _MigrationItem(
        icon: Icons.history_edu_rounded,
        title: 'Migrar Chamadas',
        subtitle: 'Importar histórico de chamadas e presenças',
        color: t.associacao,
        tela: MigracaoChamadasScreen(),
      ),
      _MigrationItem(
        icon: Icons.event_available_rounded,
        title: 'Migrar Eventos',
        subtitle: 'Importar eventos antigos do sistema',
        color: t.success,
        tela: MigracaoEventosScreen(),
      ),
      _MigrationItem(
        icon: Icons.emoji_events_rounded,
        title: 'Migrar Participações',
        subtitle: 'Importar participantes e vínculos de eventos',
        color: t.warning,
        tela: MigracaoParticipacoesScreen(),
      ),
    ];

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
                          borderRadius: BorderRadius.circular(t.buttonRadius + 1),
                          border: Border.all(color: accent.withOpacity(0.16)),
                        ),
                        child: Icon(
                          Icons.sync_alt_rounded,
                          color: accent,
                        ),
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
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                    itemCount: migrations.length,
                    itemBuilder: (context, index) {
                      final item = migrations[index];

                      return _buildMigrationTile(
                        context: sheetContext,
                        icon: item.icon,
                        title: item.title,
                        subtitle: item.subtitle,
                        color: item.color,
                        tela: item.tela,
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
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Widget tela,
  }) {
    final t = context.uai;
    final visibleColor = _ensureVisible(color, t.card);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: _softFill(visibleColor, t.card, 0.07),
        borderRadius: BorderRadius.circular(t.cardRadius - 6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.pop(context);
            _abrirTela(context, tela);
          },
          borderRadius: BorderRadius.circular(t.cardRadius - 6),
          splashColor: visibleColor.withOpacity(0.12),
          highlightColor: visibleColor.withOpacity(0.06),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.cardRadius - 6),
              border: Border.all(color: visibleColor.withOpacity(0.14)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _softFill(visibleColor, t.cardAlt, 0.14),
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                    border: Border.all(color: visibleColor.withOpacity(0.12)),
                  ),
                  child: Icon(icon, color: visibleColor, size: 22),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
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
                        subtitle,
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

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Painel Administrativo',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Migrações',
            onPressed: () => _abrirMigracoes(context),
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
                      _buildHeaderResumo(context),
                      const SizedBox(height: 16),
                      _buildSection(
                        context: context,
                        icon: Icons.public_rounded,
                        title: 'Gerenciamento do Site',
                        subtitle: 'Conteúdo público, logo e páginas do site.',
                        children: [
                          _AdminCardData(
                            icon: Icons.web_rounded,
                            title: 'Gerenciar Site',
                            subtitle: 'Regimento, biografia, graduações e inscrição',
                            color: t.associacao,
                            tela: const GerenciarSiteScreen(),
                          ),
                          _AdminCardData(
                            icon: Icons.image_rounded,
                            title: 'Logo do Site',
                            subtitle: 'Troque a logo da página inicial',
                            color: t.inscricoes,
                            tela: const GerenciarLogoScreen(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildSection(
                        context: context,
                        icon: Icons.phone_android_rounded,
                        title: 'Gerenciamento do App',
                        subtitle: 'Usuários, eventos, academias e dados internos.',
                        children: [
                          _AdminCardData(
                            icon: Icons.manage_accounts_rounded,
                            title: 'Gerenciar Usuários',
                            subtitle: 'Usuários, cargos e permissões do sistema',
                            color: t.primary,
                            tela: GerenciarUsuariosScreen(),
                          ),
                          _AdminCardData(
                            icon: Icons.workspace_premium_rounded,
                            title: 'Gerenciar Graduações',
                            subtitle: 'Crie, edite e organize as graduações do app',
                            color: t.warning,
                            tela: GerenciarGraduacoesScreen(),
                          ),
                          _AdminCardData(
                            icon: Icons.business_rounded,
                            title: 'Gerenciar Academias',
                            subtitle: 'Academias, núcleos, turmas e horários',
                            color: t.info,
                            tela: GerenciarAcademiasScreen(),
                          ),
                          _AdminCardData(
                            icon: Icons.event_rounded,
                            title: 'Gerenciar Eventos',
                            subtitle: 'Cadastre, edite e acompanhe eventos',
                            color: t.eventos,
                            tela: const GerenciarEventosScreen(),
                          ),
                          _AdminCardData(
                            icon: Icons.emoji_events_rounded,
                            title: 'Gerenciar Participações',
                            subtitle: 'Participações, pagamentos e certificados',
                            color: t.warning,
                            tela: const GerenciarParticipacoesScreen(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildMigrationButton(context),
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

  Widget _buildHeaderResumo(BuildContext context) {
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
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(t.cardRadius - 2),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(
              Icons.admin_panel_settings_rounded,
              color: onPrimary,
              size: 34,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
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
                  color: onPrimary.withOpacity(0.82),
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
                    label: 'Admin',
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
            return Column(
              children: [
                icon,
                const SizedBox(height: 14),
                text,
              ],
            );
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
  }) {
    final t = context.uai;

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
                  children: children.map((item) {
                    return _buildAdminCard(
                      context: context,
                      icon: item.icon,
                      title: item.title,
                      subtitle: item.subtitle,
                      color: item.color,
                      tela: item.tela,
                    );
                  }).toList(),
                );
              }

              final itemWidth = (constraints.maxWidth - spacing) / 2;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: children.map((item) {
                  return SizedBox(
                    width: itemWidth,
                    child: _buildAdminCard(
                      context: context,
                      icon: item.icon,
                      title: item.title,
                      subtitle: item.subtitle,
                      color: item.color,
                      tela: item.tela,
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
            border: Border.all(color: accent.withOpacity(0.12)),
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
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Widget tela,
  }) {
    final t = context.uai;
    final visibleColor = _ensureVisible(color, t.card);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius - 6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _abrirTela(context, tela),
          borderRadius: BorderRadius.circular(t.cardRadius - 6),
          splashColor: visibleColor.withOpacity(0.12),
          highlightColor: visibleColor.withOpacity(0.06),
          child: Container(
            constraints: const BoxConstraints(minHeight: 82),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.cardRadius - 6),
              border: Border.all(color: visibleColor.withOpacity(0.12)),
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
                    border: Border.all(color: visibleColor.withOpacity(0.12)),
                  ),
                  child: Icon(icon, size: 25, color: visibleColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
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
                        subtitle,
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

  Widget _buildMigrationButton(BuildContext context) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.card);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius - 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _abrirMigracoes(context),
        borderRadius: BorderRadius.circular(t.cardRadius - 6),
        splashColor: accent.withOpacity(0.10),
        highlightColor: accent.withOpacity(0.04),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.cardRadius - 6),
            border: Border.all(color: accent.withOpacity(0.14)),
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
                  border: Border.all(color: accent.withOpacity(0.12)),
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
        color: onPrimary.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: onPrimary.withOpacity(0.16)),
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

  const _AdminCardData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.tela,
  });
}

class _MigrationItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Widget tela;

  const _MigrationItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.tela,
  });
}
