import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/theme/app_theme_tokens.dart';
import 'package:uai_capoeira/modules/turmas/screens/tela_turma_screen.dart';
import 'package:uai_capoeira/modules/turmas/admin/vincular_aluno_inativo_turma_screen.dart';

class TurmasAcademiaScreen extends StatefulWidget {
  final String academiaId;
  final String academiaNome;
  final String academiaCidade;

  const TurmasAcademiaScreen({
    super.key,
    required this.academiaId,
    required this.academiaNome,
    required this.academiaCidade,
  });

  @override
  State<TurmasAcademiaScreen> createState() => _TurmasAcademiaScreenState();
}

class _TurmasAcademiaScreenState extends State<TurmasAcademiaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Connectivity _connectivity = Connectivity();

  bool _isLoading = true;
  bool _erroCarregamento = false;
  bool _atualizando = false;

  int _pesoUsuarioLogado = 1;
  Map<String, bool> _permissoes = {};
  List<Map<String, dynamic>> _turmas = [];
  String? _mensagemErro;
  DateTime? _ultimaAtualizacao;

  List<Map<String, dynamic>> _turmasCache = [];
  DateTime? _ultimoCacheTurmas;
  static const Duration _cacheValidade = Duration(minutes: 20);

  @override
  void initState() {
    super.initState();
    _carregarDadosIniciais();
  }

  bool _podeUsarCache() {
    if (_turmasCache.isEmpty || _ultimoCacheTurmas == null) return false;
    return DateTime.now().difference(_ultimoCacheTurmas!) <= _cacheValidade;
  }

  Future<bool> _temInternet() async {
    try {
      final dynamic result = await _connectivity.checkConnectivity();

      if (result is List<ConnectivityResult>) {
        return result.any((item) => item != ConnectivityResult.none);
      }

      if (result is ConnectivityResult) {
        return result != ConnectivityResult.none;
      }

      return true;
    } catch (e) {
      debugPrint('Erro ao verificar internet: $e');
      return false;
    }
  }

  Future<void> _carregarDadosIniciais() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _erroCarregamento = false;
      _mensagemErro = null;
    });

    try {
      await _carregarDadosUsuario();
      await _carregarTurmas();

      if (!mounted) return;
      setState(() {
        _ultimaAtualizacao = DateTime.now();
      });
    } catch (e) {
      debugPrint('Erro ao carregar dados iniciais: $e');

      if (!mounted) return;

      if (_turmasCache.isNotEmpty) {
        setState(() {
          _turmas = List<Map<String, dynamic>>.from(_turmasCache);
          _erroCarregamento = false;
        });
      } else {
        setState(() {
          _erroCarregamento = true;
          _mensagemErro = 'Não foi possível carregar as turmas agora.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _carregarDadosUsuario({bool forcarServidor = false}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _carregarUsuarioLogado(user.uid, forcarServidor: forcarServidor);
    await _carregarPermissoesUsuario(user.uid, forcarServidor: forcarServidor);
  }

  Future<void> _carregarUsuarioLogado(
      String uid, {
        bool forcarServidor = false,
      }) async {
    final sources = forcarServidor
        ? const [Source.server, Source.cache]
        : const [Source.cache, Source.server];

    for (final source in sources) {
      try {
        final userDoc = await _firestore
            .collection('usuarios')
            .doc(uid)
            .get(GetOptions(source: source));

        if (!userDoc.exists) continue;

        final userData = userDoc.data() ?? {};
        final rawPeso = userData['peso_permissao'];

        if (!mounted) return;
        setState(() {
          if (rawPeso is int) {
            _pesoUsuarioLogado = rawPeso;
          } else if (rawPeso is num) {
            _pesoUsuarioLogado = rawPeso.toInt();
          } else {
            _pesoUsuarioLogado =
                int.tryParse(rawPeso?.toString() ?? '') ?? _pesoUsuarioLogado;
          }
        });

        return;
      } catch (e) {
        debugPrint('Erro ao carregar usuário em $source: $e');
      }
    }
  }

  Future<void> _carregarPermissoesUsuario(
      String uid, {
        bool forcarServidor = false,
      }) async {
    final sources = forcarServidor
        ? const [Source.server, Source.cache]
        : const [Source.cache, Source.server];

    for (final source in sources) {
      try {
        final doc = await _firestore
            .collection('usuarios')
            .doc(uid)
            .collection('permissoes_usuario')
            .doc('configuracoes')
            .get(GetOptions(source: source));

        if (!doc.exists) continue;

        final data = doc.data() ?? {};

        if (!mounted) return;
        setState(() {
          _permissoes = {
            'pode_ativar_alunos': data['pode_ativar_alunos'] ?? false,
            'pode_adicionar_aluno': data['pode_adicionar_aluno'] ?? false,
            'pode_desativar_aluno': data['pode_desativar_aluno'] ?? false,
            'pode_editar_aluno': data['pode_editar_aluno'] ?? false,
            'pode_editar_chamada': data['pode_editar_chamada'] ?? false,
            'pode_excluir_aluno': data['pode_excluir_aluno'] ?? false,
            'pode_fazer_chamada': data['pode_fazer_chamada'] ?? false,
            'pode_gerenciar_usuarios': data['pode_gerenciar_usuarios'] ?? false,
            'pode_mudar_turma': data['pode_mudar_turma'] ?? false,
            'pode_visualizar_alunos': data['pode_visualizar_alunos'] ?? false,
            'pode_visualizar_relatorios':
            data['pode_visualizar_relatorios'] ?? false,
          };
        });

        return;
      } catch (e) {
        debugPrint('Erro ao carregar permissões em $source: $e');
      }
    }
  }

  Future<void> _carregarTurmas({bool forcarServidor = false}) async {
    try {
      if (!forcarServidor && _podeUsarCache()) {
        if (!mounted) return;

        setState(() {
          _turmas = List<Map<String, dynamic>>.from(_turmasCache);
          _erroCarregamento = false;
          _mensagemErro = null;
        });
        return;
      }

      final online = await _temInternet();

      if (!online) {
        if (_turmasCache.isNotEmpty) {
          if (!mounted) return;

          setState(() {
            _turmas = List<Map<String, dynamic>>.from(_turmasCache);
            _erroCarregamento = false;
            _mensagemErro = null;
          });
          return;
        }

        if (!mounted) return;

        setState(() {
          _erroCarregamento = true;
          _mensagemErro = 'Sem conexão no momento. Tente novamente em instantes.';
        });
        return;
      }

      final turmasSnapshot = await _firestore
          .collection('turmas')
          .where('academia_id', isEqualTo: widget.academiaId)
          .where('status', isEqualTo: 'ATIVA')
          .orderBy('nome')
          .get(const GetOptions(source: Source.server));

      await _processarTurmas(turmasSnapshot.docs);
    } catch (e) {
      debugPrint('Erro ao carregar turmas: $e');

      if (!mounted) return;

      if (_turmasCache.isNotEmpty) {
        setState(() {
          _turmas = List<Map<String, dynamic>>.from(_turmasCache);
          _erroCarregamento = false;
          _mensagemErro = null;
        });
      } else {
        setState(() {
          _erroCarregamento = true;
          _mensagemErro = 'Erro ao carregar turmas. Puxe para baixo para tentar novamente.';
        });
      }
    }
  }

  Future<void> _processarTurmas(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) async {
    final turmasAcessiveis = <Map<String, dynamic>>[];

    for (final doc in docs) {
      final data = doc.data();
      final pesoTurma = _parseInt(data['peso_do_usuario_para_acessar'], 1);

      if (_pesoUsuarioLogado < pesoTurma) continue;

      final turma = {
        'id': doc.id,
        'nome': data['nome'] ?? 'Sem nome',
        'nivel': data['nivel'] ?? '',
        'faixa_etaria': data['faixa_etaria'] ?? '',
        'alunos_ativos': _parseInt(data['alunos_ativos'], 0),
        'capacidade_maxima': _parseInt(data['capacidade_maxima'], 0),
        'dias_semana': _formatarDiasSemana(data),
        'horario': _formatarHorario(data),
        'duracao_aula': _parseInt(data['duracao_aula_minutos'], 0),
        'professor_principal': data['professor_principal'] ?? '',
        'cor_turma': data['cor_turma'] ?? '#059669',
        'idade_minima': _parseInt(data['idade_minima'], 0),
        'idade_maxima': _parseInt(data['idade_maxima'], 0),
        'nucleo': data['nucleo'] ?? '',
        'status': data['status'] ?? '',
        'ultima_atualizacao':
        data['ultima_atualizacao'] ?? FieldValue.serverTimestamp(),
        'logo_url': data['logo_url'] ?? '',
      };

      turmasAcessiveis.add(turma);
    }

    turmasAcessiveis.sort(
          (a, b) => a['nome'].toString().compareTo(b['nome'].toString()),
    );

    if (!mounted) return;

    setState(() {
      _turmas = turmasAcessiveis;
      _turmasCache = List<Map<String, dynamic>>.from(turmasAcessiveis);
      _ultimoCacheTurmas = DateTime.now();
      _ultimaAtualizacao = DateTime.now();
      _erroCarregamento = false;
      _mensagemErro = null;
    });
  }

  int _parseInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _formatarHorario(Map<String, dynamic> data) {
    if (data['horario_inicio'] != null && data['horario_fim'] != null) {
      return '${data['horario_inicio']} - ${data['horario_fim']}';
    }

    return data['horario_display']?.toString() ?? '';
  }

  String _formatarDiasSemana(Map<String, dynamic> data) {
    final display = data['dias_semana_display'];
    final dias = data['dias_semana'];

    if (display is List && display.isNotEmpty) {
      return display.join(', ');
    }

    if (dias is List && dias.isNotEmpty) {
      return dias.join(', ');
    }

    return '';
  }

  Future<void> _recarregarDados({bool mostrarMensagem = false}) async {
    final online = await _temInternet();

    if (!online) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sem conexão no momento.'),
          backgroundColor: context.uai.warning,
        ),
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      _atualizando = true;
      _erroCarregamento = false;
      _mensagemErro = null;
      _ultimoCacheTurmas = null;
      _turmasCache = [];
    });

    try {
      await _carregarDadosUsuario(forcarServidor: true);
      await _carregarTurmas(forcarServidor: true);

      if (mounted && mostrarMensagem) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_turmas.length} turma${_turmas.length == 1 ? '' : 's'} atualizada${_turmas.length == 1 ? '' : 's'}.',
            ),
            backgroundColor: context.uai.success,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _atualizando = false);
      }
    }
  }

  Future<void> _onRefresh() async {
    await _recarregarDados(mostrarMensagem: false);
  }

  Widget _buildLogoTurma(Map<String, dynamic> turma, {double size = 40}) {
    final corTurma = _getColorFromHex(turma['cor_turma']);

    if (turma['logo_url'] != null && turma['logo_url'].toString().isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.uai.cardAlt,
          border: Border.all(color: corTurma.withOpacity(0.28), width: 2),
        ),
        child: ClipOval(
          child: Image.network(
            turma['logo_url'],
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildFallbackLogo(turma, size, corTurma);
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;

              return Center(
                child: SizedBox(
                  width: size * 0.38,
                  height: size * 0.38,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(corTurma),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    return _buildFallbackLogo(turma, size, corTurma);
  }

  Widget _buildFallbackLogo(
      Map<String, dynamic> turma,
      double size,
      Color corTurma,
      ) {
    final nome = turma['nome']?.toString() ?? '';
    final iniciais = nome.isNotEmpty ? nome.substring(0, 1).toUpperCase() : 'T';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: corTurma.withOpacity(0.12),
        border: Border.all(color: corTurma.withOpacity(0.50), width: 2),
      ),
      child: Center(
        child: Text(
          iniciais,
          style: TextStyle(
            color: corTurma,
            fontWeight: FontWeight.w900,
            fontSize: size * 0.4,
          ),
        ),
      ),
    );
  }

  Color _getColorFromHex(String hexColor) {
    try {
      return Color(int.parse(hexColor.replaceFirst('#', '0xFF')));
    } catch (_) {
      return context.uai.uniformes;
    }
  }

  Color _capacidadeColor(double porcentagem) {
    if (porcentagem >= 90) return context.uai.error;
    if (porcentagem >= 70) return context.uai.warning;
    return context.uai.success;
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _onPrimaryText(UaiThemeTokens t) {
    return _readableOn(t.primary);
  }

  Color _onPrimarySoft(UaiThemeTokens t, double opacity) {
    return _onPrimaryText(t).withOpacity(opacity);
  }

  Widget _buildTurmaCard(Map<String, dynamic> turma) {
    final t = context.uai;
    final alunosAtivos = _parseInt(turma['alunos_ativos'], 0);
    final capacidade = _parseInt(turma['capacidade_maxima'], 0);
    final porcentagem = capacidade > 0 ? (alunosAtivos / capacidade) * 100 : 0.0;
    final corTurma = _getColorFromHex(turma['cor_turma']);
    final capacidadeColor = _capacidadeColor(porcentagem);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius - 4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TelaTurmaScreen(
                  turmaId: turma['id'],
                  turmaNome: turma['nome'],
                  academiaId: widget.academiaId,
                  academiaNome: widget.academiaNome,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(t.cardRadius - 4),
          splashColor: corTurma.withOpacity(0.10),
          highlightColor: corTurma.withOpacity(0.06),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.cardRadius - 4),
              border: Border.all(color: t.border),
              boxShadow: t.softShadow,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final veryNarrow = constraints.maxWidth < 340;

                if (veryNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTurmaCardHeader(turma, corTurma, t),
                      const SizedBox(height: 9),
                      _buildTurmaInfos(turma, t),
                      const SizedBox(height: 10),
                      _buildCapacidadeBar(
                        alunosAtivos: alunosAtivos,
                        capacidade: capacidade,
                        porcentagem: porcentagem,
                        color: capacidadeColor,
                        tokens: t,
                        compact: true,
                      ),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildLogoTurma(turma, size: 50),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTurmaTitle(turma, corTurma, t),
                          const SizedBox(height: 8),
                          _buildTurmaInfos(turma, t),
                          const SizedBox(height: 9),
                          _buildCapacidadeBar(
                            alunosAtivos: alunosAtivos,
                            capacidade: capacidade,
                            porcentagem: porcentagem,
                            color: capacidadeColor,
                            tokens: t,
                            compact: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right_rounded, color: t.textMuted),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTurmaCardHeader(
      Map<String, dynamic> turma,
      Color corTurma,
      UaiThemeTokens t,
      ) {
    return Row(
      children: [
        _buildLogoTurma(turma, size: 50),
        const SizedBox(width: 11),
        Expanded(child: _buildTurmaTitle(turma, corTurma, t)),
        Icon(Icons.chevron_right_rounded, color: t.textMuted),
      ],
    );
  }

  Widget _buildTurmaTitle(
      Map<String, dynamic> turma,
      Color corTurma,
      UaiThemeTokens t,
      ) {
    final nivel = turma['nivel']?.toString() ?? '';
    final faixa = turma['faixa_etaria']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          turma['nome']?.toString() ?? 'Turma',
          style: TextStyle(
            fontSize: 15.2,
            fontWeight: FontWeight.w900,
            color: t.textPrimary,
            height: 1.10,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (nivel.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            nivel,
            style: TextStyle(
              fontSize: 12,
              color: t.textSecondary,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (faixa.isNotEmpty) ...[
          const SizedBox(height: 6),
          _smallPill(
            icon: Icons.groups_rounded,
            label: faixa,
            color: corTurma,
          ),
        ],
      ],
    );
  }

  Widget _buildTurmaInfos(Map<String, dynamic> turma, UaiThemeTokens t) {
    final dias = turma['dias_semana']?.toString() ?? '';
    final horario = turma['horario']?.toString() ?? '';

    if (dias.isEmpty && horario.isEmpty) {
      return SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 7,
      children: [
        if (dias.isNotEmpty)
          _infoPill(
            icon: Icons.calendar_today_rounded,
            text: dias,
            color: t.info,
          ),
        if (horario.isNotEmpty)
          _infoPill(
            icon: Icons.access_time_rounded,
            text: horario,
            color: t.warning,
          ),
      ],
    );
  }

  Widget _infoPill({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    final t = context.uai;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withOpacity(0.14)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 11.5,
                  color: t.textSecondary,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapacidadeBar({
    required int alunosAtivos,
    required int capacidade,
    required double porcentagem,
    required Color color,
    required UaiThemeTokens tokens,
    bool compact = false,
  }) {
    final value = capacidade > 0 ? (alunosAtivos / capacidade).clamp(0.0, 1.0) : 0.0;

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: value,
              backgroundColor: tokens.border,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: compact ? 6 : 8,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          '$alunosAtivos/$capacidade',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w900,
            color: tokens.textPrimary,
          ),
        ),
        SizedBox(width: 5),
        Text(
          '${porcentagem.toStringAsFixed(0)}%',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }

  Future<void> _abrirTelaVincularAluno() async {
    if (_permissoes['pode_ativar_alunos'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Você não tem permissão para ativar alunos. Entre em contato com um administrador.',
          ),
          backgroundColor: context.uai.error,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    final online = await _temInternet();
    if (!online) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Você precisa estar conectado à internet para ativar alunos inativos.',
          ),
          backgroundColor: context.uai.warning,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    if (_turmas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não há turmas disponíveis.'),
          backgroundColor: context.uai.warning,
        ),
      );
      return;
    }

    if (_turmas.length == 1) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VincularAlunoInativoTurmaScreen(
            turmaId: _turmas[0]['id'],
            turmaNome: _turmas[0]['nome'],
            academiaId: widget.academiaId,
            academiaNome: widget.academiaNome,
          ),
        ),
      );
    } else {
      _mostrarDialogoSelecionarTurma();
    }
  }

  void _mostrarDialogoSelecionarTurma() {
    final t = context.uai;

    final onPrimary = _onPrimaryText(t);

    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: t.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.cardRadius),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: t.primaryGradient,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(t.cardRadius),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: onPrimary.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(
                          Icons.group_add_rounded,
                          color: onPrimary,
                          size: 23,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Selecione uma turma',
                          style: TextStyle(
                            color: onPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    itemCount: _turmas.length,
                    itemBuilder: (context, index) {
                      final turma = _turmas[index];
                      final corTurma = _getColorFromHex(turma['cor_turma']);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: t.card,
                          borderRadius: BorderRadius.circular(t.cardRadius - 6),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      VincularAlunoInativoTurmaScreen(
                                        turmaId: turma['id'],
                                        turmaNome: turma['nome'],
                                        academiaId: widget.academiaId,
                                        academiaNome: widget.academiaNome,
                                      ),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                borderRadius:
                                BorderRadius.circular(t.cardRadius - 6),
                                border: Border.all(color: t.border),
                              ),
                              child: Row(
                                children: [
                                  _buildLogoTurma(turma, size: 44),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          turma['nome']?.toString() ?? 'Turma',
                                          style: TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w900,
                                            color: t.textPrimary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _descricaoCurtaTurma(turma),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: t.textSecondary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: corTurma,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('CANCELAR'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _descricaoCurtaTurma(Map<String, dynamic> turma) {
    final dias = turma['dias_semana']?.toString() ?? '';
    final horario = turma['horario']?.toString() ?? '';
    final alunos = turma['alunos_ativos']?.toString() ?? '0';
    final capacidade = turma['capacidade_maxima']?.toString() ?? '0';

    final partes = <String>[
      if (dias.isNotEmpty) dias,
      if (horario.isNotEmpty) horario,
      '$alunos/$capacidade alunos',
    ];

    return partes.join(' • ');
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
            'Turmas da Academia',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: appBarFg,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            widget.academiaNome,
            style: TextStyle(
              fontSize: 12.5,
              color: appBarFg.withOpacity(0.82),
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: MediaQuery.of(context).size.width < 380
              ? IconButton(
            tooltip: 'Ativar alunos inativos',
            onPressed: _abrirTelaVincularAluno,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            style: IconButton.styleFrom(
              foregroundColor: appBarFg,
              backgroundColor: appBarFg.withOpacity(0.12),
            ),
          )
              : TextButton.icon(
            onPressed: _abrirTelaVincularAluno,
            icon: Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: Text('INATIVOS'),
            style: TextButton.styleFrom(
              foregroundColor: appBarFg,
              backgroundColor: appBarFg.withOpacity(0.12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.buttonRadius),
                side: BorderSide(color: appBarFg.withOpacity(0.14)),
              ),
              textStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderResumo() {
    final t = context.uai;
    final onPrimary = _onPrimaryText(t);
    final totalAlunos = _turmas.fold<int>(
      0,
          (total, turma) => total + _parseInt(turma['alunos_ativos'], 0),
    );

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
            final narrow = constraints.maxWidth < 470;

            final iconBox = Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: onPrimary.withOpacity(0.14),
                borderRadius: BorderRadius.circular(t.cardRadius - 2),
                border: Border.all(color: onPrimary.withOpacity(0.16)),
              ),
              child: Icon(
                Icons.groups_3_rounded,
                color: onPrimary,
                size: 33,
              ),
            );

            final textBox = Column(
              crossAxisAlignment:
              narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                Text(
                  widget.academiaNome,
                  textAlign: narrow ? TextAlign.center : TextAlign.left,
                  style: TextStyle(
                    color: onPrimary,
                    fontSize: narrow ? 22 : 25,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 7),
                Text(
                  widget.academiaCidade.isEmpty
                      ? 'Turmas, horários e alunos em um só lugar.'
                      : '${widget.academiaCidade} • Turmas, horários e alunos em um só lugar.',
                  textAlign: narrow ? TextAlign.center : TextAlign.left,
                  style: TextStyle(
                    color: onPrimary.withOpacity(0.84),
                    fontSize: 13,
                    height: 1.32,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment:
                  narrow ? WrapAlignment.center : WrapAlignment.start,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _whiteChip(
                      icon: Icons.class_rounded,
                      label:
                      '${_turmas.length} turma${_turmas.length == 1 ? '' : 's'}',
                    ),
                    _whiteChip(
                      icon: Icons.people_rounded,
                      label: '$totalAlunos aluno${totalAlunos == 1 ? '' : 's'}',
                    ),
                    if (_ultimaAtualizacao != null)
                      _whiteChip(
                        icon: Icons.check_circle_rounded,
                        label: 'Atualizado',
                      ),
                  ],
                ),
              ],
            );

            if (narrow) {
              return Column(
                children: [
                  iconBox,
                  SizedBox(height: 14),
                  textBox,
                ],
              );
            }

            return Row(
              children: [
                iconBox,
                SizedBox(width: 16),
                Expanded(child: textBox),
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

  Widget _buildSectionHeader() {
    final t = context.uai;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
              child: Icon(Icons.list_alt_rounded, color: t.primary),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Turmas disponíveis',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                      color: t.textPrimary,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Puxe para baixo para atualizar os dados.',
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
            if (_atualizando)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: t.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
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
                'Carregando turmas...',
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

  Widget _buildErrorState() {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: _buildAppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(t.cardRadius),
              border: Border.all(color: t.border),
              boxShadow: t.softShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 58, color: t.error),
                SizedBox(height: 16),
                Text(
                  _mensagemErro ?? 'Erro ao carregar turmas.',
                  style: TextStyle(
                    fontSize: 15.5,
                    color: t.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: () => _recarregarDados(mostrarMensagem: true),
                  icon: Icon(Icons.refresh_rounded),
                  label: Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final t = context.uai;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: t.border),
            boxShadow: t.softShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.class_outlined, size: 72, color: t.textMuted),
              const SizedBox(height: 16),
              Text(
                'Nenhuma turma disponível',
                style: TextStyle(
                  fontSize: 18,
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                widget.academiaNome,
                style: TextStyle(
                  fontSize: 13,
                  color: t.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () => _recarregarDados(mostrarMensagem: true),
                icon: Icon(Icons.refresh_rounded),
                label: Text('Recarregar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_erroCarregamento && _turmas.isEmpty) {
      return _buildErrorState();
    }

    return Scaffold(
      backgroundColor: t.background,
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        color: t.primary,
        backgroundColor: t.surface,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeaderResumo()),
            SliverToBoxAdapter(child: _buildSectionHeader()),
            if (_turmas.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(),
              )
            else
              SliverLayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.crossAxisExtent;

                  if (width >= 900) {
                    return SliverPadding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 22),
                      sliver: SliverGrid(
                        delegate: SliverChildBuilderDelegate(
                              (context, index) => _buildTurmaCard(_turmas[index]),
                          childCount: _turmas.length,
                        ),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 560,
                          mainAxisExtent: 148,
                          mainAxisSpacing: 2,
                          crossAxisSpacing: 2,
                        ),
                      ),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.only(bottom: 22),
                    sliver: SliverList.builder(
                      itemCount: _turmas.length,
                      itemBuilder: (context, index) {
                        return _buildTurmaCard(_turmas[index]);
                      },
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
