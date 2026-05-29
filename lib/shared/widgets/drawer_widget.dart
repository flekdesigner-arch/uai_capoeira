import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Telas
import 'package:uai_capoeira/modules/eventos/screens/eventos_screen.dart';
import 'package:uai_capoeira/shared/widgets/em_desenvolvimento_screen.dart';
import 'package:uai_capoeira/modules/uniformes/screens/uniformes_screen.dart';
import 'package:uai_capoeira/modules/alunos/screens/alunos_screen.dart';
import 'package:uai_capoeira/modules/sistema/admin/admin_screen.dart';
import 'package:uai_capoeira/modules/usuarios/screens/profile_screen.dart';
import 'package:uai_capoeira/shared/widgets/botao_atualizar_melhorado.dart';
import 'package:uai_capoeira/modules/inscricoes/admin/gerenciar_inscricoes_screen.dart';

// Services
import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class AppDrawer extends StatelessWidget {
  final Map<String, dynamic> userData;
  final User? currentUser;
  final VoidCallback onLogout;
  final PermissaoService permissaoService;

  const AppDrawer({
    super.key,
    required this.userData,
    required this.currentUser,
    required this.onLogout,
    required this.permissaoService,
  });

  bool get _contaAtiva {
    final status = userData['status_conta']?.toString().toLowerCase().trim() ?? '';
    return status == 'ativa' || status == 'ativo';
  }

  int get _pesoPermissao {
    final raw = userData['peso_permissao'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  bool get _isAdminLocal {
    final tipo = userData['tipo']?.toString().toLowerCase().trim() ?? '';
    return _pesoPermissao >= 90 || tipo == 'admin' || tipo == 'administrador';
  }

  Future<bool> _temAlguma(List<String> chaves) {
    return permissaoService.temQualquerPermissao(chaves);
  }

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

  Future<_DrawerPermissoes> _carregarPermissoesDrawer() async {
    if (!_contaAtiva) {
      return const _DrawerPermissoes();
    }

    final results = await Future.wait<bool>([
      // Acesso especial / visibilidade
      _temAlguma([
        'pode_acessar_eventos',
        'podeAcessarEventos',
        'pode_ver_eventos',
      ]),
      _temAlguma([
        'pode_acessar_associacao',
        'podeAcessarAssociacao',
      ]),
      _temAlguma([
        'pode_acessar_rifas',
        'podeAcessarRifas',
      ]),
      _temAlguma([
        'pode_acessar_uniformes',
        'podeAcessarUniformes',
      ]),
      _temAlguma([
        'pode_acessar_inscricoes',
        'podeAcessarInscricoes',
      ]),
      _temAlguma([
        'pode_mostrar_alunos_drawer',
        'podeMostrarAlunosDrawer',
      ]),

      // Administração flexível
      _temAlguma([
        'pode_gerenciar_usuarios',
      ]),
    ]);

    final admin = _isAdminLocal;

    return _DrawerPermissoes(
      temEventos: results[0],
      temAssociacao: results[1],
      temRifas: results[2],
      temUniformes: results[3],
      temInscricoes: results[4],
      temAlunos: admin || results[5],
      temAdminApp: admin || results[6],
    );
  }

  @override
  Widget build(BuildContext context) {
    final String displayName =
        userData['nome_completo']?.toString() ?? userData['name']?.toString() ?? 'Usuário';
    final String? photoUrl =
    (userData['foto_url'] ?? userData['foto_perfil_aluno'])?.toString();

    final t = context.uai;

    return Drawer(
      backgroundColor: t.background,
      child: SafeArea(
        top: false,
        child: Material(
          color: t.background,
          child: Column(
            children: [
              _buildDrawerHeader(context, displayName, photoUrl),
              Expanded(
                child: FutureBuilder<_DrawerPermissoes>(
                  future: _carregarPermissoesDrawer(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                        children: [
                          _buildLoadingSection(context),
                        ],
                      );
                    }

                    if (snapshot.hasError) {
                      debugPrint('Erro ao carregar permissões do drawer: ${snapshot.error}');
                    }

                    final permissoes = snapshot.data ?? const _DrawerPermissoes();

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                      children: [
                        if (!_contaAtiva)
                          _buildContaInativaAviso(context)
                        else ...[
                          _buildAcessosEspeciaisSection(context, permissoes),
                          _buildAdministracaoSection(context, permissoes),
                          if (!permissoes.temAlgumAcesso &&
                              !permissoes.temAlgumaAdministracao)
                            _buildSemPermissaoAviso(context),
                        ],
                      ],
                    );
                  },
                ),
              ),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  // ========== HEADER DO DRAWER ==========
  Widget _buildDrawerHeader(
      BuildContext context,
      String displayName,
      String? photoUrl,
      ) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);
    final statusColor = _contaAtiva ? t.success : t.error;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 18,
        left: 16,
        right: 16,
        bottom: 18,
      ),
      decoration: BoxDecoration(
        color: t.background,
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: t.primaryGradient,
          borderRadius: BorderRadius.circular(t.cardRadius + 4),
          border: Border.all(color: onPrimary.withOpacity(0.13)),
          boxShadow: t.cardShadow,
        ),
        child: Row(
          children: [
            InkWell(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfileScreen()),
                );
              },
              borderRadius: BorderRadius.circular(t.cardRadius),
              child: Container(
                width: 68,
                height: 68,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: onPrimary.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(t.cardRadius - 2),
                  border: Border.all(color: onPrimary.withOpacity(0.18)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(t.cardRadius - 5),
                  child: _buildAvatarImage(
                    context: context,
                    photoUrl: photoUrl,
                    displayName: displayName,
                    isDrawer: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onPrimary,
                      fontSize: 17,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    currentUser?.email ?? 'Email não encontrado',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onPrimary.withOpacity(0.78),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _buildHeaderBadge(context, 'UAI CAPOEIRA'),
                      _buildHeaderBadge(context, 'PESO $_pesoPermissao'),
                      _buildHeaderBadge(
                        context,
                        _contaAtiva ? 'ATIVA' : 'INATIVA',
                        color: statusColor,
                      ),
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

  Widget _buildHeaderBadge(
      BuildContext context,
      String label, {
        Color? color,
      }) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);
    final badgeColor = color ?? onPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(color == null ? 0.14 : 0.18),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: badgeColor.withOpacity(color == null ? 0.16 : 0.28),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color == null ? onPrimary : _ensureVisible(color, t.primary),
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  // ========== SEÇÃO: ACESSOS ESPECIAIS ==========
  Widget _buildAcessosEspeciaisSection(
      BuildContext context,
      _DrawerPermissoes permissoes,
      ) {
    if (!permissoes.temAlgumAcesso) return SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSecaoTitulo(context, 'ACESSOS ESPECIAIS'),
        if (permissoes.temEventos)
          _buildMenuItem(
            context: context,
            icone: Icons.event_rounded,
            cor: context.uai.info,
            titulo: 'EVENTOS',
            subtitulo: 'Calendário e gestão de eventos',
            tela: const EventosScreen(),
          ),
        if (permissoes.temAssociacao)
          _buildMenuItem(
            context: context,
            icone: Icons.people_outline_rounded,
            cor: context.uai.associacao,
            titulo: 'ASSOCIAÇÃO',
            subtitulo: 'Gerencie associações',
            tela: const EmDesenvolvimentoScreen(
              titulo: 'ASSOCIAÇÃO',
              icone: Icons.people_outline,
            ),
          ),
        if (permissoes.temRifas)
          _buildMenuItem(
            context: context,
            icone: Icons.confirmation_number_rounded,
            cor: context.uai.warning,
            titulo: 'RIFAS',
            subtitulo: 'Gerencie rifas e sorteios',
            tela: const EmDesenvolvimentoScreen(
              titulo: 'RIFAS',
              icone: Icons.confirmation_number,
            ),
          ),
        if (permissoes.temUniformes)
          _buildMenuItem(
            context: context,
            icone: Icons.shopping_bag_rounded,
            cor: context.uai.success,
            titulo: 'UNIFORMES',
            subtitulo: 'Gestão de estoque e vendas',
            tela: const UniformesScreen(),
          ),
        if (permissoes.temInscricoes)
          _buildMenuItem(
            context: context,
            icone: Icons.app_registration_rounded,
            cor: context.uai.inscricoes,
            titulo: 'INSCRIÇÕES',
            subtitulo: 'Gerenciar inscrições pendentes',
            tela: const GerenciarInscricoesScreen(),
          ),
        _buildDivider(context),
      ],
    );
  }

  // ========== SEÇÃO: ADMINISTRAÇÃO ==========
  Widget _buildAdministracaoSection(
      BuildContext context,
      _DrawerPermissoes permissoes,
      ) {
    if (!permissoes.temAlgumaAdministracao) return SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSecaoTitulo(context, 'ADMINISTRAÇÃO'),
        if (permissoes.temAlunos)
          _buildMenuItem(
            context: context,
            icone: Icons.people_rounded,
            cor: context.uai.primary,
            titulo: 'ALUNOS',
            subtitulo: 'Gerenciar alunos',
            tela: const AlunosScreen(),
          ),
        if (permissoes.temAdminApp)
          _buildMenuItem(
            context: context,
            icone: Icons.admin_panel_settings_rounded,
            cor: context.uai.accent,
            titulo: 'ADMIN APP',
            subtitulo: 'Configurações do sistema',
            tela: const AdminScreen(),
          ),
        _buildDivider(context),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    final t = context.uai;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: t.background,
          border: Border(top: BorderSide(color: t.border)),
        ),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: t.border),
            boxShadow: t.softShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BotaoAtualizarMelhorado(),
              const SizedBox(height: 8),
              _buildLogoutButton(context),
            ],
          ),
        ),
      ),
    );
  }

  // ========== BOTÃO SAIR ==========
  Widget _buildLogoutButton(BuildContext context) {
    final t = context.uai;
    final bg = _ensureVisible(t.error, t.card);
    final fg = _readableOn(bg);

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onLogout,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.buttonRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
          elevation: 0,
        ),
        icon: const Icon(Icons.logout_rounded, size: 20),
        label: const Text('SAIR DO APP'),
      ),
    );
  }

  // ========== WIDGETS AUXILIARES ==========
  Widget _buildSecaoTitulo(BuildContext context, String titulo) {
    final t = context.uai;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: t.primary,
              borderRadius: BorderRadius.circular(99),
              boxShadow: [
                BoxShadow(
                  color: t.primary.withOpacity(0.30),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              titulo,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: t.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required BuildContext context,
    required IconData icone,
    required Color cor,
    required String titulo,
    required String subtitulo,
    required Widget tela,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(cor, t.card);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => tela),
            );
          },
          borderRadius: BorderRadius.circular(t.cardRadius),
          splashColor: accent.withOpacity(0.12),
          highlightColor: accent.withOpacity(0.06),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.cardRadius),
              border: Border.all(color: t.border),
              boxShadow: t.softShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(accent.withOpacity(0.13), t.cardAlt),
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                    border: Border.all(color: accent.withOpacity(0.20)),
                  ),
                  child: Icon(icone, color: accent, size: 22),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: t.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.2,
                          color: t.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: t.cardAlt,
                    shape: BoxShape.circle,
                    border: Border.all(color: t.border),
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: t.textMuted,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingSection(BuildContext context) {
    final t = context.uai;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: t.border),
          boxShadow: t.softShadow,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: t.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Carregando permissões...',
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSemPermissaoAviso(BuildContext context) {
    return _buildInfoBox(
      context: context,
      icon: Icons.lock_outline_rounded,
      color: context.uai.warning,
      title: 'Nenhum acesso liberado',
      message: 'Peça para o administrador liberar suas permissões.',
    );
  }

  Widget _buildContaInativaAviso(BuildContext context) {
    return _buildInfoBox(
      context: context,
      icon: Icons.block_rounded,
      color: context.uai.error,
      title: 'Conta sem acesso',
      message: 'Sua conta não está ativa. Fale com o administrador.',
    );
  }

  Widget _buildInfoBox({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String title,
    required String message,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Color.alphaBlend(accent.withOpacity(0.10), t.card),
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: accent.withOpacity(0.22)),
          boxShadow: t.softShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(t.buttonRadius),
                border: Border.all(color: accent.withOpacity(0.22)),
              ),
              child: Icon(icon, color: accent, size: 23),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
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
        ),
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Divider(
        height: 1,
        thickness: 1,
        color: context.uai.border.withOpacity(0.75),
      ),
    );
  }

  Widget _buildAvatarImage({
    required BuildContext context,
    required String? photoUrl,
    required String displayName,
    bool isDrawer = false,
  }) {
    if (photoUrl == null || photoUrl.isEmpty) {
      return Container(
        color: context.uai.cardAlt,
        alignment: Alignment.center,
        child: Icon(
          Icons.person_rounded,
          size: isDrawer ? 36 : 60,
          color: context.uai.primary,
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: photoUrl,
      fit: BoxFit.cover,
      width: isDrawer ? 68 : 120,
      height: isDrawer ? 68 : 120,
      placeholder: (context, url) => Container(
        color: context.uai.cardAlt,
        alignment: Alignment.center,
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.uai.primary,
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: context.uai.cardAlt,
        alignment: Alignment.center,
        child: Icon(
          Icons.person_rounded,
          size: isDrawer ? 36 : 60,
          color: context.uai.primary,
        ),
      ),
    );
  }
}

class _DrawerPermissoes {
  final bool temEventos;
  final bool temAssociacao;
  final bool temRifas;
  final bool temUniformes;
  final bool temInscricoes;
  final bool temAlunos;
  final bool temAdminApp;

  const _DrawerPermissoes({
    this.temEventos = false,
    this.temAssociacao = false,
    this.temRifas = false,
    this.temUniformes = false,
    this.temInscricoes = false,
    this.temAlunos = false,
    this.temAdminApp = false,
  });

  bool get temAlgumAcesso =>
      temEventos || temAssociacao || temRifas || temUniformes || temInscricoes;

  bool get temAlgumaAdministracao => temAlunos || temAdminApp;
}

