import 'package:flutter/material.dart';
import '../../gerenciar_graduacoes_screen.dart';
import '../../gerenciar_usuarios_screen.dart';
import '../../migracao_triagem_screen.dart';
import 'gerenciar_academias_screen.dart';
import 'migracao_chamadas_screen.dart';
import 'migracao_eventos_screen.dart';
import 'gerenciar_eventos_screen.dart';
import 'migracao_participacoes_screen.dart';
import 'gerenciar_participacoes_screen.dart';
import 'migracao_graduacoes_screen.dart';
import 'gerenciar_site_screen.dart';
import 'gerenciar_logo_screen.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  void _abrirTela(BuildContext context, Widget tela) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => tela),
    );
  }

  void _abrirMigracoes(BuildContext context) {
    final migrations = <_MigrationItem>[
      _MigrationItem(
        icon: Icons.people_alt_rounded,
        title: 'Migrar Alunos',
        subtitle: 'Importar ou corrigir dados antigos dos alunos',
        color: Colors.blue,
        tela: MigracaoTriagemScreen(),
      ),
      const _MigrationItem(
        icon: Icons.workspace_premium_rounded,
        title: 'Migrar Graduações',
        subtitle: 'Importar graduações e faixas antigas',
        color: Colors.orange,
        tela: MigracaoGraduacoesScreen(),
      ),
      _MigrationItem(
        icon: Icons.history_edu_rounded,
        title: 'Migrar Chamadas',
        subtitle: 'Importar histórico de chamadas e presenças',
        color: Colors.purple,
        tela: MigracaoChamadasScreen(),
      ),
      _MigrationItem(
        icon: Icons.event_available_rounded,
        title: 'Migrar Eventos',
        subtitle: 'Importar eventos antigos do sistema',
        color: Colors.green,
        tela: MigracaoEventosScreen(),
      ),
      _MigrationItem(
        icon: Icons.emoji_events_rounded,
        title: 'Migrar Participações',
        subtitle: 'Importar participantes e vínculos de eventos',
        color: Colors.amber,
        tela: MigracaoParticipacoesScreen(),
      ),
    ];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.84;

        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            constraints: BoxConstraints(maxHeight: maxHeight),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.16),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
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
                          color: Colors.red.shade900.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: Icon(
                          Icons.sync_alt_rounded,
                          color: Colors.red.shade900,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ferramentas de Migração',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Importações e correções de dados antigos',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                                height: 1.25,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
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
                        context: context,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: color.withOpacity(0.055),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.pop(context);
            _abrirTela(context, tela);
          },
          borderRadius: BorderRadius.circular(18),
          splashColor: color.withOpacity(0.12),
          highlightColor: color.withOpacity(0.06),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withOpacity(0.12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: _iconColor(color), size: 22),
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
                          color: Colors.grey.shade900,
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
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Painel Administrativo',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
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
                        icon: Icons.public_rounded,
                        title: 'Gerenciamento do Site',
                        subtitle: 'Conteúdo público, logo e páginas do site.',
                        children: [
                          _AdminCardData(
                            icon: Icons.web_rounded,
                            title: 'Gerenciar Site',
                            subtitle: 'Regimento, biografia, graduações e inscrição',
                            color: Colors.purple,
                            tela: const GerenciarSiteScreen(),
                          ),
                          _AdminCardData(
                            icon: Icons.image_rounded,
                            title: 'Logo do Site',
                            subtitle: 'Troque a logo da página inicial',
                            color: Colors.teal,
                            tela: const GerenciarLogoScreen(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildSection(
                        icon: Icons.phone_android_rounded,
                        title: 'Gerenciamento do App',
                        subtitle: 'Usuários, eventos, academias e dados internos.',
                        children: [
                          _AdminCardData(
                            icon: Icons.manage_accounts_rounded,
                            title: 'Gerenciar Usuários',
                            subtitle: 'Usuários, cargos e permissões do sistema',
                            color: Colors.red,
                            tela: GerenciarUsuariosScreen(),
                          ),
                          _AdminCardData(
                            icon: Icons.workspace_premium_rounded,
                            title: 'Gerenciar Graduações',
                            subtitle: 'Crie, edite e organize as graduações do app',
                            color: Colors.deepOrange,
                            tela: GerenciarGraduacoesScreen(),
                          ),
                          _AdminCardData(
                            icon: Icons.business_rounded,
                            title: 'Gerenciar Academias',
                            subtitle: 'Academias, núcleos, turmas e horários',
                            color: Colors.indigo,
                            tela: GerenciarAcademiasScreen(),
                          ),
                          _AdminCardData(
                            icon: Icons.event_rounded,
                            title: 'Gerenciar Eventos',
                            subtitle: 'Cadastre, edite e acompanhe eventos',
                            color: Colors.blue,
                            tela: const GerenciarEventosScreen(),
                          ),
                          _AdminCardData(
                            icon: Icons.emoji_events_rounded,
                            title: 'Gerenciar Participações',
                            subtitle: 'Participações, pagamentos e certificados',
                            color: Colors.amber,
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade900.withOpacity(0.16),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final icon = Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.16)),
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
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
                  color: Colors.white,
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
                  color: Colors.white.withOpacity(0.82),
                  fontSize: 13,
                  height: 1.32,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _whiteChip(
                    icon: Icons.security_rounded,
                    label: 'Admin',
                  ),
                  _whiteChip(
                    icon: Icons.tune_rounded,
                    label: 'Configurações',
                  ),
                  _whiteChip(
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
    required IconData icon,
    required String title,
    required String subtitle,
    required List<_AdminCardData> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: _sectionDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
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
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.red.shade900.withOpacity(0.08),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: Colors.red.shade900),
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
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 11.5,
                  height: 1.25,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _abrirTela(context, tela),
          borderRadius: BorderRadius.circular(18),
          splashColor: color.withOpacity(0.12),
          highlightColor: color.withOpacity(0.06),
          child: Container(
            constraints: const BoxConstraints(minHeight: 82),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withOpacity(0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.024),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, size: 25, color: _iconColor(color)),
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
                          color: Colors.grey.shade900,
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
                          color: Colors.grey.shade600,
                          fontSize: 11.5,
                          height: 1.24,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMigrationButton(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _abrirMigracoes(context),
        borderRadius: BorderRadius.circular(18),
        splashColor: Colors.red.withOpacity(0.10),
        highlightColor: Colors.red.withOpacity(0.04),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.red.shade100),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.sync_alt_rounded, color: Colors.red.shade900),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Abrir ferramentas de migração',
                  style: TextStyle(
                    color: Colors.red.shade900,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.red.shade900),
            ],
          ),
        ),
      ),
    );
  }

  Widget _whiteChip({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _sectionDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.grey.shade100),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.032),
          blurRadius: 7,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  Color _iconColor(Color color) {
    if (color is MaterialColor) return color.shade700;
    return color;
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
