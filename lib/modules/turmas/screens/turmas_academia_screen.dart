import 'package:uai_capoeira/core/access_simulation/access_simulation_controller.dart';
import 'package:uai_capoeira/core/access_simulation/mirror_academia_reader.dart';
import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:uai_capoeira/core/caca_bug/caca_bug_actions.dart';
import 'package:uai_capoeira/core/caca_bug/caca_bug_service.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/emergency_offline/emergency_offline_service.dart';
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
  int? _totalInativos;
  bool _cacaBugRegistrouEntrada = false;
  bool _cacaBugRegistrouCarregamentoTurmas = false;
  bool _cacaBugRegistrouErroCarregamento = false;

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
    AccessSimulationController.instance.addListener(_simulationChanged);
    _registrarEntradaCacaBug();
    _carregarDadosIniciais();
    _carregarTotalInativos();
  }

  @override
  void dispose() {
    AccessSimulationController.instance.removeListener(_simulationChanged);
    super.dispose();
  }

  void _simulationChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _turmas = [];
      _turmasCache = [];
      _ultimoCacheTurmas = null;
      _permissoes = {};
      _pesoUsuarioLogado = 1;
    });
    unawaited(_carregarDadosIniciais());
  }

  bool _blockUnreviewedChild() {
    if (!AccessSimulationController.instance.active) {
      return false;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Cobertura limitada no Modo Espelho: alunos, chamadas e ativação ainda não estão integrados.',
        ),
      ),
    );
    return true;
  }

  void _registrarEntradaCacaBug() {
    if (AccessSimulationController.instance.active) {
      return;
    }
    if (_cacaBugRegistrouEntrada) {
      return;
    }
    _cacaBugRegistrouEntrada = true;
    unawaited(
      CacaBugService.instance
          .registrarEvento(
            tipo: 'navegacao',
            acao: CacaBugActions.abriuTelaTurmasAcademia,
            descricao:
                'Usu\u00e1rio entrou nas turmas da academia ${widget.academiaNome}',
            tela: 'TurmasAcademiaScreen',
            arquivo: 'lib/modules/turmas/screens/turmas_academia_screen.dart',
            rota: '/academias/turmas',
            status: 'success',
            dados: {
              'academiaId': widget.academiaId,
              'academiaNome': widget.academiaNome,
              'academiaCidade': widget.academiaCidade,
            },
          )
          .then((_) => CacaBugService.instance.flush(force: true)),
    );
  }

  void _registrarCarregouTurmasCacaBug({required bool refreshManual}) {
    if (AccessSimulationController.instance.active) {
      return;
    }
    if (!refreshManual && _cacaBugRegistrouCarregamentoTurmas) {
      return;
    }
    if (!refreshManual) _cacaBugRegistrouCarregamentoTurmas = true;
    unawaited(
      CacaBugService.instance.registrarEvento(
        tipo: 'acao_usuario',
        acao: refreshManual
            ? CacaBugActions.atualizouTurmasAcademia
            : CacaBugActions.carregouTurmasAcademia,
        descricao: refreshManual
            ? 'Usu\u00e1rio atualizou turmas da academia ${widget.academiaNome}'
            : 'Usu\u00e1rio carregou ${_turmas.length} turma(s) da academia ${widget.academiaNome}',
        tela: 'TurmasAcademiaScreen',
        arquivo: 'lib/modules/turmas/screens/turmas_academia_screen.dart',
        rota: '/academias/turmas',
        status: 'success',
        dados: {
          'academiaId': widget.academiaId,
          'academiaNome': widget.academiaNome,
          'turmasCount': _turmas.length,
          'origem': refreshManual ? 'refresh_manual' : 'carregamento_inicial',
        },
      ),
    );
  }

  void _registrarErroCarregarTurmasCacaBug(Object erro) {
    if (AccessSimulationController.instance.active) {
      return;
    }
    if (_cacaBugRegistrouErroCarregamento) {
      return;
    }
    _cacaBugRegistrouErroCarregamento = true;
    unawaited(
      CacaBugService.instance.registrarErro(
        acao: CacaBugActions.erroCarregarTurmasAcademia,
        descricao: 'Erro ao carregar turmas da academia ${widget.academiaNome}',
        tela: 'TurmasAcademiaScreen',
        arquivo: 'lib/modules/turmas/screens/turmas_academia_screen.dart',
        rota: '/academias/turmas',
        erro: erro,
        dados: {
          'academiaId': widget.academiaId,
          'academiaNome': widget.academiaNome,
        },
      ),
    );
  }

  void _registrarAbriuTurmaCacaBug(Map<String, dynamic> turma) {
    if (AccessSimulationController.instance.active) {
      return;
    }
    unawaited(
      CacaBugService.instance
          .registrarEvento(
            tipo: 'acao_usuario',
            acao: CacaBugActions.abriuTurma,
            descricao:
                'Usu\u00e1rio abriu a turma ${turma['nome'] ?? 'sem nome'}',
            tela: 'TurmasAcademiaScreen',
            arquivo: 'lib/modules/turmas/screens/turmas_academia_screen.dart',
            rota: '/academias/turmas',
            status: 'success',
            dados: {
              'academiaId': widget.academiaId,
              'academiaNome': widget.academiaNome,
              'turmaId': turma['id'],
              'turmaNome': turma['nome'],
              'alunosCount': turma['alunos_ativos'],
              'horario': turma['horario'],
            },
          )
          .then((_) => CacaBugService.instance.flush(force: true)),
    );
  }

  bool _podeUsarCache() {
    if (_turmasCache.isEmpty || _ultimoCacheTurmas == null) {
      return false;
    }
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

  Future<void> _carregarTotalInativos() async {
    try {
      final resultado = await _firestore.collection('alunos')
          .where('academia_id', isEqualTo: widget.academiaId)
          .where('status_atividade', isEqualTo: 'INATIVO(A)')
          .count().get();
      if (mounted) setState(() => _totalInativos = resultado.count);
    } catch (e) {
      debugPrint('Contagem de alunos inativos indisponível: $e');
    }
  }

  Future<void> _carregarDadosIniciais() async {
    final revision = AccessSimulationController.instance.revision;
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
      _erroCarregamento = false;
      _mensagemErro = null;
    });

    try {
      await _carregarDadosUsuario();
      if (revision != AccessSimulationController.instance.revision) return;
      await _carregarTurmas();

      if (!mounted) {
        return;
      }
      setState(() {
        _ultimaAtualizacao = DateTime.now();
      });
    } catch (e) {
      _registrarErroCarregarTurmasCacaBug(e);
      debugPrint('Erro ao carregar dados iniciais: $e');

      if (!mounted) {
        return;
      }

      if (!AccessSimulationController.instance.active &&
          _turmasCache.isNotEmpty) {
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
    if (AccessSimulationController.instance.active) {
      final revision = AccessSimulationController.instance.revision;
      final service = PermissaoService();
      final peso = await service.getPesoUsuarioAtual();
      final permissoes = await service.getTodasPermissoes();
      if (!mounted ||
          revision != AccessSimulationController.instance.revision) {
        return;
      }
      setState(() {
        _pesoUsuarioLogado = peso;
        _permissoes = permissoes;
      });
      return;
    }
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }

    await _carregarUsuarioLogado(user.uid, forcarServidor: forcarServidor);
    await _carregarPermissoesUsuario(user.uid, forcarServidor: forcarServidor);
  }

  Future<void> _carregarUsuarioLogado(
    String uid, {
    bool forcarServidor = false,
  }) async {
    final revision = AccessSimulationController.instance.revision;
    final sources = forcarServidor
        ? const [Source.server, Source.cache]
        : const [Source.cache, Source.server];

    for (final source in sources) {
      try {
        final userDoc = await _firestore
            .collection('usuarios')
            .doc(uid)
            .get(GetOptions(source: source));

        if (AccessSimulationController.instance.active ||
            revision != AccessSimulationController.instance.revision) {
          return;
        }
        if (!userDoc.exists) continue;

        final userData = userDoc.data() ?? {};
        final rawPeso = userData['peso_permissao'];

        if (!mounted) {
          return;
        }
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
    final revision = AccessSimulationController.instance.revision;
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

        if (AccessSimulationController.instance.active ||
            revision != AccessSimulationController.instance.revision) {
          return;
        }
        if (!doc.exists) continue;

        final data = doc.data() ?? {};

        if (!mounted) {
          return;
        }
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

  Future<bool> _usarTurmasPacoteOffline() async {
    if (AccessSimulationController.instance.active) {
      return false;
    }
    final revision = AccessSimulationController.instance.revision;
    final snapshot = await EmergencyOfflineService.instance.read();
    if (AccessSimulationController.instance.active ||
        revision != AccessSimulationController.instance.revision) {
      return false;
    }
    final entries = (snapshot?['turmas'] as List?) ?? const [];
    if (snapshot == null) {
      return false;
    }
    final roster = (snapshot['alunos'] as List?) ?? const [];
    final selected =
        entries
            .whereType<Map>()
            .where((t) => t['academiaId']?.toString() == widget.academiaId)
            .map((t) {
              final id = (t['id'] ?? '').toString();
              return <String, dynamic>{
                ...Map<String, dynamic>.from(t),
                'id': id,
                'nome': t['nome'] ?? 'Turma',
                'alunos_ativos': roster
                    .where((a) => a is Map && a['turmaId'] == id)
                    .length,
                'capacidade_maxima': t['capacidade_maxima'] ?? 0,
                'status': 'ATIVA',
                'horario': t['horario'] ?? '',
                'dias_semana': t['dias_semana'] ?? '',
                'cor_turma': t['cor_turma'] ?? '#059669',
              };
            })
            .toList()
          ..sort(
            (a, b) => a['nome'].toString().compareTo(b['nome'].toString()),
          );
    if (!mounted) {
      return true;
    }
    setState(() {
      _turmas = selected;
      _turmasCache = List<Map<String, dynamic>>.from(selected);
      _ultimoCacheTurmas = DateTime.now();
      _erroCarregamento = false;
      _mensagemErro = null;
    });
    return true;
  }

  Future<void> _carregarTurmas({bool forcarServidor = false}) async {
    final revision = AccessSimulationController.instance.revision;
    if (AccessSimulationController.instance.active) {
      try {
        final rows = await MirrorAcademiaReader().carregarTurmas(
          widget.academiaId,
        );
        if (!mounted ||
            revision != AccessSimulationController.instance.revision) {
          return;
        }
        await _processarTurmas(rows);
      } catch (_) {
        if (!mounted ||
            revision != AccessSimulationController.instance.revision) {
          return;
        }
        setState(() {
          _turmas = [];
          _turmasCache = [];
          _erroCarregamento = true;
          _mensagemErro =
              'Leitura online indisponível no Modo Espelho. Tente atualizar.';
        });
      }
      return;
    }
    try {
      if (!forcarServidor && _podeUsarCache()) {
        if (!mounted) {
          return;
        }

        setState(() {
          _turmas = List<Map<String, dynamic>>.from(_turmasCache);
          _erroCarregamento = false;
          _mensagemErro = null;
        });
        return;
      }

      final online = await _temInternet();
      if (revision != AccessSimulationController.instance.revision) {
        return;
      }

      if (!online) {
        if (_turmasCache.isNotEmpty) {
          if (!mounted) {
            return;
          }

          setState(() {
            _turmas = List<Map<String, dynamic>>.from(_turmasCache);
            _erroCarregamento = false;
            _mensagemErro = null;
          });
          return;
        }

        if (await _usarTurmasPacoteOffline()) {
          return;
        }
        if (!mounted) {
          return;
        }
        setState(() {
          _erroCarregamento = true;
          _mensagemErro = 'Sem conexão e nenhum pacote local disponível.';
        });
        return;
      }

      final turmasSnapshot = await _firestore
          .collection('turmas')
          .where('academia_id', isEqualTo: widget.academiaId)
          .where('status', isEqualTo: 'ATIVA')
          .orderBy('nome')
          .get(const GetOptions(source: Source.server));

      if (revision != AccessSimulationController.instance.revision) {
        return;
      }
      await _processarTurmas(
        turmasSnapshot.docs
            .map((d) => <String, dynamic>{...d.data(), 'id': d.id})
            .toList(),
      );
      _registrarCarregouTurmasCacaBug(refreshManual: false);
    } catch (e) {
      _registrarErroCarregarTurmasCacaBug(e);
      debugPrint('Erro ao carregar turmas: $e');
      if (revision != AccessSimulationController.instance.revision) {
        return;
      }

      if (!mounted) {
        return;
      }

      if (_turmasCache.isNotEmpty) {
        setState(() {
          _turmas = List<Map<String, dynamic>>.from(_turmasCache);
          _erroCarregamento = false;
          _mensagemErro = null;
        });
      } else if (!await _usarTurmasPacoteOffline()) {
        setState(() {
          _erroCarregamento = true;
          _mensagemErro =
              'Erro ao carregar turmas. Puxe para baixo para tentar novamente.';
        });
      }
    }
  }

  Future<void> _processarTurmas(List<Map<String, dynamic>> docs) async {
    final turmasAcessiveis = <Map<String, dynamic>>[];

    for (final doc in docs) {
      final data = doc;
      final pesoTurma = _parseInt(data['peso_do_usuario_para_acessar'], 1);

      if (_pesoUsuarioLogado < pesoTurma) continue;

      final turma = {
        'id': doc['id'],
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

    if (!mounted) {
      return;
    }

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
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
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
    final revision = AccessSimulationController.instance.revision;
    final online = await _temInternet();
    if (revision != AccessSimulationController.instance.revision) return;

    if (!online) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sem conexão no momento.'),
          backgroundColor: context.uai.warning,
        ),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _atualizando = true;
      _erroCarregamento = false;
      _mensagemErro = null;
      _ultimoCacheTurmas = null;
      _turmasCache = [];
    });

    try {
      await _carregarDadosUsuario(forcarServidor: true);
      if (revision != AccessSimulationController.instance.revision) return;
      await _carregarTurmas(forcarServidor: true);
      _registrarCarregouTurmasCacaBug(refreshManual: true);

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
    await _carregarTotalInativos();
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
          border: Border.all(color: corTurma.withAlpha(71), width: 2),
        ),
        child: ClipOval(
          child: Image.network(
            turma['logo_url'],
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildFallbackLogo(turma, size, corTurma);
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) {
                return child;
              }

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
        color: corTurma.withAlpha(31),
        border: Border.all(color: corTurma.withAlpha(128), width: 2),
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
    if (porcentagem >= 90) {
      return context.uai.error;
    }
    if (porcentagem >= 70) {
      return context.uai.warning;
    }
    return context.uai.success;
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
    final temaEscuro =
        t.background.computeLuminance() < 0.45 ||
        t.surface.computeLuminance() < 0.45;

    if (temaEscuro) {
      return Colors.white;
    }

    return _readableOn(t.primary);
  }

  Widget _buildTurmaCard(Map<String, dynamic> turma, {bool gridMode = false}) {
    final t = context.uai;
    final alunosAtivos = _parseInt(turma['alunos_ativos'], 0);
    final capacidade = _parseInt(turma['capacidade_maxima'], 0);
    final porcentagem = capacidade > 0
        ? (alunosAtivos / capacidade) * 100
        : 0.0;
    final corTurma = _getColorFromHex(turma['cor_turma']);
    final capacidadeColor = _capacidadeColor(porcentagem);

    return Padding(
      padding: gridMode
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius - 4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            if (_blockUnreviewedChild()) {
              return;
            }
            _registrarAbriuTurmaCacaBug(turma);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) {
                  final nomeTurma = turma['nome']?.toString().trim() ?? '';
                  return TelaTurmaScreen(
                    turmaId: turma['id'],
                    turmaNome: nomeTurma.isEmpty ? 'Turma sem nome' : nomeTurma,
                    academiaId: widget.academiaId,
                    academiaNome: widget.academiaNome,
                  );
                },
              ),
            );
          },
          borderRadius: BorderRadius.circular(t.cardRadius - 4),
          splashColor: corTurma.withAlpha(26),
          highlightColor: corTurma.withAlpha(15),
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
                        mainAxisSize: MainAxisSize.min,
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
          _smallPill(icon: Icons.groups_rounded, label: faixa, color: corTurma),
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
          color: color.withAlpha(26),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withAlpha(36)),
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
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withAlpha(41)),
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
    final value = capacidade > 0
        ? (alunosAtivos / capacidade).clamp(0.0, 1.0)
        : 0.0;

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
    if (_blockUnreviewedChild()) {
      return;
    }
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
    if (!mounted) {
      return;
    }
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

    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => VincularAlunoInativoTurmaScreen(
          academiaId: widget.academiaId,
          academiaNome: widget.academiaNome,
          turmasDisponiveis: List<Map<String, dynamic>>.from(_turmas),
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    if (resultado == true) {
      await _carregarTurmas(forcarServidor: true);
      await _carregarTotalInativos();
    }
  }

  PreferredSizeWidget _buildAppBar() {
    final t = context.uai;

    final appBarBg = Theme.of(context).appBarTheme.backgroundColor ?? t.primary;
    final appBarFg =
        Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(appBarBg);

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
              color: appBarFg.withAlpha(209),
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Atualizar turmas e contadores',
          onPressed: _atualizando ? null : () async {
            await _onRefresh();
          },
          icon: _atualizando
              ? const SizedBox(width: 19, height: 19,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 6),
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
                color: onPrimary.withAlpha(36),
                borderRadius: BorderRadius.circular(t.cardRadius - 2),
                border: Border.all(color: onPrimary.withAlpha(41)),
              ),
              child: Icon(Icons.groups_3_rounded, color: onPrimary, size: 33),
            );

            final textBox = Column(
              crossAxisAlignment: narrow
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
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
                    color: onPrimary.withAlpha(214),
                    fontSize: 13,
                    height: 1.32,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: narrow
                      ? WrapAlignment.center
                      : WrapAlignment.start,
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
              return Column(children: [iconBox, SizedBox(height: 14), textBox]);
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

  Widget _whiteChip({required IconData icon, required String label}) {
    final t = context.uai;
    final onPrimary = _onPrimaryText(t);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: onPrimary.withAlpha(36),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: onPrimary.withAlpha(41)),
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _abrirTelaVincularAluno,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.cardRadius),
              border: Border.all(color: t.border),
            ),
            child: Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: t.primary.withAlpha(28),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.person_add_alt_1_rounded, color: t.primary),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Alunos inativos',
                    style: TextStyle(color: t.textPrimary,
                      fontSize: 15.5, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text('Toque para consultar e reativar um aluno.',
                    style: TextStyle(color: t.textSecondary,
                      fontSize: 11.5, height: 1.3)),
                  if (_totalInativos != null) ...[
                    const SizedBox(height: 6),
                    Text('$_totalInativos inativo(s) nesta academia',
                      style: TextStyle(color: t.primary,
                        fontSize: 11, fontWeight: FontWeight.w800)),
                  ],
                ],
              )),
              Icon(Icons.chevron_right_rounded, color: t.primary),
            ]),
          ),
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
                          (context, index) =>
                              _buildTurmaCard(_turmas[index], gridMode: true),
                          childCount: _turmas.length,
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 430,
                              mainAxisExtent: 200,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
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
