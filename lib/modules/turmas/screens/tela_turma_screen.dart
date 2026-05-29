import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/theme/app_theme_tokens.dart';
import 'package:uai_capoeira/modules/chamadas/screens/chamada_turma_screen.dart';
import 'package:uai_capoeira/modules/chamadas/screens/listas_chamada_screen.dart';
import 'package:uai_capoeira/modules/turmas/screens/alunos_turma_screen.dart';
import 'package:uai_capoeira/modules/turmas/screens/avaliacao_alunos_turma_screen.dart';
import 'package:uai_capoeira/modules/turmas/screens/dashboard_turmas_page.dart';

class TelaTurmaScreen extends StatefulWidget {
  final String turmaId;
  final String turmaNome;
  final String academiaId;
  final String academiaNome;

  const TelaTurmaScreen({
    super.key,
    required this.turmaId,
    required this.turmaNome,
    required this.academiaId,
    required this.academiaNome,
  });

  @override
  State<TelaTurmaScreen> createState() => _TelaTurmaScreenState();
}

class _TelaTurmaScreenState extends State<TelaTurmaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<dynamic>? _connectivitySubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _permissoesSub;

  bool _isLoading = true;
  bool _isLoadingPermissoes = true;
  bool _temInternet = true;

  Map<String, dynamic> _dadosTurma = {};
  Map<String, dynamic> _permissoes = {};

  Color _corTurmaFallback = const Color(0xFFB71C1C);

  @override
  void initState() {
    super.initState();
    _monitorarConexao();
    _carregarDadosTurma();
    _inicializarPermissoesInteligente();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _permissoesSub?.cancel();
    super.dispose();
  }

  void _monitorarConexao() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((result) {
      final online = _isOnlineFromConnectivity(result);
      final voltou = !_temInternet && online;

      if (!mounted) return;

      setState(() => _temInternet = online);

      if (voltou) {
        _recarregarPermissoes();
      }
    });

    _verificarInternetInicial();
  }

  Future<void> _verificarInternetInicial() async {
    try {
      final result = await _connectivity.checkConnectivity();
      if (!mounted) return;
      setState(() => _temInternet = _isOnlineFromConnectivity(result));
    } catch (_) {
      if (mounted) setState(() => _temInternet = false);
    }
  }

  bool _isOnlineFromConnectivity(dynamic result) {
    if (result is List<ConnectivityResult>) {
      return result.any((item) => item != ConnectivityResult.none);
    }

    if (result is ConnectivityResult) {
      return result != ConnectivityResult.none;
    }

    return true;
  }

  bool _temPermissao(String permissao) {
    final valor = _permissoes[permissao];

    if (valor == true) return true;
    if (valor is String) {
      final normalizado = valor.toLowerCase().trim();
      return normalizado == 'true' || normalizado == '1' || normalizado == 'sim';
    }
    if (valor is num) return valor == 1;

    return false;
  }

  Future<void> _inicializarPermissoesInteligente() async {
    final user = _auth.currentUser;

    if (user == null) {
      if (mounted) setState(() => _isLoadingPermissoes = false);
      return;
    }

    try {
      try {
        final cacheDoc = await _firestore
            .collection('usuarios')
            .doc(user.uid)
            .collection('permissoes_usuario')
            .doc('configuracoes')
            .get(const GetOptions(source: Source.cache));

        if (cacheDoc.exists && mounted) {
          setState(() {
            _permissoes = cacheDoc.data() ?? {};
            _isLoadingPermissoes = false;
          });
        }
      } catch (_) {}

      final online = await _temInternetAgora();

      if (online) {
        _configurarStreamPermissoes(user.uid);
      } else if (mounted) {
        setState(() => _isLoadingPermissoes = false);
      }
    } catch (e) {
      debugPrint('Erro ao inicializar permissões: $e');
      if (mounted) setState(() => _isLoadingPermissoes = false);
    }
  }

  void _configurarStreamPermissoes(String uid) {
    _permissoesSub?.cancel();

    _permissoesSub = _firestore
        .collection('usuarios')
        .doc(uid)
        .collection('permissoes_usuario')
        .doc('configuracoes')
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
        if (!snapshot.exists || !mounted) return;

        setState(() {
          _permissoes = snapshot.data() ?? {};
          _isLoadingPermissoes = false;
        });
      },
      onError: (error) {
        debugPrint('Erro no stream de permissões: $error');
        if (mounted) setState(() => _isLoadingPermissoes = false);
      },
    );
  }

  Future<void> _recarregarPermissoes() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore
          .collection('usuarios')
          .doc(user.uid)
          .collection('permissoes_usuario')
          .doc('configuracoes')
          .get(const GetOptions(source: Source.server));

      if (!mounted || !doc.exists) return;

      setState(() => _permissoes = doc.data() ?? {});
    } catch (e) {
      debugPrint('Erro ao recarregar permissões: $e');
    }
  }

  Future<bool> _temInternetAgora() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return _isOnlineFromConnectivity(result);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _temInternetParaAcao() async {
    final online = await _temInternetAgora();

    if (!online) {
      _mostrarMensagem(
        'Modo offline. Conecte-se à internet para esta ação.',
        context.uai.warning,
        icon: Icons.wifi_off_rounded,
      );
      return false;
    }

    return true;
  }

  Future<void> _carregarDadosTurma() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      DocumentSnapshot<Map<String, dynamic>> turmaDoc;

      try {
        turmaDoc = await _firestore
            .collection('turmas')
            .doc(widget.turmaId)
            .get(const GetOptions(source: Source.cache));
      } catch (_) {
        turmaDoc = await _firestore
            .collection('turmas')
            .doc(widget.turmaId)
            .get(const GetOptions(source: Source.server));
      }

      if (!mounted) return;

      if (turmaDoc.exists) {
        final data = turmaDoc.data() ?? {};

        setState(() {
          _dadosTurma = data;
          _corTurmaFallback = _getColorFromHex(
            data['cor_turma']?.toString() ?? '#B71C1C',
            fallback: context.uai.primary,
          );
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados da turma: $e');

      if (mounted) {
        _mostrarMensagem(
          'Erro ao carregar dados da turma.',
          context.uai.error,
          icon: Icons.error_outline_rounded,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _getColorFromHex(String hexColor, {Color? fallback}) {
    try {
      return Color(int.parse(hexColor.replaceFirst('#', '0xFF')));
    } catch (_) {
      return fallback ?? context.uai.primary;
    }
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _onPrimaryText(UaiThemeTokens t) {
    // Cabeçalhos com primaryGradient precisam ficar legíveis nos 4 temas oficiais.
    // No Verde Neon, o primary pode ser claro, mas o tema inteiro é dark;
    // se usar _readableOn(primary), o texto fica escuro e perde leitura no card.
    final temaEscuro = t.background.computeLuminance() < 0.45 ||
        t.surface.computeLuminance() < 0.45;

    if (temaEscuro) return Colors.white;

    return _readableOn(t.primary);
  }

  int _parseInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _turmaNome() {
    return _dadosTurma['nome']?.toString() ?? widget.turmaNome;
  }

  String _horarioDisplay() {
    final display = _dadosTurma['horario_display']?.toString() ?? '';
    if (display.isNotEmpty) return display;

    final inicio = _dadosTurma['horario_inicio']?.toString() ?? '';
    final fim = _dadosTurma['horario_fim']?.toString() ?? '';

    if (inicio.isNotEmpty && fim.isNotEmpty) {
      return '$inicio - $fim';
    }

    return '';
  }

  String _diasSemanaTexto() {
    final display = _dadosTurma['dias_semana_display'];
    final dias = _dadosTurma['dias_semana'];

    if (display is List && display.isNotEmpty) {
      return display.join(', ');
    }

    if (dias is List && dias.isNotEmpty) {
      return dias.join(', ');
    }

    return '';
  }

  Future<void> _validarEAbrirChamada() async {
    if (!_temPermissao('pode_fazer_chamada')) {
      _mostrarMensagem(
        'Você não tem permissão para realizar chamadas.',
        context.uai.error,
        icon: Icons.lock_rounded,
      );
      return;
    }

    if (!await _temInternetParaAcao()) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _mostrarMensagem(
        'Usuário não logado.',
        context.uai.error,
        icon: Icons.error_outline_rounded,
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChamadaTurmaScreen(
          turmaId: widget.turmaId,
          turmaNome: _turmaNome(),
          academiaId: widget.academiaId,
          academiaNome: widget.academiaNome,
          usuarioId: user.uid,
        ),
      ),
    );
  }

  Future<void> _validarEAbrirAvaliacaoAluno() async {
    if (!_temPermissao('pode_avaliar_aluno')) {
      _mostrarMensagem(
        'Você não tem permissão para avaliar alunos.',
        context.uai.error,
        icon: Icons.lock_rounded,
      );
      return;
    }

    if (!await _temInternetParaAcao()) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AvaliacaoAlunosTurmaScreen(
          turmaId: widget.turmaId,
          turmaNome: _turmaNome(),
          academiaId: widget.academiaId,
          academiaNome: widget.academiaNome,
        ),
      ),
    );
  }

  void _mostrarMensagem(
      String mensagem,
      Color cor, {
        IconData icon = Icons.info_outline_rounded,
      }) {
    final onColor = _readableOn(cor);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: onColor, size: 18),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                mensagem,
                style: TextStyle(
                  color: onColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: cor,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final t = context.uai;

    final appBarBg = Theme.of(context).appBarTheme.backgroundColor ?? t.primary;
    final appBarFg = Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(appBarBg);

    return AppBar(
      backgroundColor: appBarBg,
      foregroundColor: appBarFg,
      elevation: 0,
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _turmaNome().toUpperCase(),
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
              color: appBarFg,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            widget.academiaNome,
            style: TextStyle(
              fontSize: 12,
              color: appBarFg.withOpacity(0.82),
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        if (!_temInternet)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(Icons.wifi_off_rounded, color: t.warning, size: 19),
          ),
        IconButton(
          onPressed: _carregarDadosTurma,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Atualizar',
        ),
      ],
    );
  }

  Widget _buildLogoTurma({
    required String logoUrl,
    required UaiThemeTokens t,
    double size = 74,
  }) {
    if (logoUrl.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(t.cardRadius - 8),
          border: Border.all(color: t.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(t.cardRadius - 10),
          child: CachedNetworkImage(
            imageUrl: logoUrl,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => _fallbackLogo(t, size),
            placeholder: (_, __) => Center(
              child: SizedBox(
                width: size * 0.30,
                height: size * 0.30,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: t.primary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return _fallbackLogo(t, size);
  }

  Widget _fallbackLogo(UaiThemeTokens t, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _onPrimaryText(t).withOpacity(0.14),
        borderRadius: BorderRadius.circular(t.cardRadius - 8),
        border: Border.all(color: _onPrimaryText(t).withOpacity(0.16)),
      ),
      child: Icon(
        Icons.class_rounded,
        size: size * 0.46,
        color: _onPrimaryText(t),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final t = context.uai;
    final onPrimary = _onPrimaryText(t);
    final logoUrl = _dadosTurma['logo_url']?.toString() ?? '';
    final alunosAtivos = _parseInt(_dadosTurma['alunos_ativos'], 0);
    final capacidade = _parseInt(_dadosTurma['capacidade_maxima'], 0);
    final dias = _diasSemanaTexto();
    final horario = _horarioDisplay();
    final nivel = _dadosTurma['nivel']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: t.primaryGradient,
          borderRadius: BorderRadius.circular(t.cardRadius + 2),
          boxShadow: t.cardShadow,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 500;

            final logo = _buildLogoTurma(logoUrl: logoUrl, t: t, size: narrow ? 70 : 78);

            final content = Column(
              crossAxisAlignment:
              narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                Text(
                  _turmaNome().toUpperCase(),
                  textAlign: narrow ? TextAlign.center : TextAlign.left,
                  style: TextStyle(
                    color: onPrimary,
                    fontSize: narrow ? 23 : 27,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 7),
                Text(
                  widget.academiaNome,
                  textAlign: narrow ? TextAlign.center : TextAlign.left,
                  style: TextStyle(
                    color: onPrimary.withOpacity(0.84),
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 13),
                Wrap(
                  alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _whiteChip(
                      icon: Icons.people_rounded,
                      label: '$alunosAtivos/$capacidade alunos',
                    ),
                    if (dias.isNotEmpty)
                      _whiteChip(
                        icon: Icons.calendar_today_rounded,
                        label: dias,
                      ),
                    if (horario.isNotEmpty)
                      _whiteChip(
                        icon: Icons.access_time_rounded,
                        label: horario,
                      ),
                    if (nivel.isNotEmpty)
                      _whiteChip(
                        icon: Icons.star_rounded,
                        label: nivel,
                      ),
                  ],
                ),
              ],
            );

            if (narrow) {
              return Column(
                children: [
                  logo,
                  SizedBox(height: 14),
                  content,
                ],
              );
            }

            return Row(
              children: [
                logo,
                SizedBox(width: 16),
                Expanded(child: content),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _whiteChip({
    required IconData icon,
    required String label,
  }) {
    final t = context.uai;
    final onPrimary = _onPrimaryText(t);

    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
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
          SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: onPrimary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle() {
    final t = context.uai;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
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
            Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(
                color: t.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(t.buttonRadius),
              ),
              child: Icon(Icons.dashboard_customize_rounded, color: t.primary),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Painel da turma',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                      color: t.textPrimary,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Acesse as ações disponíveis para esta turma.',
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

  Widget _buildFunctionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    required String permissao,
  }) {
    if (!_temPermissao(permissao)) {
      return SizedBox.shrink();
    }

    final t = context.uai;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius - 6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(t.cardRadius - 6),
          splashColor: color.withOpacity(0.12),
          highlightColor: color.withOpacity(0.06),
          child: Container(
            constraints: const BoxConstraints(minHeight: 78),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.cardRadius - 6),
              border: Border.all(color: color.withOpacity(0.14)),
              boxShadow: t.softShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 47,
                  height: 47,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                  ),
                  child: Icon(icon, size: 25, color: color),
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
                        ),
                      ),
                      if (!_temInternet) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Icon(Icons.wifi_off_rounded, size: 12, color: t.warning),
                            const SizedBox(width: 4),
                            Text(
                              'offline',
                              style: TextStyle(
                                fontSize: 10,
                                color: t.warning,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActionCards() {
    return [
      _buildFunctionCard(
        icon: Icons.person_search_rounded,
        title: 'Ver alunos',
        subtitle: 'Lista completa de alunos',
        color: context.uai.associacao,
        permissao: 'pode_visualizar_alunos',
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AlunosTurmaScreen(
                turmaId: widget.turmaId,
                turmaNome: _turmaNome(),
                academiaId: widget.academiaId,
                academiaNome: widget.academiaNome,
              ),
            ),
          );
        },
      ),
      _buildFunctionCard(
        icon: Icons.people_alt_rounded,
        title: 'Fazer chamada',
        subtitle: 'Registrar presença dos alunos',
        color: context.uai.success,
        permissao: 'pode_fazer_chamada',
        onTap: _validarEAbrirChamada,
      ),
      _buildFunctionCard(
        icon: Icons.list_alt_rounded,
        title: 'Listas de chamada',
        subtitle: 'Histórico de presenças',
        color: context.uai.info,
        permissao: 'pode_ver_lista_de_chamada',
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ListasChamadaScreen(
                turmaId: widget.turmaId,
                turmaNome: _turmaNome(),
                academiaId: widget.academiaId,
                academiaNome: widget.academiaNome,
              ),
            ),
          );
        },
      ),
      _buildFunctionCard(
        icon: Icons.summarize_rounded,
        title: 'Resumo da turma',
        subtitle: 'Estatísticas e relatórios',
        color: context.uai.warning,
        permissao: 'pode_visualizar_relatorios',
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DashboardTurmasPage(
                turmaId: widget.turmaId,
                turmaNome: _turmaNome(),
                academiaId: widget.academiaId,
              ),
            ),
          );
        },
      ),
      _buildFunctionCard(
        icon: Icons.star_rate_rounded,
        title: 'Avaliação do aluno',
        subtitle: 'Comportamento, disciplina e evolução',
        color: context.uai.associacao,
        permissao: 'pode_avaliar_aluno',
        onTap: _validarEAbrirAvaliacaoAluno,
      ),
    ].where((widget) => widget is! SizedBox).toList();
  }

  Widget _buildLoadingScreen() {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: _buildAppBar(),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: t.border),
            boxShadow: t.softShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: t.primary),
              SizedBox(height: 16),
              Text(
                _temInternet ? 'Carregando turma...' : 'Modo offline',
                style: TextStyle(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyActions() {
    final t = context.uai;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: t.border),
          boxShadow: t.softShadow,
        ),
        child: Column(
          children: [
            Icon(Icons.lock_outline_rounded, size: 48, color: t.textMuted),
            SizedBox(height: 10),
            Text(
              'Nenhuma ação disponível',
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Seu usuário não possui permissões liberadas para esta turma.',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textSecondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _isLoadingPermissoes) {
      return _buildLoadingScreen();
    }

    final t = context.uai;
    final actions = _buildActionCards();

    return Scaffold(
      backgroundColor: t.background,
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        color: t.primary,
        backgroundColor: t.surface,
        onRefresh: () async {
          await _carregarDadosTurma();
          await _recarregarPermissoes();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeaderCard()),
            SliverToBoxAdapter(child: _buildSectionTitle()),
            if (actions.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyActions(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.crossAxisExtent;

                    if (width >= 900) {
                      return SliverGrid(
                        delegate: SliverChildBuilderDelegate(
                              (context, index) => actions[index],
                          childCount: actions.length,
                        ),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 430,
                          mainAxisExtent: 100,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 10,
                        ),
                      );
                    }

                    return SliverList.builder(
                      itemCount: actions.length,
                      itemBuilder: (context, index) => actions[index],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
