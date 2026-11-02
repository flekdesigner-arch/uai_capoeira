import 'package:uai_capoeira/core/access_simulation/access_simulation_controller.dart';
import 'package:uai_capoeira/core/access_simulation/simulation_session.dart';
import 'package:uai_capoeira/core/access_simulation/simulation_navigation_guard.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Telas
import 'package:uai_capoeira/modules/eventos/screens/eventos_screen.dart';
import 'package:uai_capoeira/modules/transportes/screens/transportes_screen.dart';
import 'package:uai_capoeira/modules/associacao/screens/associacao_hub_screen.dart';
import 'package:uai_capoeira/modules/uniformes/screens/uniformes_screen.dart';
import 'package:uai_capoeira/modules/rifas/screens/rifas_screen.dart';
import 'package:uai_capoeira/modules/alunos/screens/alunos_screen.dart';
import 'package:uai_capoeira/modules/sistema/admin/admin_screen.dart';
import 'package:uai_capoeira/modules/usuarios/screens/profile_screen.dart';
import 'package:uai_capoeira/shared/widgets/botao_atualizar_melhorado.dart';
import 'package:uai_capoeira/modules/inscricoes/admin/gerenciar_inscricoes_screen.dart';
import 'package:uai_capoeira/modules/inscricoes/services/inscricoes_pendentes_service.dart';
import 'package:uai_capoeira/modules/inscricoes/widgets/inscricoes_pending_badge.dart';
import 'package:uai_capoeira/modules/area_aluno/screens/escolher_aluno_vinculado_screen.dart';
import 'package:uai_capoeira/modules/area_aluno/services/area_aluno_google_service.dart';

// Services
import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class AppDrawer extends StatelessWidget {
  final Map<String, dynamic> userData;
  final User? currentUser;
  final Future<void> Function() onLogout;
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
      _onCard(context).withAlpha(173);

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
      return Color.alphaBlend(t.primary.withAlpha(87), t.surface);
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
          Color.alphaBlend(t.primary.withAlpha(71), t.surface),
          Color.alphaBlend(t.primary.withAlpha(112), t.card),
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
      _temAlguma([
        'pode_acessar_transportes',
        'podeAcessarTransportes',
        'pode_ver_transportes',
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
      temTransportes: results[1],
      temAssociacao: results[2],
      temRifas: results[3],
      temUniformes: results[4],
      temInscricoes: results[5],
      temAlunos: admin || results[6],
      temAdminApp: admin || results[7],
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
      shape: Border(right: BorderSide(color: t.border.withAlpha(217))),
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
        top: MediaQuery.of(context).padding.top + 10,
        left: 12,
        right: 12,
        bottom: 9,
      ),
      decoration: BoxDecoration(
        color: t.background,
        border: Border(bottom: BorderSide(color: t.border.withAlpha(140))),
      ),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          gradient: _drawerHeroGradient(context),
          borderRadius: BorderRadius.circular(t.cardRadius + 6),
          border: Border.all(color: onHero.withAlpha(33)),
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
                    if (SimulationNavigationGuard.intercept(context, module: 'Perfil')) return;
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
                    width: 58,
                    height: 58,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: onHero.withAlpha(41),
                      borderRadius: BorderRadius.circular(t.cardRadius + 1),
                      border: Border.all(color: onHero.withAlpha(46)),
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
                const SizedBox(width: 11),
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
                          fontSize: 15.2,
                          height: 1.07,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        AccessSimulationController.instance.active ? 'Perfil simulado • somente leitura' : (currentUser?.email ?? 'Email n\u00e3o encontrado'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onHero.withAlpha(199),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 5,
                        children: [
                          _buildHeaderBadge(
                            context,
                            (userData['tipo']?.toString().trim().isNotEmpty ?? false)
                                ? userData['tipo'].toString().toUpperCase()
                                : 'USUÁRIO',
                          ),
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
            const SizedBox(height: 9),
            InkWell(
              onTap: () {
                if (SimulationNavigationGuard.intercept(context, module: 'Perfil')) return;
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfileScreen(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(t.buttonRadius),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: onHero.withAlpha(28),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: onHero.withAlpha(33)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.account_circle_rounded, color: onHero, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ver meu perfil e prefer\u00eancias',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onHero.withAlpha(230),
                          fontSize: 11.3,
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
        color: badgeColor.withAlpha(color == null ? 33 : 46),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: badgeColor.withAlpha(color == null ? 41 : 77),
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

  // ========== SECAO: ACESSOS ESPECIAIS ==========
  Widget _buildAcessosEspeciaisSection(
    BuildContext context,
    _DrawerPermissoes permissoes,
  ) {
    if (!permissoes.temAlgumAcesso) return const SizedBox.shrink();

    final itens = <Widget>[
      if (permissoes.temEventos)
        _buildMenuItem(
          context: context,
          icone: Icons.event_rounded,
          cor: context.uai.info,
          titulo: 'EVENTOS',
          subtitulo: 'Calendário e gestão de eventos',
          tela: const EventosScreen(),
          mirrorDestination: MirrorDestination.events,
        ),
      if (permissoes.temTransportes)
        _buildMenuItem(
          context: context,
          icone: Icons.directions_bus_filled_rounded,
          cor: context.uai.warning,
          titulo: 'TRANSPORTES',
          subtitulo: 'Viagens, vagas e pagamentos',
          tela: const TransportesScreen(),
          mirrorDestination: MirrorDestination.transportes,
        ),
      if (permissoes.temAssociacao)
        _buildMenuItem(
          context: context,
          icone: Icons.people_outline_rounded,
          cor: context.uai.associacao,
          titulo: 'ASSOCIAÇÃO',
          subtitulo: 'Financeiro, associados, ofícios e patrimônio',
          tela: const AssociacaoHubScreen(),
        ),
      if (permissoes.temRifas)
        _buildMenuItem(
          context: context,
          icone: Icons.confirmation_number_rounded,
          cor: context.uai.warning,
          titulo: 'RIFAS',
          subtitulo: 'Gerencie rifas e sorteios',
          tela: const RifasScreen(),
          mirrorDestination: MirrorDestination.rifas,
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
        StreamBuilder<int>(
          stream: AccessSimulationController.instance.active
              ? Stream<int>.value(0)
              : InscricoesPendentesService().watchPendentes(),
          builder: (context, snapshot) {
            final pendentes = snapshot.data ?? 0;
            return PendingPulse(
              active: pendentes > 0,
              child: _buildMenuItem(
                context: context,
                icone: Icons.app_registration_rounded,
                cor: context.uai.inscricoes,
                titulo: 'INSCRIÇÕES',
                subtitulo: pendentes > 0
                    ? '$pendentes ${pendentes == 1 ? 'inscrição pendente' : 'inscrições pendentes'}'
                    : 'Gerenciar inscrições pendentes',
                tela: const GerenciarInscricoesScreen(),
                badgeCount: pendentes,
              ),
            );
          },
        ),
    ];

    return _DrawerCollapsibleSection(
      storageKey: 'drawer_acessos_especiais_aberto',
      title: 'ACESSOS ESPECIAIS',
      initiallyExpanded: true,
      children: itens,
    );
  }

  // ========== SECAO: ADMINISTRACAO ==========
  Widget _buildAdministracaoSection(
    BuildContext context,
    _DrawerPermissoes permissoes,
  ) {
    if (!permissoes.temAlgumaAdministracao) return const SizedBox.shrink();

    final itens = <Widget>[
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
    ];

    return _DrawerCollapsibleSection(
      storageKey: 'drawer_administracao_aberto',
      title: 'ADMINISTRAÇÃO',
      initiallyExpanded: true,
      children: itens,
    );
  }

  Widget _buildMinhaAreaAlunoSection(BuildContext context) {
    if (AccessSimulationController.instance.active) return const ListTile(leading: Icon(Icons.info_outline), title: Text('Área do Aluno: cobertura limitada'));
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
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 9),
        decoration: BoxDecoration(
          color: t.background,
          border: Border(top: BorderSide(color: t.border.withAlpha(158))),
        ),
        child: Row(
          children: [
            Expanded(child: AccessSimulationController.instance.active
              ? TextButton(onPressed: SimulationSession.instance.stop, child: const Text('Sair do Modo Espelho'))
              : const BotaoAtualizarMelhorado()),
            const SizedBox(width: 5),
            Tooltip(
              message: 'Sair do app',
              child: Material(
                color: Color.alphaBlend(t.error.withAlpha(20), t.card),
                borderRadius: BorderRadius.circular(t.buttonRadius),
                child: InkWell(
                  onTap: () async => _sairDoApp(context),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                    child: Icon(
                      Icons.logout_rounded,
                      size: 19,
                      color: _ensureVisible(t.error, t.card),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sairDoApp(BuildContext context) async {
    if (AccessSimulationController.instance.active) { SimulationSession.instance.stop(); return; }
    // A preferência visual pertence ao dispositivo/usuário e deve continuar
    // aplicada nas telas públicas de Login/Cadastro. Não force tema claro no
    // logout: apenas encerre a sessão autenticada.
    await onLogout();
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
                  color: accent.withAlpha(77),
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
    int badgeCount = 0,
    MirrorDestination? mirrorDestination,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(cor, t.card);
    final onCard = _onCard(context);
    final onMuted = _onCardMuted(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            final navigator = Navigator.of(context);
            if (AccessSimulationController.instance.active) {
              if (mirrorDestination == null) {
                SimulationNavigationGuard.intercept(context, module: titulo);
                return;
              }
              final allowed = await SimulationNavigationGuard().canEnter(mirrorDestination);
              if (!context.mounted) return;
              if (!allowed) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Acesso negado. Verifique as permissões do perfil e a autorização administrativa.')));
                return;
              }
            }
            navigator.pop();
            navigator.push(MaterialPageRoute(builder: (context) => tela));
          },
          splashColor: accent.withAlpha(28),
          highlightColor: accent.withAlpha(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 58),
            decoration: BoxDecoration(
              border: Border.all(color: t.border.withAlpha(209)),
              borderRadius: BorderRadius.circular(t.cardRadius),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 34,
                  margin: const EdgeInsets.only(left: 5),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 39,
                  height: 39,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(accent.withAlpha(33), t.cardAlt),
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                    border: Border.all(color: accent.withAlpha(51)),
                  ),
                  child: Icon(icone, color: accent, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.2,
                            color: onCard,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.8,
                            color: onMuted,
                            height: 1.15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (badgeCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InscricoesPendingBadge(
                      count: badgeCount,
                      color: accent,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 9),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: accent.withAlpha(219),
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
          color: Color.alphaBlend(accent.withAlpha(26), t.card),
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: accent.withAlpha(56)),
          boxShadow: t.softShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent.withAlpha(31),
                borderRadius: BorderRadius.circular(t.buttonRadius),
                border: Border.all(color: accent.withAlpha(56)),
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
        color: context.uai.border.withAlpha(191),
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
          child: CircularProgressIndicator(strokeWidth: 2, color: primary),
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


class _DrawerCollapsibleSection extends StatefulWidget {
  final String storageKey;
  final String title;
  final bool initiallyExpanded;
  final List<Widget> children;

  const _DrawerCollapsibleSection({
    required this.storageKey,
    required this.title,
    required this.children,
    this.initiallyExpanded = true,
  });

  @override
  State<_DrawerCollapsibleSection> createState() =>
      _DrawerCollapsibleSectionState();
}

class _DrawerCollapsibleSectionState extends State<_DrawerCollapsibleSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(widget.storageKey);
      if (saved != null && mounted) setState(() => _expanded = saved);
    } catch (_) {}
  }

  Future<void> _toggle() async {
    final value = !_expanded;
    setState(() => _expanded = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(widget.storageKey, value);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final accent = _visible(t.primary, t.background);
    final text = _visible(t.textSecondary, t.background);

    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(t.buttonRadius),
            child: InkWell(
              onTap: _toggle,
              borderRadius: BorderRadius.circular(t.buttonRadius),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(7, 8, 5, 7),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 17,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 10.9,
                          fontWeight: FontWeight.w900,
                          color: text,
                          letterSpacing: 0.82,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: text.withAlpha(204),
                        size: 21,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ClipRect(
            child: AnimatedAlign(
              alignment: Alignment.topCenter,
              heightFactor: _expanded ? 1 : 0,
              duration: const Duration(milliseconds: 190),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _expanded ? 1 : 0,
                duration: const Duration(milliseconds: 140),
                child: Column(children: widget.children),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Divider(height: 1, color: t.border.withAlpha(133)),
            ),
        ],
      ),
    );
  }

  Color _visible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance()).abs();
    if (diff >= 0.24) return color;
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness(background.computeLuminance() < 0.45 ? 0.76 : 0.28)
        .toColor();
  }
}

class _DrawerPermissoes {
  final bool temEventos;
  final bool temTransportes;
  final bool temAssociacao;
  final bool temRifas;
  final bool temUniformes;
  final bool temInscricoes;
  final bool temAlunos;
  final bool temAdminApp;

  const _DrawerPermissoes({
    this.temEventos = false,
    this.temTransportes = false,
    this.temAssociacao = false,
    this.temRifas = false,
    this.temUniformes = false,
    this.temInscricoes = false,
    this.temAlunos = false,
    this.temAdminApp = false,
  });

  bool get temAlgumAcesso =>
      temEventos || temTransportes || temAssociacao || temRifas || temUniformes || temInscricoes;

  bool get temAlgumaAdministracao => temAlunos || temAdminApp;
}

// ============================================================
// Tela refatorada visualmente em 03/07/2026 as 10:55
// Refatoracao focada em tema dinamico, responsividade e layout adaptativo.
// Logica original preservada.
// ============================================================
