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
import 'package:uai_capoeira/modules/area_aluno/screens/escolher_aluno_vinculado_screen.dart';
import 'package:uai_capoeira/modules/area_aluno/services/area_aluno_google_service.dart';

// Services
import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/theme/app_theme_controller.dart';
import 'package:uai_capoeira/core/theme/app_theme_preset.dart';

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
    final status =
        userData['status_conta']?.toString().toLowerCase().trim() ?? '';
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

  Color _onCard(BuildContext context) => _readableOn(context.uai.card);

  Color _onCardMuted(BuildContext context) =>
      _onCard(context).withOpacity(0.68);

  bool _temaNeonSobreFundoEscuro(BuildContext context) {
    final t = context.uai;
    final primary = t.primary;
    final hsl = HSLColor.fromColor(primary);

    return primary.computeLuminance() > 0.48 &&
        t.background.computeLuminance() < 0.34 &&
        t.surface.computeLuminance() < 0.40 &&
        hsl.saturation > 0.55;
  }

  Color _drawerHeroBase(BuildContext context) {
    final t = context.uai;

    if (_temaNeonSobreFundoEscuro(context)) {
      return Color.alphaBlend(t.primary.withOpacity(0.34), t.surface);
    }

    return t.primary;
  }

  Gradient _drawerHeroGradient(BuildContext context) {
    final t = context.uai;
    final base = _drawerHeroBase(context);

    if (_temaNeonSobreFundoEscuro(context)) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(t.primary.withOpacity(0.28), t.surface),
          Color.alphaBlend(t.primary.withOpacity(0.44), t.card),
        ],
      );
    }

    final hsl = HSLColor.fromColor(base);
    final end = hsl
        .withLightness((hsl.lightness - 0.08).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation + 0.05).clamp(0.0, 1.0))
        .toColor();

    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [base, end],
    );
  }

  Color _onHero(BuildContext context) {
    if (_temaNeonSobreFundoEscuro(context)) {
      return const Color(0xFFFFFFFF);
    }
    return _readableOn(_drawerHeroBase(context));
  }

  double _drawerWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    if (width >= 1180) return 372;
    if (width >= 720) return 358;
    if (width <= 360) return width * 0.94;
    return 342;
  }

  String _iniciais(String nome) {
    final partes = nome
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.trim().isNotEmpty)
        .toList();

    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first.characters.first.toUpperCase();

    return '${partes.first.characters.first}${partes.last.characters.first}'
        .toUpperCase();
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
      _temAlguma(['pode_acessar_associacao', 'podeAcessarAssociacao']),
      _temAlguma(['pode_acessar_rifas', 'podeAcessarRifas']),
      _temAlguma(['pode_acessar_uniformes', 'podeAcessarUniformes']),
      _temAlguma(['pode_acessar_inscricoes', 'podeAcessarInscricoes']),
      _temAlguma(['pode_mostrar_alunos_drawer', 'podeMostrarAlunosDrawer']),

      // Administração flexível
      _temAlguma(['pode_gerenciar_usuarios']),
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
        userData['nome_completo']?.toString() ??
            userData['name']?.toString() ??
            'Usuário';
    final String? photoUrl =
    (userData['foto_url'] ?? userData['foto_perfil_aluno'])?.toString();

    final t = context.uai;

    return Drawer(
      width: _drawerWidth(context),
      backgroundColor: t.background,
      shape: Border(
        right: BorderSide(color: t.border.withOpacity(0.85)),
      ),
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
                        padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                        children: [_buildLoadingSection(context)],
                      );
                    }

                    if (snapshot.hasError) {
                      debugPrint(
                        'Erro ao carregar permissões do drawer: ${snapshot.error}',
                      );
                    }

                    final permissoes =
                        snapshot.data ?? const _DrawerPermissoes();

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                      children: [
                        if (!_contaAtiva)
                          _buildContaInativaAviso(context)
                        else ...[
                          _buildMinhaAreaAlunoSection(context),
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
    final onHero = _onHero(context);
    final statusColor = _contaAtiva ? t.success : t.error;
    final visibleStatus = _ensureVisible(statusColor, _drawerHeroBase(context));

    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 14,
        left: 14,
        right: 14,
        bottom: 12,
      ),
      decoration: BoxDecoration(
        color: t.background,
        border: Border(bottom: BorderSide(color: t.border.withOpacity(0.55))),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: _drawerHeroGradient(context),
          borderRadius: BorderRadius.circular(t.cardRadius + 6),
          border: Border.all(color: onHero.withOpacity(0.13)),
          boxShadow: t.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProfileScreen(),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(t.cardRadius + 2),
                  child: Container(
                    width: 72,
                    height: 72,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: onHero.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(t.cardRadius + 1),
                      border: Border.all(color: onHero.withOpacity(0.18)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(t.cardRadius - 2),
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
                          color: onHero,
                          fontSize: 16.8,
                          height: 1.07,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        currentUser?.email ?? 'Email não encontrado',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onHero.withOpacity(0.78),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
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
                            color: visibleStatus,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfileScreen()),
                );
              },
              borderRadius: BorderRadius.circular(t.buttonRadius),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                decoration: BoxDecoration(
                  color: onHero.withOpacity(0.11),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: onHero.withOpacity(0.13)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.account_circle_rounded, color: onHero, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ver meu perfil e preferências',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onHero.withOpacity(0.90),
                          fontSize: 11.8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: onHero, size: 19),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBadge(BuildContext context, String label, {Color? color}) {
    final onHero = _onHero(context);
    final badgeColor = color ?? onHero;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(color == null ? 0.13 : 0.18),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: badgeColor.withOpacity(color == null ? 0.16 : 0.30),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color == null ? onHero : badgeColor,
          fontSize: 9.6,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.65,
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

  Widget _buildMinhaAreaAlunoSection(BuildContext context) {
    if (currentUser == null) return const SizedBox.shrink();

    return FutureBuilder<List<AlunoVinculadoGoogle>>(
      future: AreaAlunoGoogleService().buscarAlunosVinculados(),
      builder: (context, snapshot) {
        final alunos = snapshot.data ?? const <AlunoVinculadoGoogle>[];
        if (snapshot.connectionState == ConnectionState.waiting ||
            alunos.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSecaoTitulo(context, 'CONTA'),
            _buildMenuItem(
              context: context,
              icone: Icons.school_rounded,
              cor: context.uai.info,
              titulo: 'MINHA ÁREA DO ALUNO',
              subtitulo: alunos.length == 1
                  ? 'Abrir meu perfil vinculado'
                  : 'Escolher perfil vinculado',
              tela: alunos.length == 1
                  ? _AbrirAreaAlunoVinculadaScreen(aluno: alunos.first)
                  : EscolherAlunoVinculadoScreen(alunos: alunos),
            ),
            _buildDivider(context),
          ],
        );
      },
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
          border: Border(top: BorderSide(color: t.border.withOpacity(0.70))),
        ),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius + 2),
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

  Future<void> _sairDoApp(BuildContext context) async {
    try {
      final controller = AppThemeController.instance;

      if (!controller.initialized) {
        await controller.initialize();
      }

      await controller.apply(
        preset: UaiThemePreset.uaiClassico,
        mode: ThemeMode.light,
      );

      debugPrint('✅ Tema padrão restaurado ao sair do app');
    } catch (e) {
      debugPrint('⚠️ Erro ao restaurar tema padrão no logout: $e');
    }

    onLogout();
  }

  // ========== BOTÃO SAIR ==========
  Widget _buildLogoutButton(BuildContext context) {
    final t = context.uai;
    final bg = _ensureVisible(t.error, t.card);
    final fg = _readableOn(bg);

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () async {
          await _sairDoApp(context);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.buttonRadius + 1),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
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
    final accent = _ensureVisible(t.primary, t.background);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 15, 8, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(99),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(0.30),
                  blurRadius: 10,
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
                fontSize: 11.2,
                fontWeight: FontWeight.w900,
                color: _ensureVisible(t.textSecondary, t.background),
                letterSpacing: 0.85,
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
    final onCard = _onCard(context);
    final onMuted = _onCardMuted(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.5),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(t.cardRadius + 1),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => tela),
            );
          },
          borderRadius: BorderRadius.circular(t.cardRadius + 1),
          splashColor: accent.withOpacity(0.12),
          highlightColor: accent.withOpacity(0.06),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Color.alphaBlend(accent.withOpacity(0.035), t.card),
              borderRadius: BorderRadius.circular(t.cardRadius + 1),
              border: Border.all(color: accent.withOpacity(0.18)),
              boxShadow: t.softShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      accent.withOpacity(0.15),
                      t.cardAlt,
                    ),
                    borderRadius: BorderRadius.circular(t.buttonRadius + 1),
                    border: Border.all(color: accent.withOpacity(0.24)),
                  ),
                  child: Icon(icone, color: accent, size: 23),
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
                          fontSize: 13.8,
                          color: onCard,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.2,
                          color: onMuted,
                          height: 1.18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 31,
                  height: 31,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      accent.withOpacity(0.09),
                      t.cardAlt,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: accent.withOpacity(0.13)),
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: accent,
                    size: 22,
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
    final onCard = _onCardMuted(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
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
                  color: onCard,
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
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
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
                      color: _onCardMuted(context),
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
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    if (photoUrl == null || photoUrl.isEmpty) {
      return Container(
        color: t.cardAlt,
        alignment: Alignment.center,
        child: Text(
          _iniciais(displayName),
          style: TextStyle(
            fontSize: isDrawer ? 22 : 30,
            color: primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: photoUrl,
      fit: BoxFit.cover,
      width: isDrawer ? 72 : 120,
      height: isDrawer ? 72 : 120,
      placeholder: (context, url) => Container(
        color: t.cardAlt,
        alignment: Alignment.center,
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: primary,
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: t.cardAlt,
        alignment: Alignment.center,
        child: Text(
          _iniciais(displayName),
          style: TextStyle(
            fontSize: isDrawer ? 22 : 30,
            color: primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _AbrirAreaAlunoVinculadaScreen extends StatefulWidget {
  final AlunoVinculadoGoogle aluno;

  const _AbrirAreaAlunoVinculadaScreen({required this.aluno});

  @override
  State<_AbrirAreaAlunoVinculadaScreen> createState() =>
      _AbrirAreaAlunoVinculadaScreenState();
}

class _AbrirAreaAlunoVinculadaScreenState
    extends State<_AbrirAreaAlunoVinculadaScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AreaAlunoGoogleService().abrirAreaAlunoVinculado(context, widget.aluno);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.uai.background,
      body: Center(
        child: CircularProgressIndicator(color: context.uai.primary),
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

// ============================================================
// Tela refatorada visualmente em 03/07/2026 às 10:55
// Refatoração focada em tema dinâmico, responsividade e layout adaptativo.
// Lógica original preservada.
// ============================================================
