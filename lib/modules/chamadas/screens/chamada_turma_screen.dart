import 'package:uai_capoeira/modules/disciplina/disciplina_dialog.dart'
    show DisciplinaStatusChip;
import 'package:uai_capoeira/core/services/uai_callable_client.dart';
import 'package:uai_capoeira/core/session_log/session_log_service.dart';
// chamada_turma_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uai_capoeira/modules/disciplina/disciplina_service.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uai_capoeira/modules/chamadas/services/lock_chamada_service.dart';
import 'package:uai_capoeira/modules/chamadas/services/aluno_foto_resolver.dart';
import 'package:uai_capoeira/core/image_cache/uai_student_photo.dart';

// The date picker can finish after this screen has been removed.
bool chamadaEspecialPodeAbrirConfirmacao(
  BuildContext context,
  DateTime? dataSelecionada,
) => dataSelecionada != null && context.mounted;

// ============================================
// TELA PRINCIPAL - CHAMADA TURMA (COM CLOUD FUNCTION)
// ============================================

class ChamadaTurmaScreen extends StatefulWidget {
  final String turmaId;
  final String turmaNome;
  final String academiaId;
  final String academiaNome;
  final String usuarioId;
  final DateTime? dataSelecionadaEspecial;

  const ChamadaTurmaScreen({
    super.key,
    required this.turmaId,
    required this.turmaNome,
    required this.academiaId,
    required this.academiaNome,
    required this.usuarioId,
    this.dataSelecionadaEspecial,
  });

  @override
  State<ChamadaTurmaScreen> createState() => _ChamadaTurmaScreenState();
}

class _ChamadaTurmaScreenState extends State<ChamadaTurmaScreen>
    with SingleTickerProviderStateMixin {
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _onPrimary() {
    final t = context.uai;
    final temaEscuro =
        t.background.computeLuminance() < 0.45 ||
        t.surface.computeLuminance() < 0.45;

    // No Verde Neon o primary pode ser claro, mas o tema inteiro é dark.
    // Em headers/progressos com gradiente, branco fica muito mais legível.
    if (temaEscuro) return Colors.white;

    return _readableOn(t.primary);
  }

  Color _onCard() => _readableOn(context.uai.card);
  Color _appBarBg() =>
      Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;
  Color _appBarFg() =>
      Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(_appBarBg());

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

  Color _saveButtonBg() {
    final t = context.uai;
    return _ensureVisible(t.primary, t.cardAlt);
  }

  Color _saveButtonFg() => _readableOn(_saveButtonBg());

  Color _headerAccent(Color color) {
    final bg = context.uai.primary;
    return _ensureVisible(color, bg);
  }

  bool get _ehChamadaEspecial => widget.dataSelecionadaEspecial != null;

  String _formatarDataDisciplina(dynamic value) {
    final texto = value?.toString().trim() ?? '';
    if (texto.isEmpty) return '--/--/----';
    final data = DateTime.tryParse(texto);
    if (data == null) return texto;
    return DateFormat('dd/MM/yyyy').format(data);
  }

  List<double> _matrizEscalaCinza() => const <double>[
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  Map<String, dynamic>? _eventoDisciplinaAluno(String alunoId) =>
      DisciplinaService.suspensaoAtual(
        _disciplinaPorAluno?[alunoId],
        _dataChamada,
      );

  Widget _buildChipSuspensoGrid(String alunoId) {
    final evento = _eventoDisciplinaAluno(alunoId);
    return DisciplinaStatusChip(
      estado: DisciplinaService.estado(
        _disciplinaPorAluno?[alunoId],
        _dataChamada,
        confirmado: _disciplinaPorAluno != null,
      ),
      retorno: _formatarDataDisciplina(
        evento?['data_retorno'] ?? evento?['fim_exclusivo'],
      ),
      onTap: () => _avisarSuspensao(alunoId),
    );
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🔥 ESTADOS PARA LOCK
  bool _verificandoLock = true;
  bool _podeAcessarChamada = false;
  Map<String, dynamic>? _ocupanteInfo;
  StreamSubscription<Map<String, dynamic>?>? _ocupacaoSubscription;

  // Estados principais
  bool _isLoading = true;
  bool _podeFazerChamada = false;
  bool _chamadaJaFeitaHoje = false;
  bool _salvandoChamada = false;

  String _mensagemAulaHoje = '';

  // Dados da chamada
  List<Map<String, dynamic>> _alunos = [];
  Map<String, bool> _presencas = {};
  // null = ainda não foi possível validar o status; falha fechada na UI.
  Map<String, Map<String, dynamic>>? _disciplinaPorAluno;

  bool _suspensoNaAula(String alunoId) =>
      DisciplinaService.suspenso(_disciplinaPorAluno?[alunoId], _dataChamada);
  bool _impedidoNaAula(String alunoId) =>
      _disciplinaPorAluno == null || _suspensoNaAula(alunoId);
  Timer? _disciplinaTimer;
  bool _consultandoDisciplina = false;
  final String _comandoCriacao =
      'criar_${DateTime.now().microsecondsSinceEpoch}';
  Future<void> _atualizarDisciplina() async {
    if (_consultandoDisciplina || _alunos.isEmpty) return;
    _consultandoDisciplina = true;
    Map<String, Map<String, dynamic>>? dados;
    try {
      dados = await DisciplinaService.buscarResumos(
        _alunos.map((a) => a['id'].toString()),
      );
    } catch (_) {
      dados = null;
    }
    _consultandoDisciplina = false;
    if (mounted) {
      setState(() {
        _disciplinaPorAluno = dados;
        for (final aluno in _alunos) {
          final id = aluno['id'].toString();
          if (_suspensoNaAula(id)) {
            _presencas[id] = false;
          }
        }
      });
    }
  }

  void _avisarSuspensao(String alunoId) {
    final resumo = _disciplinaPorAluno?[alunoId];
    final evento = DisciplinaService.suspensaoAtual(resumo, _dataChamada);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          evento == null
              ? 'Verificação pendente'
              : evento['tipo'] == 'expulsao'
              ? 'Aluno expulso'
              : 'Aluno suspenso',
        ),
        content: Text(
          evento == null
              ? 'Verificação disciplinar pendente. Conecte-se para carregar o status.'
              : 'Motivo: ${evento['motivo']}\nResponsável: ${evento['autor_nome']}\n'
                    'Início: ${evento['inicio']}\n${evento['tipo'] == 'expulsao' ? 'Expulsão ativa — reativação administrativa obrigatória' : 'Retorno em: ${evento['data_retorno'] ?? evento['fim_exclusivo']}'}',
        ),
        actions: [
          if (evento == null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _atualizarDisciplina();
              },
              child: const Text('Tentar novamente'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  final Map<String, String> _observacoes = {};
  DateTime _dataChamada = DateTime.now();

  // Controles
  final TextEditingController _observacaoController = TextEditingController();
  final TextEditingController _buscaController = TextEditingController();

  // 🔥 UX DA LISTA
  String _buscaAluno = '';
  String _filtroPresenca =
      'Todos'; // Todos, Presentes, Ausentes, Com observação
  bool _modoListaCompacta = false;

  // Dados da turma
  List<String> _diasTreinoTurma = [];
  String _tipoAulaHoje = 'OBJETIVA';
  Map<String, dynamic>? _chamadaExistente;

  // Dados do professor
  String _professorNome = 'Carregando...';
  String _professorId = '';
  bool _carregouDadosProfessor = false;
  bool _erroUsuarioId = false;

  // Permissões
  bool _isAdmin = false;
  final bool _modoExtraForcado = false;

  // UI
  final Map<String, Map<String, dynamic>> _graduacoesCache = {};

  // 🔥 OTIMIZAÇÃO DE UI / CACHE LOCAL
  Timer? _buscaDebounce;
  String _cacheAssinaturaFiltro = '';
  List<Map<String, dynamic>> _cacheAlunosFiltrados = [];
  bool _avisoLockPerdidoAberto = false;

  // Cache global enquanto o app está aberto para não baixar graduação/SVG toda hora.
  static final Map<String, Map<String, dynamic>> _graduacoesGlobalCache = {};

  // 🔥 ANIMAÇÕES
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // 🔥 CONTROLE DA ANIMAÇÃO DE SALVAMENTO
  String _statusMensagem = '';

  // 🧠 MODO BRINCADEIRA DA CHAMADA
  bool _modoBrincadeiraAtivo = false;
  bool _telepatiaAtiva = false;
  bool _telepatiaRodando = false;
  bool _telepatiaConcluida = false;
  bool _telepatiaJaIniciou = false;
  bool _telepatiaUsandoChamadaReal = false;
  bool _telepatiaRegistradaNoUsuario = false;
  Timer? _telepatiaTimer;
  String _telepatiaMensagem = '';
  final ScrollController _telepatiaScrollController = ScrollController();

  bool _chamadaInversaAtiva = false;
  bool _chamadaInversaRodando = false;
  bool _chamadaInversaJaIniciou = false;
  int _chamadaInversaToques = 0;
  Timer? _chamadaInversaTimer;

  // 🔥 PISCAR CARD QUANDO O INDICADOR EXIGE ALERTA
  Timer? _alertaPiscaTimer;
  bool _alertaPiscaLigado = false;

  bool _indicadoresAusenciaAtivo = true;
  bool _mostrarTextoUltimaPresencaIndicador = true;
  List<Map<String, dynamic>> _faixasIndicadoresAusencia = [];

  final Map<String, String> _diasAbreviados = {
    'SEGUNDA': 'seg',
    'TERÇA': 'ter',
    'TERCA': 'ter',
    'QUARTA': 'qua',
    'QUINTA': 'qui',
    'SEXTA': 'sex',
    'SÁBADO': 'sab',
    'SABADO': 'sab',
    'DOMINGO': 'dom',
  };

  @override
  void initState() {
    super.initState();

    // Inicializar animações
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutBack,
          ),
        );

    _alertaPiscaTimer = Timer.periodic(const Duration(milliseconds: 850), (_) {
      if (!mounted) return;
      if (!_indicadoresAusenciaAtivo) return;
      setState(() => _alertaPiscaLigado = !_alertaPiscaLigado);
    });

    _dataChamada = widget.dataSelecionadaEspecial ?? DisciplinaService.hoje();
    _disciplinaTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _atualizarDisciplina(),
    );
    debugPrint('🚀 ChamadaTurmaScreen initState');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verificarEAcessarChamada();
    });
  }

  @override
  void dispose() {
    if (_podeAcessarChamada && !_telepatiaUsandoChamadaReal) {
      debugPrint('🔓 Liberando lock no dispose');
      LockChamadaService.liberarChamada(widget.turmaId);
    }
    _buscaDebounce?.cancel();
    _disciplinaTimer?.cancel();
    _alertaPiscaTimer?.cancel();
    _telepatiaTimer?.cancel();
    _chamadaInversaTimer?.cancel();
    _telepatiaScrollController.dispose();
    _ocupacaoSubscription?.cancel();
    _animationController.dispose();
    _observacaoController.dispose();
    _buscaController.dispose();
    super.dispose();
  }

  // ============================================
  // VERIFICAR LOCK E ACESSAR
  // ============================================
  Future<void> _verificarEAcessarChamada() async {
    debugPrint('🔍 Verificando lock para turma: ${widget.turmaId}');

    setState(() {
      _verificandoLock = true;
      _isLoading = true;
    });

    try {
      // Verificar se já tem chamada hoje
      await _verificarChamadaExistenteAlternativa();
      await _carregarConfiguracaoIndicadoresAusencia();
      await _carregarConfiguracaoModoBrincadeira();

      if (_chamadaJaFeitaHoje) {
        final jaRecebeuTelepatia =
            await _usuarioJaRecebeuTelepatiaNestaChamada();

        if (_telepatiaAtiva && !jaRecebeuTelepatia) {
          await _prepararTelepatiaComChamadaReal();

          if (!mounted) return;
          setState(() {
            _podeAcessarChamada = true;
            _podeFazerChamada = true;
            _verificandoLock = false;
            _isLoading = false;
          });

          _agendarTelepatiaSeAtiva();
          return;
        }

        setState(() {
          _verificandoLock = false;
          _isLoading = false;
          _podeAcessarChamada = false;
        });
        return;
      }

      // Verificar disponibilidade do lock
      final disponivel = await LockChamadaService.verificarDisponibilidade(
        widget.turmaId,
        usuarioId: widget.usuarioId,
      );

      if (!disponivel) {
        final doc = await _firestore
            .collection('locks_chamada')
            .doc(widget.turmaId)
            .get();

        if (doc.exists) {
          setState(() {
            _ocupanteInfo = doc.data();
          });
        }

        setState(() {
          _verificandoLock = false;
          _isLoading = false;
          _podeAcessarChamada = false;
        });
        return;
      }

      // Tentar ocupar a chamada
      final user = FirebaseAuth.instance.currentUser;
      final nome = user?.displayName ?? 'Professor';

      final ocupado = await LockChamadaService.ocuparChamada(
        turmaId: widget.turmaId,
        usuarioId: widget.usuarioId,
        usuarioNome: nome,
      );

      if (!ocupado) {
        final doc = await _firestore
            .collection('locks_chamada')
            .doc(widget.turmaId)
            .get();

        if (doc.exists) {
          setState(() {
            _ocupanteInfo = doc.data();
          });
        }

        setState(() {
          _verificandoLock = false;
          _isLoading = false;
          _podeAcessarChamada = false;
        });
        return;
      }

      // Configurar stream para monitorar ocupação
      await _ocupacaoSubscription?.cancel();
      _ocupacaoSubscription = _firestore
          .collection('locks_chamada')
          .doc(widget.turmaId)
          .snapshots()
          .map((snapshot) => snapshot.data())
          .listen((ocupante) {
            if (!mounted) return;
            if (ocupante == null) return;
            final ocupanteId = ocupante['usuario_id'];
            if (ocupanteId != widget.usuarioId) {
              _mostrarAvisoLockPerdido(ocupante);
            }
          });

      setState(() {
        _podeAcessarChamada = true;
      });

      await _verificarUsuarioECarregarDados();

      setState(() {
        _verificandoLock = false;
      });
    } catch (e, stackTrace) {
      debugPrint('❌ Erro ao verificar lock: $e');
      debugPrint('❌ StackTrace: $stackTrace');
      setState(() {
        _verificandoLock = false;
        _isLoading = false;
        _podeAcessarChamada = false;
      });
      _mostrarErroGeral('Erro ao verificar disponibilidade da chamada: $e');
    }
  }

  void _mostrarAvisoLockPerdido(Map<String, dynamic> ocupante) {
    if (!mounted || _avisoLockPerdidoAberto) return;
    _avisoLockPerdidoAberto = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: context.uai.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.uai.cardRadius),
        ),
        title: Icon(Icons.warning_amber, color: context.uai.warning, size: 50),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '⚠️ CHAMADA INTERROMPIDA',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.uai.warning,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Outro professor assumiu o controle desta chamada:\n\n'
              '👤 ${ocupante['usuario_nome'] ?? 'Professor'}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.uai.textPrimary,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Você será redirecionado.',
              style: TextStyle(
                color: context.uai.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _appBarBg(),
              foregroundColor: _appBarFg(),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ============================================
  // CARREGAMENTO INICIAL
  // ============================================
  Future<void> _verificarUsuarioECarregarDados() async {
    if (!_podeAcessarChamada) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      if (widget.usuarioId.isEmpty) {
        setState(() => _erroUsuarioId = true);
        _mostrarErroUsuario();
        return;
      }

      setState(() => _isLoading = true);

      await _carregarDadosProfessor();

      if (!_carregouDadosProfessor) {
        setState(() => _isLoading = false);
        return;
      }

      await _verificarChamadaExistenteAlternativa();
      await _carregarConfiguracaoIndicadoresAusencia();
      await _carregarConfiguracaoModoBrincadeira();

      if (_chamadaJaFeitaHoje) {
        setState(() {
          _isLoading = false;
          _podeFazerChamada = false;
        });
        return;
      }

      await _continuarFluxoChamada();
    } catch (e) {
      debugPrint('❌ Erro ao carregar dados: $e');
      setState(() => _isLoading = false);
      _mostrarErroGeral(e.toString());
    }
  }

  Future<void> _carregarDadosProfessor() async {
    try {
      if (widget.usuarioId.isEmpty) {
        setState(() {
          _professorNome = 'Erro: Usuário não identificado';
          _professorId = '';
          _carregouDadosProfessor = false;
          _isAdmin = false;
        });
        return;
      }

      final usuarioDoc = await _firestore
          .collection('usuarios')
          .doc(widget.usuarioId)
          .get();

      if (usuarioDoc.exists) {
        final usuarioData = usuarioDoc.data()!;
        final nomeCompleto =
            usuarioData['nome_completo']?.toString() ??
            usuarioData['nome']?.toString() ??
            'Professor';

        final pesoRaw = usuarioData['peso_permissao'];
        int pesoPermissao = 0;

        if (pesoRaw is int) {
          pesoPermissao = pesoRaw;
        } else if (pesoRaw is double) {
          pesoPermissao = pesoRaw.toInt();
        } else if (pesoRaw is String) {
          pesoPermissao = int.tryParse(pesoRaw) ?? 0;
        }

        setState(() {
          _professorId = widget.usuarioId;
          _professorNome = nomeCompleto;
          _carregouDadosProfessor = true;
          _isAdmin = pesoPermissao >= 100;
        });
      } else {
        setState(() {
          _professorId = widget.usuarioId;
          _professorNome = 'Professor';
          _carregouDadosProfessor = true;
          _isAdmin = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar dados do professor: $e');
      setState(() {
        _professorId = widget.usuarioId;
        _professorNome = 'Professor';
        _carregouDadosProfessor = widget.usuarioId.isNotEmpty;
        _isAdmin = false;
      });
    }
  }

  Future<void> _verificarChamadaExistenteAlternativa() async {
    try {
      final hoje = _dataChamada;
      final dataHojeFormatada = DateFormat('yyyy-MM-dd').format(hoje);

      final querySnapshot = await _firestore
          .collection('chamadas')
          .where('turma_id', isEqualTo: widget.turmaId)
          .where('data_formatada', isEqualTo: dataHojeFormatada)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        setState(() {
          _chamadaJaFeitaHoje = true;
          _chamadaExistente = {
            ...querySnapshot.docs.first.data(),
            'id': querySnapshot.docs.first.id,
          };
        });
      } else {
        setState(() {
          _chamadaJaFeitaHoje = false;
          _chamadaExistente = null;
        });
      }
    } catch (e) {
      debugPrint('❌ Erro ao verificar chamada existente: $e');
      setState(() {
        _chamadaJaFeitaHoje = false;
        _chamadaExistente = null;
      });
    }
  }

  Future<void> _continuarFluxoChamada() async {
    try {
      final turmaDoc = await _firestore
          .collection('turmas')
          .doc(widget.turmaId)
          .get();

      if (!turmaDoc.exists) {
        setState(() {
          _isLoading = false;
          _podeFazerChamada = false;
          _mensagemAulaHoje = 'Turma não encontrada';
        });
        return;
      }

      final turmaData = turmaDoc.data()!;
      final diasTreino =
          (turmaData['dias_semana'] as List<dynamic>?)
              ?.map((dia) => dia.toString().toUpperCase().trim())
              .toList() ??
          [];

      setState(() => _diasTreinoTurma = diasTreino);

      final agora = _dataChamada;
      final diaSemanaOriginal = DateFormat(
        'EEEE',
        'pt_BR',
      ).format(agora).toLowerCase();

      String diaSemanaFormatado = diaSemanaOriginal;
      if (diaSemanaOriginal.contains('segunda')) {
        diaSemanaFormatado = 'SEGUNDA';
      } else if (diaSemanaOriginal.contains('terça') ||
          diaSemanaOriginal.contains('terca')) {
        diaSemanaFormatado = 'TERCA';
      } else if (diaSemanaOriginal.contains('quarta')) {
        diaSemanaFormatado = 'QUARTA';
      } else if (diaSemanaOriginal.contains('quinta')) {
        diaSemanaFormatado = 'QUINTA';
      } else if (diaSemanaOriginal.contains('sexta')) {
        diaSemanaFormatado = 'SEXTA';
      } else if (diaSemanaOriginal.contains('sábado') ||
          diaSemanaOriginal.contains('sabado')) {
        diaSemanaFormatado = 'SABADO';
      } else if (diaSemanaOriginal.contains('domingo')) {
        diaSemanaFormatado = 'DOMINGO';
      }

      final diaSemanaCompleto = diaSemanaFormatado;
      final diaSemanaAbrev = _getDiaAbreviado(diaSemanaCompleto);

      final diasConfiguracao =
          turmaData['dias_configuracao'] as Map<String, dynamic>?;
      String tipoAulaHoje = 'OBJETIVA';

      if (diasConfiguracao != null) {
        final configuracaoDia =
            diasConfiguracao[diaSemanaCompleto] as Map<String, dynamic>?;
        if (configuracaoDia != null) {
          tipoAulaHoje = configuracaoDia['tipoAula']?.toString() ?? 'OBJETIVA';
        }
      }

      setState(() {
        _dataChamada = agora;
        _tipoAulaHoje = tipoAulaHoje;
      });

      bool encontrouDia = false;
      String diaCorrespondente = '';

      for (var diaTurma in _diasTreinoTurma) {
        final diaTurmaAbrev = _getDiaAbreviado(diaTurma);
        if (diaSemanaAbrev == diaTurmaAbrev) {
          encontrouDia = true;
          diaCorrespondente = diaTurma;
          break;
        }
      }

      if (encontrouDia || _modoExtraForcado || _ehChamadaEspecial) {
        setState(() {
          _podeFazerChamada = true;
          _mensagemAulaHoje = _ehChamadaEspecial
              ? '📅 CHAMADA ESPECIAL: ${DateFormat('dd/MM/yyyy').format(_dataChamada)}'
              : encontrouDia
              ? 'AULA HOJE: $diaCorrespondente'
              : '🔴 MODO ADMIN: CHAMADA EXTRA (fora do dia)';
        });
        await _carregarAlunos();
        _agendarChamadaInversaSeAtiva();
      } else {
        final diasTreinoTexto = _diasTreinoTurma.isNotEmpty
            ? _diasTreinoTurma.join(', ')
            : 'nenhum dia definido';

        setState(() {
          _podeFazerChamada = false;
          _mensagemAulaHoje =
              '📅 Esta turma não tem aula hoje.\n'
              '🏋️ Dias de treino: $diasTreinoTexto\n'
              '📆 Hoje é: $diaSemanaCompleto';
        });
      }
    } catch (e) {
      debugPrint('❌ Erro ao verificar dia de treino: $e');
      setState(() {
        _podeFazerChamada = false;
        _mensagemAulaHoje = '❌ Erro ao verificar dados da turma';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _carregarAlunos() async {
    try {
      debugPrint('👥 Carregando alunos...');

      final alunosSnapshot = await _firestore
          .collection('alunos')
          .where('turma_id', isEqualTo: widget.turmaId)
          .where(
            'status_atividade',
            whereIn: ['ATIVO(A)', 'ATIVO(A) ', 'ATIVO'],
          )
          .get();

      final alunosList = alunosSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'nome': data['nome'] ?? 'Sem nome',
          'apelido': data['apelido']?.toString() ?? '',
          'foto': AlunoFotoResolver.fotoDoMapa(data),
          'graduacao_id': data['graduacao_id'] as String?,
          'graduacao_nome':
              data['graduacao_nome']?.toString() ??
              data['graduacao_atual']?.toString() ??
              '',
          'ultimo_dia_presente':
              data['ultimo_dia_presente'] ??
              data['ultimoDiaPresente'] ??
              data['ultima_presenca'] ??
              data['ultimaPresenca'] ??
              data['data_ultima_presenca'] ??
              data['dataUltimaPresenca'] ??
              data['ultimo_presente_em'] ??
              data['ultimoPresenteEm'] ??
              data['last_presence'] ??
              data['lastPresence'],
        };
      }).toList();

      alunosList.sort(
        (a, b) => (a['nome'] as String).compareTo(b['nome'] as String),
      );
      // Carrega o estado disciplinar em paralelo, sem alterar o cadastro original.
      // Na falha de rede a tela não autoriza novas presenças.
      try {
        _disciplinaPorAluno = await DisciplinaService.buscarResumos(
          alunosList.map((aluno) => aluno['id'].toString()),
        );
      } catch (_) {
        _disciplinaPorAluno = null;
      }

      final presencasIniciais = <String, bool>{};
      for (var aluno in alunosList) {
        presencasIniciais[aluno['id'] as String] = false;
      }

      setState(() {
        _alunos = alunosList;
        _presencas = presencasIniciais;
        _invalidarCacheFiltro();
      });

      _preloadGraduacoes();
    } catch (e) {
      debugPrint('❌ Erro ao carregar alunos: $e');
      setState(() {
        _mensagemAulaHoje = '❌ Erro ao carregar alunos: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _preloadGraduacoes() async {
    try {
      if (_graduacoesGlobalCache.isNotEmpty) {
        _graduacoesCache
          ..clear()
          ..addAll(_graduacoesGlobalCache);
        return;
      }

      final snapshot = await _firestore.collection('graduacoes').get();

      final temp = <String, Map<String, dynamic>>{};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        temp[doc.id] = {
          'hex_cor1': data.containsKey('hex_cor1')
              ? data['hex_cor1']
              : '#CCCCCC',
          'hex_cor2': data.containsKey('hex_cor2')
              ? data['hex_cor2']
              : '#CCCCCC',
          'hex_ponta1': data.containsKey('hex_ponta1')
              ? data['hex_ponta1']
              : '#CCCCCC',
          'hex_ponta2': data.containsKey('hex_ponta2')
              ? data['hex_ponta2']
              : '#CCCCCC',
          'nome_graduacao': data.containsKey('nome_graduacao')
              ? data['nome_graduacao']
              : 'Sem graduação',
        };
      }

      _graduacoesGlobalCache
        ..clear()
        ..addAll(temp);

      _graduacoesCache
        ..clear()
        ..addAll(temp);
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar graduações: $e');
    }
  }

  // ============================================
  // FUNÇÕES DE CHAMADA ESPECIAL
  // ============================================
  Future<void> _abrirChamadaEspecial() async {
    try {
      final DateTime? dataSelecionada = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2020, 1, 1),
        lastDate: DateTime(2026, 12, 31),
        locale: const Locale('pt', 'BR'),
        builder: (context, child) {
          final primary = _ensureVisible(
            context.uai.primary,
            context.uai.surface,
          );

          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme(
                brightness: context.uai.background.computeLuminance() < 0.45
                    ? Brightness.dark
                    : Brightness.light,
                primary: primary,
                onPrimary: _readableOn(primary),
                secondary: primary,
                onSecondary: _readableOn(primary),
                error: context.uai.error,
                onError: _readableOn(context.uai.error),
                surface: context.uai.surface,
                onSurface: context.uai.textPrimary,
              ),
              dialogTheme: DialogThemeData(
                backgroundColor: context.uai.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(context.uai.cardRadius),
                ),
              ),
            ),
            child: child!,
          );
        },
      );

      if (!mounted) return;
      if (dataSelecionada == null ||
          !chamadaEspecialPodeAbrirConfirmacao(context, dataSelecionada)) {
        return;
      }

      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: context.uai.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.uai.cardRadius),
            ),
            title: Text(
              '📅 CHAMADA ESPECIAL',
              style: TextStyle(
                color: context.uai.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Data selecionada: ${DateFormat('dd/MM/yyyy').format(dataSelecionada)}',
                  style: TextStyle(
                    color: context.uai.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'Deseja fazer chamada para esta data?\n\n'
                  '• Pode ser qualquer dia (inclusive retroativo)\n'
                  '• A chamada será salva normalmente\n'
                  '• Os alunos serão os mesmos da turma atual',
                  style: TextStyle(
                    fontSize: 14,
                    color: context.uai.textSecondary,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'CANCELAR',
                  style: TextStyle(color: context.uai.textMuted),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _appBarBg(),
                  foregroundColor: _appBarFg(),
                ),
                child: const Text('CONTINUAR'),
              ),
            ],
          );
        },
      );

      if (confirm != true) return;

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChamadaTurmaScreen(
            turmaId: widget.turmaId,
            turmaNome: widget.turmaNome,
            academiaId: widget.academiaId,
            academiaNome: widget.academiaNome,
            usuarioId: widget.usuarioId,
            dataSelecionadaEspecial: dataSelecionada,
          ),
        ),
      );

      if (mounted) {
        _verificarUsuarioECarregarDados();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao abrir chamada especial: $e'),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  // ============================================
  // 🧠 CONFIGURAÇÕES SECRETAS DA CHAMADA
  // ============================================
  Future<void> _carregarConfiguracaoModoBrincadeira() async {
    try {
      final doc = await _firestore
          .collection('configuracoes_sistema')
          .doc('modo_troll')
          .get();

      final data = doc.data();
      if (data == null) {
        if (!mounted) return;
        setState(() {
          _modoBrincadeiraAtivo = false;
          _telepatiaAtiva = false;
          _chamadaInversaAtiva = false;
        });
        return;
      }

      final ativoGeral = data['ativo'] == true;
      bool telepatiaAtiva = false;
      bool chamadaInversaAtiva = false;

      final trolagens = data['trolagens'];
      if (trolagens is Map) {
        final telepatia = trolagens['chamada_telepatia'];
        final inversa = trolagens['chamada_inversa'];

        telepatiaAtiva =
            telepatia == true ||
            (telepatia is Map &&
                (telepatia['ativo'] == true || telepatia['enabled'] == true));
        chamadaInversaAtiva =
            inversa == true ||
            (inversa is Map &&
                (inversa['ativo'] == true || inversa['enabled'] == true));
      }

      if (!mounted) return;
      setState(() {
        _modoBrincadeiraAtivo = ativoGeral;
        _telepatiaAtiva = ativoGeral && telepatiaAtiva;
        _chamadaInversaAtiva = ativoGeral && chamadaInversaAtiva;
      });
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar configurações secretas da chamada: $e');
      if (!mounted) return;
      setState(() {
        _modoBrincadeiraAtivo = false;
        _telepatiaAtiva = false;
        _chamadaInversaAtiva = false;
      });
    }
  }

  String _chaveChamadaTelepatiaUsuario() {
    final dataFmt = _chamadaExistente?['data_formatada']?.toString();
    final dataFinal = (dataFmt != null && dataFmt.isNotEmpty)
        ? dataFmt
        : DateFormat('yyyy-MM-dd').format(_dataChamada);
    return '${widget.turmaId}_$dataFinal';
  }

  Future<bool> _usuarioJaRecebeuTelepatiaNestaChamada() async {
    try {
      if (widget.usuarioId.isEmpty) return true;
      if (_chamadaExistente == null) return true;

      final userDoc = await _firestore
          .collection('usuarios')
          .doc(widget.usuarioId)
          .get();
      final data = userDoc.data();
      final trollData = data?['trolldata'];
      if (trollData is! Map) return false;

      final telepatia = trollData['chamada_telepatia'];
      if (telepatia is! Map) return false;

      return telepatia.containsKey(_chaveChamadaTelepatiaUsuario());
    } catch (e) {
      debugPrint(
        '⚠️ Erro ao verificar histórico de brincadeira do usuário: $e',
      );
      return true;
    }
  }

  Future<void> _registrarTelepatiaNoUsuario() async {
    if (_telepatiaRegistradaNoUsuario) return;
    if (widget.usuarioId.isEmpty) return;
    if (_chamadaExistente == null) return;

    _telepatiaRegistradaNoUsuario = true;

    try {
      final chave = _chaveChamadaTelepatiaUsuario();
      final chamadaId = _chamadaExistente?['id']?.toString() ?? '';

      await _firestore.collection('usuarios').doc(widget.usuarioId).set({
        'trolldata': {
          'chamada_telepatia': {
            chave: {
              'turma_id': widget.turmaId,
              'turma_nome': widget.turmaNome,
              'academia_id': widget.academiaId,
              'academia_nome': widget.academiaNome,
              'chamada_id': chamadaId,
              'data_chamada': Timestamp.fromDate(_dataChamada),
              'data_formatada': DateFormat('yyyy-MM-dd').format(_dataChamada),
              'registrado_em': FieldValue.serverTimestamp(),
            },
          },
        },
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('⚠️ Erro ao registrar brincadeira no usuário: $e');
    }
  }

  DateTime _dataChamadaRealFromData(Map<String, dynamic> data) {
    final value = data['data_chamada'] ?? data['dataChamada'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    final dataFormatada = data['data_formatada']?.toString();
    if (dataFormatada != null && dataFormatada.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(dataFormatada.trim());
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }

  Future<void> _prepararTelepatiaComChamadaReal() async {
    final chamada = _chamadaExistente;
    if (chamada == null) return;

    final alunosRaw = chamada['alunos'];
    final alunos = <Map<String, dynamic>>[];
    final presencasIniciais = <String, bool>{};

    if (alunosRaw is List) {
      for (var i = 0; i < alunosRaw.length; i++) {
        final raw = alunosRaw[i];
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final id = (item['aluno_id'] ?? item['id'] ?? 'replay_$i').toString();
        final nome = (item['aluno_nome'] ?? item['nome'] ?? 'Aluno').toString();
        final presenteReal = item['presente'] == true;

        alunos.add({
          'id': id,
          'nome': nome,
          'apelido': item['apelido']?.toString() ?? '',
          'foto': item['foto'] ?? item['foto_perfil_aluno'],
          'graduacao_id': item['graduacao_id'],
          'graduacao_nome':
              item['graduacao_nome']?.toString() ??
              item['graduacao']?.toString() ??
              item['corda']?.toString() ??
              '',
          'ultimo_dia_presente':
              item['ultimo_dia_presente'] ??
              item['ultima_presenca'] ??
              item['data_ultima_presenca'],
          'observacao': item['observacao']?.toString() ?? '',
          '_presente_real_replay': presenteReal,
        });
        presencasIniciais[id] = false;
      }
    }

    alunos.sort((a, b) {
      final nomeA = a['nome']?.toString().toLowerCase() ?? '';
      final nomeB = b['nome']?.toString().toLowerCase() ?? '';
      return nomeA.compareTo(nomeB);
    });

    final dataReal = _dataChamadaRealFromData(chamada);
    final tipoReal = chamada['tipo_aula']?.toString() ?? _tipoAulaHoje;
    final professorReal =
        chamada['professor_nome']?.toString() ?? _professorNome;
    final professorIdReal = chamada['professor_id']?.toString() ?? _professorId;

    if (!mounted) return;
    setState(() {
      _alunos = alunos;
      _presencas = presencasIniciais;
      _observacoes.clear();
      _dataChamada = dataReal;
      _tipoAulaHoje = tipoReal;
      _professorNome = professorReal.isEmpty ? 'Professor' : professorReal;
      _professorId = professorIdReal;
      _telepatiaUsandoChamadaReal = true;
      _telepatiaRodando = false;
      _telepatiaConcluida = false;
      _telepatiaJaIniciou = false;
      _telepatiaRegistradaNoUsuario = false;
      _telepatiaMensagem = 'Preparando chamada...';
      _filtroPresenca = 'Todos';
      _buscaAluno = '';
      _buscaController.clear();
      _invalidarCacheFiltro();
    });

    _preloadGraduacoes();
  }

  void _agendarTelepatiaSeAtiva() {
    if (!_telepatiaAtiva) return;
    if (!_telepatiaUsandoChamadaReal) return;
    if (_telepatiaJaIniciou) return;
    if (_alunos.isEmpty) return;
    if (!mounted) return;

    _telepatiaJaIniciou = true;

    Future.delayed(const Duration(milliseconds: 850), () {
      if (!mounted) return;
      if (!_telepatiaAtiva || !_telepatiaUsandoChamadaReal) return;
      if (_alunos.isEmpty) return;
      _iniciarTelepatiaReplay();
    });
  }

  void _iniciarTelepatiaReplay() {
    _telepatiaTimer?.cancel();

    final roteiro = List<Map<String, dynamic>>.from(_alunos);
    if (roteiro.isEmpty) return;

    final frases = <String>[
      'Lendo a energia da turma...',
      'Consultando o berimbau...',
      'Detectando presença por vibração...',
      'Calculando nível de axé...',
      'Sincronizando presença espiritual...',
      'Conferindo a roda...',
    ];

    setState(() {
      _telepatiaRodando = true;
      _telepatiaConcluida = false;
      _telepatiaMensagem = frases.first;
      _filtroPresenca = 'Todos';
      _buscaAluno = '';
      _buscaController.clear();
      for (final aluno in _alunos) {
        _presencas[aluno['id'] as String] = false;
      }
      _invalidarCacheFiltro();
    });

    HapticFeedback.mediumImpact();

    int index = 0;
    _telepatiaTimer = Timer.periodic(const Duration(milliseconds: 430), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (index >= roteiro.length) {
        timer.cancel();
        final presentes = _presencas.values.where((v) => v).length;
        final ausentes = _alunos.length - presentes;

        setState(() {
          _telepatiaRodando = false;
          _telepatiaConcluida = true;
          _telepatiaMensagem =
              'Chamada concluída por presença espiritual: $presentes presentes e $ausentes ausentes.';
          _invalidarCacheFiltro();
        });

        HapticFeedback.heavyImpact();
        _registrarTelepatiaNoUsuario();

        Future.delayed(const Duration(milliseconds: 650), () {
          if (!mounted) return;
          _mostrarDialogoTelepatiaFinal();
        });
        return;
      }

      final aluno = roteiro[index];
      final alunoId = aluno['id'] as String?;
      final presente = aluno['_presente_real_replay'] == true;
      final nome = aluno['nome']?.toString() ?? 'Aluno';
      final frase = frases[index % frases.length];

      setState(() {
        if (alunoId != null && alunoId.isNotEmpty) {
          _presencas[alunoId] = presente;
        }
        _telepatiaMensagem = presente
            ? '$frase\n✅ ${_nomeAlunoCurto(nome)} detectado pelo axé.'
            : '$frase\n❌ ${_nomeAlunoCurto(nome)} sem sinal de presença.';
        _invalidarCacheFiltro();
      });

      if (_telepatiaScrollController.hasClients) {
        final maxScroll = _telepatiaScrollController.position.maxScrollExtent;
        final progress = roteiro.length <= 1
            ? 1.0
            : (index / (roteiro.length - 1)).clamp(0.0, 1.0).toDouble();
        final target = maxScroll * progress;
        _telepatiaScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
        );
      }

      index++;
    });
  }

  void _mostrarDialogoTelepatiaFinal() {
    final presentes = _presencas.values.where((v) => v).length;
    final total = _alunos.length;
    final ausentes = total - presentes;
    final porcentagem = total > 0 ? ((presentes / total) * 100).round() : 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: context.uai.primaryGradient,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                duration: const Duration(seconds: 1),
                tween: Tween(begin: 0.0, end: 1.0),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Icon(
                      Icons.celebration,
                      size: 80,
                      color: _onPrimary(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text(
                '🎉 CHAMADA CONCLUÍDA!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _onPrimary(),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                DateFormat("EEEE, dd/MM/yyyy", 'pt_BR').format(_dataChamada),
                style: TextStyle(
                  fontSize: 16,
                  color: _onPrimary().withAlpha(189),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.uai.card.withAlpha(46),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: _onPrimary().withAlpha(36)),
                ),
                child: Text(
                  'Chamada feita por telepatia capoeirística e presença espiritual.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _onPrimary(),
                    fontSize: 14,
                    height: 1.25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: context.uai.card.withAlpha(51),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildResumoItem(
                      '$presentes',
                      'Presentes',
                      Icons.check_circle,
                    ),
                    _buildResumoItem('$ausentes', 'Ausentes', Icons.cancel),
                    _buildResumoItem(
                      '$porcentagem%',
                      'Frequência',
                      Icons.trending_up,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Professor: $_professorNome',
                style: TextStyle(fontSize: 14, color: _onPrimary()),
              ),
              const SizedBox(height: 8),
              Text(
                'Tipo de aula: $_tipoAulaHoje',
                style: TextStyle(
                  fontSize: 12,
                  color: _onPrimary().withAlpha(189),
                ),
              ),
              const SizedBox(height: 24),
              TweenAnimationBuilder<Duration>(
                duration: const Duration(seconds: 8),
                tween: Tween(
                  begin: const Duration(seconds: 8),
                  end: Duration.zero,
                ),
                onEnd: () {
                  Navigator.pop(context);
                  if (mounted) Navigator.pop(context);
                },
                builder: (context, value, child) {
                  return Column(
                    children: [
                      LinearProgressIndicator(
                        value: value.inSeconds / 8,
                        backgroundColor: _onPrimary().withAlpha(64),
                        valueColor: AlwaysStoppedAnimation<Color>(_onPrimary()),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Fechando em ${value.inSeconds} segundos...',
                        style: TextStyle(
                          color: _onPrimary().withAlpha(189),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  if (mounted) Navigator.pop(context);
                },
                child: Text(
                  'FECHAR AGORA',
                  style: TextStyle(
                    color: _onPrimary(),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _agendarChamadaInversaSeAtiva() {
    if (!_modoBrincadeiraAtivo || !_chamadaInversaAtiva) return;
    if (_chamadaInversaJaIniciou) return;
    if (_telepatiaUsandoChamadaReal) return;
    if (_chamadaJaFeitaHoje) return;
    if (_alunos.isEmpty) return;

    _chamadaInversaJaIniciou = true;

    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      if (!_podeFazerChamada || _chamadaJaFeitaHoje) return;

      setState(() {
        _chamadaInversaRodando = true;
        _chamadaInversaToques = 0;
        _statusMensagem = 'Sincronizando presença automática...';
      });

      _chamadaInversaTimer?.cancel();
      _chamadaInversaTimer = Timer(const Duration(seconds: 20), () {
        if (!mounted) return;
        setState(() {
          _chamadaInversaRodando = false;
          _statusMensagem = '';
        });
      });
    });
  }

  void _togglePresencaInversa(String alunoId) {
    final alunosVisiveis = _alunosFiltrados;
    if (alunosVisiveis.isEmpty) return;

    final index = alunosVisiveis.indexWhere((a) => a['id'] == alunoId);
    if (index < 0) return;

    final offsets = _modoListaCompacta ? <int>[1, -1] : <int>[1, 2, -1, -2];
    final offset = offsets[_chamadaInversaToques % offsets.length];
    final targetIndex = (index + offset) % alunosVisiveis.length;
    final normalizedIndex = targetIndex < 0
        ? targetIndex + alunosVisiveis.length
        : targetIndex;
    final alvo = alunosVisiveis[normalizedIndex];
    final alvoId = alvo['id'] as String;

    setState(() {
      _chamadaInversaToques++;
      _presencas[alvoId] = !(_presencas[alvoId] ?? false);
      _invalidarCacheFiltro();
    });

    HapticFeedback.mediumImpact();
  }

  // ============================================
  // FUNÇÕES AUXILIARES
  // ============================================

  int _parseIntSeguro(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is num) return value.toInt();
    if (value is String) {
      final cleaned = value.trim().replaceAll('%', '').replaceAll(',', '.');
      final parsedInt = int.tryParse(cleaned);
      if (parsedInt != null) return parsedInt;
      final parsedDouble = double.tryParse(cleaned);
      if (parsedDouble != null) return parsedDouble.round();
    }
    return fallback;
  }

  String _getDiaAbreviado(String diaCompleto) {
    final diaUpper = diaCompleto.toUpperCase().trim();
    if (_diasAbreviados.containsKey(diaUpper)) {
      return _diasAbreviados[diaUpper]!;
    }
    for (var entry in _diasAbreviados.entries) {
      if (diaUpper.contains(entry.key) || entry.key.contains(diaUpper)) {
        return entry.value;
      }
    }
    return diaUpper.length >= 3
        ? diaUpper.substring(0, 3).toLowerCase()
        : diaUpper.toLowerCase();
  }

  int _parseIntIndicador(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '') ?? fallback;
  }

  List<Map<String, dynamic>> _faixasIndicadoresPadrao() {
    return [
      {
        'ate_dias': 3,
        'cor': '#2196F3',
        'label': 'Frequente',
        'gera_alerta': false,
      },
      {
        'ate_dias': 6,
        'cor': '#4CAF50',
        'label': 'Regular',
        'gera_alerta': false,
      },
      {
        'ate_dias': 12,
        'cor': '#FFC107',
        'label': 'Atenção',
        'gera_alerta': true,
      },
      {
        'ate_dias': 24,
        'cor': '#FF9800',
        'label': 'Ausente',
        'gera_alerta': true,
      },
      {
        'ate_dias': 35,
        'cor': '#FF5722',
        'label': 'Muito ausente',
        'gera_alerta': true,
      },
      {
        'ate_dias': 9999,
        'cor': '#F44336',
        'label': 'Risco de inatividade',
        'gera_alerta': true,
      },
    ];
  }

  Color _colorFromHexIndicador(String value, {Color? fallback}) {
    try {
      var cleaned = value.trim().replaceAll('#', '').toUpperCase();
      if (cleaned.length == 6) cleaned = 'FF$cleaned';
      if (cleaned.length != 8) return fallback ?? context.uai.textMuted;
      return Color(int.parse(cleaned, radix: 16));
    } catch (_) {
      return fallback ?? context.uai.textMuted;
    }
  }

  Future<void> _carregarConfiguracaoIndicadoresAusencia() async {
    try {
      final doc = await _firestore
          .collection('configuracoes_sistema')
          .doc('indicadores_ausencia')
          .get();

      final data = doc.data();
      final faixasRaw = data?['faixas'];
      final faixas = faixasRaw is List
          ? faixasRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : _faixasIndicadoresPadrao();

      faixas.sort((a, b) {
        final aDias = _parseIntIndicador(a['ate_dias'], fallback: 9999);
        final bDias = _parseIntIndicador(b['ate_dias'], fallback: 9999);
        return aDias.compareTo(bDias);
      });

      _indicadoresAusenciaAtivo = data?['ativo'] != false;
      _mostrarTextoUltimaPresencaIndicador =
          data?['mostrar_texto_ultima_presenca'] != false;
      _faixasIndicadoresAusencia = faixas;
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar configuração dos indicadores: $e');
      _indicadoresAusenciaAtivo = true;
      _mostrarTextoUltimaPresencaIndicador = true;
      _faixasIndicadoresAusencia = _faixasIndicadoresPadrao();
    }
  }

  DateTime? _dateTimeSeguro(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;

    if (value is String) {
      final texto = value.trim();
      if (texto.isEmpty) return null;
      final parsedIso = DateTime.tryParse(texto);
      if (parsedIso != null) return parsedIso;
      try {
        return DateFormat('dd/MM/yyyy').parseStrict(texto);
      } catch (_) {
        return null;
      }
    }

    if (value is Map) {
      final seconds = value['_seconds'] ?? value['seconds'];
      if (seconds is int) {
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
      if (seconds is num) {
        return DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000);
      }
    }

    return null;
  }

  DateTime? _ultimaPresencaDoAluno(Map<String, dynamic> aluno) {
    final campos = [
      aluno['ultimo_dia_presente'],
      aluno['ultimoDiaPresente'],
      aluno['ultima_presenca'],
      aluno['ultimaPresenca'],
      aluno['data_ultima_presenca'],
      aluno['dataUltimaPresenca'],
      aluno['ultimo_presente_em'],
      aluno['ultimoPresenteEm'],
      aluno['last_presence'],
      aluno['lastPresence'],
    ];

    for (final campo in campos) {
      final data = _dateTimeSeguro(campo);
      if (data != null) return data;
    }

    return null;
  }

  int? _diasDesdeUltimaPresenca(Map<String, dynamic> aluno) {
    final ultima = _ultimaPresencaDoAluno(aluno);
    if (ultima == null) return null;

    final hoje = DateTime.now();
    final hojeLimpo = DateTime(hoje.year, hoje.month, hoje.day);
    final ultimaLimpa = DateTime(ultima.year, ultima.month, ultima.day);
    final dias = hojeLimpo.difference(ultimaLimpa).inDays;

    return dias < 0 ? 0 : dias;
  }

  Map<String, dynamic>? _faixaIndicadorAusencia(Map<String, dynamic> aluno) {
    if (!_indicadoresAusenciaAtivo) return null;

    final dias = _diasDesdeUltimaPresenca(aluno);
    if (dias == null) return null;

    final faixas = _faixasIndicadoresAusencia.isEmpty
        ? _faixasIndicadoresPadrao()
        : _faixasIndicadoresAusencia;

    for (final faixa in faixas) {
      final ateDias = _parseIntIndicador(faixa['ate_dias'], fallback: 9999);
      if (dias <= ateDias) return faixa;
    }

    return faixas.isNotEmpty ? faixas.last : null;
  }

  Color _corIndicadorAusencia(Map<String, dynamic> aluno) {
    if (!_indicadoresAusenciaAtivo) return context.uai.textMuted;

    final faixa = _faixaIndicadorAusencia(aluno);
    if (faixa == null) return context.uai.textMuted;

    return _colorFromHexIndicador(
      faixa['cor']?.toString() ?? '#9E9E9E',
      fallback: context.uai.textMuted,
    );
  }

  bool _indicadorGeraAlerta(Map<String, dynamic> aluno) {
    final faixa = _faixaIndicadorAusencia(aluno);
    if (faixa == null) return false;
    return faixa['gera_alerta'] == true;
  }

  String _labelIndicadorAusencia(Map<String, dynamic> aluno) {
    final faixa = _faixaIndicadorAusencia(aluno);
    final label = faixa?['label']?.toString().trim() ?? '';
    return label.isEmpty ? 'Alerta' : label;
  }

  Map<String, List<Map<String, dynamic>>> _alunosAgrupadosPorAlerta() {
    final grupos = <String, List<Map<String, dynamic>>>{};

    for (final aluno in _alunos) {
      final alunoId = aluno['id'] as String? ?? '';
      final estaPresente = _presencas[alunoId] == true;

      // Se marcou presença, não entra no alerta final da chamada.
      if (estaPresente) continue;
      if (!_indicadorGeraAlerta(aluno)) continue;

      final label = _labelIndicadorAusencia(aluno);
      grupos.putIfAbsent(label, () => []).add(aluno);
    }

    return grupos;
  }

  String _textoUltimaPresenca(Map<String, dynamic> aluno) {
    final dias = _diasDesdeUltimaPresenca(aluno);

    if (dias == null) return 'Sem presença registrada';
    if (dias == 0) return 'Última presença hoje';
    if (dias == 1) return 'Última presença ontem';
    return 'Última presença há $dias dias';
  }

  String _nomeAlunoCurto(String nomeCompleto) {
    final partes = nomeCompleto
        .trim()
        .split(RegExp(r'\s+'))
        .where((parte) => parte.trim().isNotEmpty)
        .toList();

    if (partes.length <= 2) return nomeCompleto.trim();

    const conectores = {'de', 'da', 'do', 'das', 'dos', 'd'};
    final segundaParte = partes[1].toLowerCase();

    if (conectores.contains(segundaParte) && partes.length >= 3) {
      return '${partes[0]} ${partes[1]} ${partes[2]}';
    }

    return '${partes[0]} ${partes[1]}';
  }

  Widget _buildIndicadorBolinha(
    Map<String, dynamic> aluno, {
    double size = 13,
  }) {
    if (!_indicadoresAusenciaAtivo) return const SizedBox.shrink();

    final color = _corIndicadorAusencia(aluno);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: context.uai.card, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(46),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }

  void _invalidarCacheFiltro() {
    _cacheAssinaturaFiltro = '';
  }

  void _togglePresenca(String alunoId) {
    if (_impedidoNaAula(alunoId)) {
      _avisarSuspensao(alunoId);
      return;
    }
    if (_telepatiaAtiva && _telepatiaUsandoChamadaReal) {
      HapticFeedback.selectionClick();
      return;
    }

    if (_chamadaInversaRodando) {
      _togglePresencaInversa(alunoId);
      return;
    }

    setState(() {
      _presencas[alunoId] = !(_presencas[alunoId] ?? false);
      _invalidarCacheFiltro();
    });
    HapticFeedback.selectionClick();
  }

  String _normalizarTextoBusca(String texto) {
    return texto
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c');
  }

  String _assinaturaFiltroAlunos() {
    final presentes = _presencas.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .join('|');

    final observacoes = _observacoes.entries
        .where((e) => e.value.trim().isNotEmpty)
        .map((e) => '${e.key}:${e.value.trim().length}')
        .join('|');

    return '${_alunos.length}::${_normalizarTextoBusca(_buscaAluno)}::'
        '$_filtroPresenca::$presentes::$observacoes';
  }

  List<Map<String, dynamic>> get _alunosFiltrados {
    final assinatura = _assinaturaFiltroAlunos();

    if (_cacheAssinaturaFiltro == assinatura) {
      return _cacheAlunosFiltrados;
    }

    final busca = _normalizarTextoBusca(_buscaAluno);
    final resultado = <Map<String, dynamic>>[];

    for (final aluno in _alunos) {
      final alunoId = aluno['id'] as String;
      final presente = _presencas[alunoId] ?? false;
      final observacao = (_observacoes[alunoId] ?? '').trim();

      if (_filtroPresenca == 'Presentes' && !presente) continue;
      if (_filtroPresenca == 'Ausentes' && presente) continue;
      if (_filtroPresenca == 'Com observação' && observacao.isEmpty) {
        continue;
      }

      if (busca.isNotEmpty) {
        final nome = aluno['nome']?.toString() ?? '';
        final apelido = aluno['apelido']?.toString() ?? '';
        final graduacao = aluno['graduacao_nome']?.toString() ?? '';
        final textoAluno = _normalizarTextoBusca('$nome $apelido $graduacao');

        if (!textoAluno.contains(busca)) continue;
      }

      resultado.add(aluno);
    }

    _cacheAssinaturaFiltro = assinatura;
    _cacheAlunosFiltrados = resultado;
    return resultado;
  }

  int get _presentesFiltrados {
    int total = 0;
    for (final aluno in _alunosFiltrados) {
      if (_presencas[aluno['id'] as String] == true) total++;
    }
    return total;
  }

  void _marcarTodosFiltrados(bool presente) {
    if (_telepatiaAtiva && _telepatiaUsandoChamadaReal) return;

    final filtrados = _alunosFiltrados;
    if (filtrados.isEmpty) return;

    setState(() {
      for (final aluno in filtrados) {
        if (!_impedidoNaAula(aluno['id'] as String)) {
          _presencas[aluno['id'] as String] = presente;
        }
      }
      _invalidarCacheFiltro();
    });

    HapticFeedback.lightImpact();
  }

  void _inverterFiltrados() {
    if (_telepatiaAtiva && _telepatiaUsandoChamadaReal) return;

    final filtrados = _alunosFiltrados;
    if (filtrados.isEmpty) return;

    setState(() {
      for (final aluno in filtrados) {
        final id = aluno['id'] as String;
        if (!_impedidoNaAula(id)) {
          _presencas[id] = !(_presencas[id] ?? false);
        }
      }
      _invalidarCacheFiltro();
    });

    HapticFeedback.mediumImpact();
  }

  Future<void> _confirmarLimparChamada() async {
    if (_telepatiaAtiva && _telepatiaUsandoChamadaReal) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.uai.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Limpar marcações?'),
        content: Text(
          'Isso vai desmarcar todos os alunos e limpar a busca/filtros da tela. '
          'A chamada ainda não será apagada do sistema.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _appBarBg(),
              foregroundColor: _appBarFg(),
            ),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      for (final aluno in _alunos) {
        _presencas[aluno['id'] as String] = false;
      }
      _observacoes.clear();
      _buscaController.clear();
      _buscaAluno = '';
      _filtroPresenca = 'Todos';
      _invalidarCacheFiltro();
    });
  }

  void _adicionarObservacao(String alunoId, String nomeAluno) {
    _observacaoController.text = _observacoes[alunoId] ?? '';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: context.uai.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.uai.cardRadius),
          ),
          title: Text(
            'Observação para $nomeAluno',
            style: TextStyle(
              color: context.uai.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: TextField(
            controller: _observacaoController,
            maxLines: 3,
            style: TextStyle(color: context.uai.textPrimary),
            decoration: InputDecoration(
              hintText: 'Digite uma observação...',
              hintStyle: TextStyle(color: context.uai.textMuted),
              filled: true,
              fillColor: context.uai.cardAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(context.uai.inputRadius),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(context.uai.inputRadius),
                borderSide: BorderSide(color: context.uai.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(context.uai.inputRadius),
                borderSide: BorderSide(color: context.uai.primary, width: 1.4),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _observacoes[alunoId] = _observacaoController.text;
                  _invalidarCacheFiltro();
                });
                _observacaoController.clear();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Observação salva!'),
                      backgroundColor: context.uai.success,
                    ),
                  );
                }
                Navigator.pop(context);
              },
              child: Text('Salvar'),
            ),
          ],
        );
      },
    );
  }

  void _mostrarErroUsuario() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '❌ Erro: Usuário não identificado. Faça login novamente.',
            ),
            backgroundColor: context.uai.error,
            duration: const Duration(seconds: 5),
          ),
        );

        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) Navigator.pop(context);
        });
      }
    });
  }

  void _mostrarErroGeral(String erro) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erro ao carregar dados: $erro'),
          backgroundColor: context.uai.error,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ============================================
  // VERIFICAR SE LOCK AINDA ESTÁ ATIVO
  // ============================================
  Future<bool> _verificarLockAindaAtivo() async {
    try {
      final doc = await _firestore
          .collection('locks_chamada')
          .doc(widget.turmaId)
          .get();

      if (!doc.exists) return false;
      final data = doc.data();
      if (data == null) return false;

      final usuarioId = data['usuario_id'] as String?;
      return usuarioId == widget.usuarioId;
    } catch (e) {
      debugPrint('❌ Erro ao verificar lock: $e');
      return false;
    }
  }

  void _mostrarAvisoLockExpirado() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: context.uai.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.uai.cardRadius),
        ),
        title: Icon(Icons.timer_off, color: context.uai.error, size: 50),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '⏰ TEMPO EXPIRADO',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.uai.error,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'O tempo para realizar esta chamada expirou.\n\n'
              'Outro professor pode ter assumido o controle.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.uai.textPrimary,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _appBarBg(),
              foregroundColor: _appBarFg(),
            ),
            child: Text('VOLTAR'),
          ),
        ],
      ),
    );
  }

  // ============================================
  // FUNÇÃO PRINCIPAL DE SALVAR CHAMADA (COM CLOUD FUNCTION)
  // ============================================
  Future<void> _salvarChamada() async {
    if (_disciplinaPorAluno == null) {
      _avisarSuspensao('');
      return;
    }
    if (_telepatiaAtiva && _telepatiaUsandoChamadaReal) {
      _mostrarDialogoTelepatiaFinal();
      return;
    }

    final aindaTemLock = await _verificarLockAindaAtivo();
    if (!aindaTemLock) {
      _mostrarAvisoLockExpirado();
      return;
    }

    if (_alunos.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Não há alunos para salvar chamada'),
            backgroundColor: context.uai.warning,
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    final presentes = _presencas.values.where((v) => v).length;

    if (presentes == 0) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: context.uai.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.uai.cardRadius),
          ),
          title: Text(
            '❌ Nenhum aluno presente',
            style: TextStyle(
              color: context.uai.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            'Deseja salvar a chamada mesmo sem nenhum aluno presente?',
            style: TextStyle(
              color: context.uai.textSecondary,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.uai.warning,
                foregroundColor: _readableOn(context.uai.warning),
              ),
              child: const Text('Salvar mesmo assim'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    // Preparar dados para a Cloud Function
    final dadosChamada = {
      'comandoId': _comandoCriacao,
      'turmaId': widget.turmaId,
      'turmaNome': widget.turmaNome,
      'academiaId': widget.academiaId,
      'academiaNome': widget.academiaNome,
      'dataChamada': DateFormat('yyyy-MM-dd').format(_dataChamada),
      'tipoAula': _tipoAulaHoje,
      'professorId': _professorId,
      'professorNome': _professorNome,
      'alunos': _alunos.map((aluno) {
        final alunoId = aluno['id']?.toString() ?? '';
        final fotoPerfilAluno = (aluno['foto']?.toString() ?? '').trim();

        return {
          'id': alunoId,
          'nome': aluno['nome']?.toString() ?? 'Sem nome',
          'apelido': aluno['apelido']?.toString() ?? '',
          'presente': _presencas[alunoId] ?? false,
          'observacao': _observacoes[alunoId] ?? '',

          // Snapshot econômico para histórico/lista de chamada.
          // A chamada nova já salva a foto e dados básicos, evitando consultas extras.
          'foto_perfil_aluno': fotoPerfilAluno,
          'foto': fotoPerfilAluno,
          'graduacao_id': aluno['graduacao_id'],
          'graduacao_nome': aluno['graduacao_nome']?.toString() ?? '',
        };
      }).toList(),
    };

    setState(() {
      _salvandoChamada = true;
      _statusMensagem = 'Enviando para processamento...';
    });
    _animationController.forward();

    var chamadaConfirmada = false;
    try {
      // Chamar a Cloud Function
      setState(() {
        _statusMensagem = 'Processando chamada e atualizando contadores...';
      });

      final result = await UaiCallableClient.instance.call(
        'processarChamada',
        dadosChamada,
      );

      setState(() {
        _statusMensagem = '✅ Chamada salva com sucesso!';
      });
      await Future.delayed(const Duration(milliseconds: 500));

      if (result['success'] == true) {
        chamadaConfirmada = true;
        unawaited(
          SessionLogService.instance.recordEntityOperation(
            module: 'chamadas',
            entityType: 'turma',
            entityId: widget.turmaId,
            operation: 'criou',
            result: 'sucesso',
          ),
        );
        // Liberar lock
        await LockChamadaService.liberarChamada(widget.turmaId);

        if (mounted) {
          final int presentesResult = _parseIntSeguro(result['presentes']);
          final int ausentesResult = _parseIntSeguro(result['ausentes']);
          final int processadosResult = _parseIntSeguro(result['processados']);
          final int percentualResult = _parseIntSeguro(
            result['porcentagem_frequencia'],
          );

          _mostrarTelaConclusao({
            'presentes': presentesResult,
            'ausentes': ausentesResult,
            'total_alunos': processadosResult,
            'porcentagem_frequencia': percentualResult,
          });
        }
      } else {
        unawaited(
          SessionLogService.instance.recordEntityOperation(
            module: 'chamadas',
            entityType: 'turma',
            entityId: widget.turmaId,
            operation: 'criou',
            result: 'falha',
          ),
        );
      }
    } catch (e) {
      if (!chamadaConfirmada) {
        unawaited(
          SessionLogService.instance.recordEntityOperation(
            module: 'chamadas',
            entityType: 'turma',
            entityId: widget.turmaId,
            operation: 'criou',
            result: 'falha',
          ),
        );
      }
      debugPrint('❌ Erro ao processar chamada: $e');
      setState(() {
        _salvandoChamada = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar chamada: ${e.toString()}'),
            backgroundColor: context.uai.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _salvandoChamada = false;
        });
      }
    }
  }

  // ============================================
  // TELA DE CONCLUSÃO DA CHAMADA
  // ============================================
  void _mostrarTelaConclusao(Map<String, dynamic> dados) {
    final gruposAlerta = _alunosAgrupadosPorAlerta();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        insetPadding: EdgeInsets.all(20),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: context.uai.primaryGradient,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                duration: const Duration(seconds: 1),
                tween: Tween(begin: 0.0, end: 1.0),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Icon(
                      Icons.celebration,
                      size: 80,
                      color: _onPrimary(),
                    ),
                  );
                },
              ),
              SizedBox(height: 20),
              Text(
                '🎉 CHAMADA CONCLUÍDA!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _onPrimary(),
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 10),
              Text(
                DateFormat("EEEE, dd/MM/yyyy", 'pt_BR').format(_dataChamada),
                style: TextStyle(
                  fontSize: 16,
                  color: _onPrimary().withAlpha(189),
                ),
              ),
              SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: context.uai.card.withAlpha(51),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildResumoItem(
                      '${dados['presentes']}',
                      'Presentes',
                      Icons.check_circle,
                    ),
                    _buildResumoItem(
                      '${dados['ausentes']}',
                      'Ausentes',
                      Icons.cancel,
                    ),
                    _buildResumoItem(
                      '${dados['porcentagem_frequencia']}%',
                      'Frequência',
                      Icons.trending_up,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20),
              Text(
                'Professor: $_professorNome',
                style: TextStyle(fontSize: 14, color: _onPrimary()),
              ),
              SizedBox(height: 10),
              Text(
                'Tipo de aula: $_tipoAulaHoje',
                style: TextStyle(
                  fontSize: 12,
                  color: _onPrimary().withAlpha(189),
                ),
              ),
              if (gruposAlerta.isNotEmpty) ...[
                const SizedBox(height: 14),
                _buildAlunosAtencaoConclusao(gruposAlerta),
              ],
              SizedBox(height: 25),
              TweenAnimationBuilder<Duration>(
                duration: const Duration(seconds: 10),
                tween: Tween(
                  begin: const Duration(seconds: 10),
                  end: Duration.zero,
                ),
                onEnd: () {
                  Navigator.pop(context);
                  if (mounted) Navigator.pop(context);
                },
                builder: (context, value, child) {
                  return Column(
                    children: [
                      LinearProgressIndicator(
                        value: value.inSeconds / 5,
                        backgroundColor: _onPrimary().withAlpha(64),
                        valueColor: AlwaysStoppedAnimation<Color>(_onPrimary()),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Fechando em ${value.inSeconds} segundos...',
                        style: TextStyle(
                          color: _onPrimary().withAlpha(189),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  );
                },
              ),
              SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  if (mounted) Navigator.pop(context);
                },
                child: Text(
                  'FECHAR AGORA',
                  style: TextStyle(
                    color: _onPrimary(),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlunosAtencaoConclusao(
    Map<String, List<Map<String, dynamic>>> grupos,
  ) {
    final onGradient = _onPrimary();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(41),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: onGradient.withAlpha(46)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: onGradient, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Esses alunos merecem atenção',
                  style: TextStyle(
                    color: onGradient,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...grupos.entries.map((entry) {
            final nomes = entry.value
                .map(
                  (aluno) =>
                      _nomeAlunoCurto(aluno['nome']?.toString() ?? 'Aluno'),
                )
                .toList();

            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.key} (${nomes.length})',
                    style: TextStyle(
                      color: onGradient,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    nomes.join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onGradient.withAlpha(209),
                      fontSize: 11,
                      height: 1.22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildResumoItem(String value, String label, IconData icon) {
    final onGradient = _onPrimary();

    return Column(
      children: [
        Icon(icon, color: onGradient, size: 24),
        SizedBox(height: 5),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: onGradient,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: onGradient.withAlpha(189)),
        ),
      ],
    );
  }

  // ============================================
  // GRADE DE ALUNOS
  // ============================================
  Widget _buildAlunoGridItem(Map<String, dynamic> aluno) {
    final alunoId = aluno['id'] as String;
    final nomeAluno = aluno['nome'] as String;
    final nomeAlunoExibicao = _nomeAlunoCurto(nomeAluno);
    final estaPresente = _presencas[alunoId] ?? false;
    final temObservacao = (_observacoes[alunoId] ?? '').trim().isNotEmpty;
    final fotoUrl = aluno['foto'] as String?;
    final indicadorColor = _corIndicadorAusencia(aluno);
    final alertaAtivo = _indicadorGeraAlerta(aluno) && !estaPresente;
    final alertaPiscando = alertaAtivo && _alertaPiscaLigado;

    final suspenso = _suspensoNaAula(alunoId);
    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: alertaAtivo
                  ? indicadorColor.withAlpha(alertaPiscando ? 133 : 46)
                  : estaPresente
                  ? context.uai.success.withAlpha(46)
                  : context.uai.error.withAlpha(36),
              blurRadius: alertaAtivo
                  ? (alertaPiscando ? 18 : 9)
                  : estaPresente
                  ? 13
                  : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _impedidoNaAula(alunoId)
                ? _avisarSuspensao(alunoId)
                : _togglePresenca(alunoId),
            onLongPress: () => _adicionarObservacao(alunoId, nomeAluno),
            borderRadius: BorderRadius.circular(22),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: context.uai.card,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: alertaAtivo
                      ? indicadorColor.withAlpha(alertaPiscando ? 250 : 117)
                      : estaPresente
                      ? context.uai.success
                      : context.uai.error.withAlpha(179),
                  width: alertaAtivo
                      ? (alertaPiscando ? 2.8 : 1.8)
                      : estaPresente
                      ? 2.2
                      : 1.8,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Column(
                        children: [
                          Expanded(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _buildFotoAlunoSegura(
                                  alunoId: alunoId,
                                  fotoUrl: fotoUrl,
                                  nome: nomeAluno,
                                  fit: BoxFit.cover,
                                  cacheWidth: 420,
                                  placeholderSize: 68,
                                  emEscalaCinza: suspenso,
                                ),
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.center,
                                        colors: [
                                          Colors.black.withAlpha(148),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 10,
                                  right: 10,
                                  bottom: 10,
                                  child: Center(
                                    child: Container(
                                      constraints: const BoxConstraints(
                                        maxWidth: 132,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withAlpha(87),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: Colors.white.withAlpha(26),
                                        ),
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          nomeAlunoExibicao,
                                          textAlign: TextAlign.center,
                                          softWrap: false,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            height: 1.08,
                                            shadows: [
                                              Shadow(
                                                color: Colors.black.withAlpha(
                                                  (255.0 * (0.55)).round(),
                                                ),
                                                blurRadius: 8,
                                                offset: const Offset(0, 1),
                                              ),
                                            ],
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                            decoration: BoxDecoration(
                              color: suspenso
                                  ? context.uai.error.withAlpha(18)
                                  : estaPresente
                                  ? context.uai.success.withAlpha(26)
                                  : context.uai.error.withAlpha(26),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (suspenso ||
                                    (_indicadoresAusenciaAtivo &&
                                        _mostrarTextoUltimaPresencaIndicador))
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text(
                                      suspenso
                                          ? 'Aluno suspenso nesta data'
                                          : _textoUltimaPresenca(aluno),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: suspenso
                                            ? context.uai.error
                                            : indicadorColor,
                                        fontSize: 9.8,
                                        fontWeight: FontWeight.w900,
                                        height: 1,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black.withAlpha(
                                              (255.0 * (0.10)).round(),
                                            ),
                                            blurRadius: 2,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                Center(
                                  child: _impedidoNaAula(alunoId)
                                      ? _buildChipSuspensoGrid(alunoId)
                                      : SizedBox(
                                          width: 108,
                                          height: 31,
                                          child: ElevatedButton.icon(
                                            onPressed: () =>
                                                _togglePresenca(alunoId),
                                            style: ElevatedButton.styleFrom(
                                              elevation: 0,
                                              backgroundColor: estaPresente
                                                  ? context.uai.success
                                                  : context.uai.primary,
                                              foregroundColor: _readableOn(
                                                estaPresente
                                                    ? context.uai.success
                                                    : context.uai.primary,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(17),
                                              ),
                                            ),
                                            icon: Icon(
                                              estaPresente
                                                  ? Icons.check_circle_rounded
                                                  : Icons
                                                        .radio_button_unchecked_rounded,
                                              size: 15,
                                            ),
                                            label: Text(
                                              estaPresente
                                                  ? 'Presente'
                                                  : 'Marcar',
                                              style: const TextStyle(
                                                fontSize: 10.8,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => _adicionarObservacao(alunoId, nomeAluno),
                        child: Container(
                          padding: EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: temObservacao
                                ? context.uai.warning
                                : Colors.white.withAlpha(240),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(41),
                                blurRadius: 7,
                              ),
                            ],
                          ),
                          child: Icon(
                            temObservacao
                                ? Icons.sticky_note_2_rounded
                                : Icons.note_add_outlined,
                            size: 17,
                            color: temObservacao
                                ? _readableOn(context.uai.warning)
                                : _ensureVisible(
                                    context.uai.info,
                                    Colors.white,
                                  ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: estaPresente
                              ? context.uai.success
                              : context.uai.error,
                          shape: BoxShape.circle,
                          border: Border.all(color: context.uai.card, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(46),
                              blurRadius: 5,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_indicadoresAusenciaAtivo)
                      Positioned(
                        top: 8,
                        left: 27,
                        child: _buildIndicadorBolinha(aluno, size: 12),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlunoCompactTile(
    Map<String, dynamic> aluno, {
    EdgeInsetsGeometry? margin,
  }) {
    final alunoId = aluno['id'] as String;
    final nomeAluno = aluno['nome'] as String;
    final nomeAlunoExibicao = _nomeAlunoCurto(nomeAluno);
    final graduacao = aluno['graduacao_nome']?.toString() ?? '';
    final fotoUrl = aluno['foto'] as String?;
    final estaPresente = _presencas[alunoId] ?? false;
    final temObservacao = (_observacoes[alunoId] ?? '').trim().isNotEmpty;
    final suspenso = _suspensoNaAula(alunoId);
    return Container(
      margin: margin ?? EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: estaPresente
              ? context.uai.success.withAlpha(140)
              : context.uai.border,
          width: estaPresente ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(11),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          onTap: () => _impedidoNaAula(alunoId)
              ? _avisarSuspensao(alunoId)
              : _togglePresenca(alunoId),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              _buildAlunoAvatarMini(
                alunoId,
                fotoUrl,
                nomeAluno,
                estaPresente,
                emEscalaCinza: suspenso,
              ),
              if (_indicadoresAusenciaAtivo)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: _buildIndicadorBolinha(aluno, size: 12),
                ),
            ],
          ),
          title: Text(
            nomeAlunoExibicao,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: estaPresente
                  ? context.uai.success
                  : context.uai.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            suspenso
                ? 'SUSPENSO ATÉ ${_formatarDataDisciplina(_eventoDisciplinaAluno(alunoId)?['data_retorno'] ?? _eventoDisciplinaAluno(alunoId)?['fim_exclusivo'])}'
                : graduacao.isNotEmpty
                ? graduacao
                : (estaPresente ? 'Presente na chamada' : 'Ausente na chamada'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: context.uai.textSecondary),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (temObservacao)
                Icon(
                  Icons.sticky_note_2_rounded,
                  color: context.uai.warning,
                  size: 20,
                ),
              IconButton(
                tooltip: 'Observação',
                onPressed: () => _adicionarObservacao(alunoId, nomeAluno),
                icon: Icon(Icons.note_add_outlined, color: context.uai.info),
              ),
              if (_impedidoNaAula(alunoId))
                _buildChipSuspensoGrid(alunoId)
              else
                Switch(
                  value: estaPresente,
                  activeThumbColor: context.uai.success,
                  onChanged: suspenso ? null : (_) => _togglePresenca(alunoId),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlunoAvatarMini(
    String alunoId,
    String? fotoUrl,
    String nome,
    bool presente, {
    bool emEscalaCinza = false,
  }) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: presente ? context.uai.success : context.uai.border,
          width: 2,
        ),
      ),
      child: ClipOval(
        child: _buildFotoAlunoSegura(
          alunoId: alunoId,
          fotoUrl: fotoUrl,
          nome: nome,
          fit: BoxFit.cover,
          cacheWidth: 140,
          placeholderSize: 24,
          circular: true,
          emEscalaCinza: emEscalaCinza,
        ),
      ),
    );
  }

  Widget _buildFotoAlunoSegura({
    required String alunoId,
    required String? fotoUrl,
    required String nome,
    required BoxFit fit,
    required int cacheWidth,
    double placeholderSize = 50,
    bool circular = false,
    bool emEscalaCinza = false,
  }) {
    final url = fotoUrl?.trim() ?? '';
    final inicial = nome.trim().isEmpty ? '?' : nome.trim()[0].toUpperCase();

    Widget fallback({Color? backgroundColor}) {
      return Container(
        color: backgroundColor ?? context.uai.cardAlt,
        child: Center(
          child: circular
              ? Text(
                  inicial,
                  style: TextStyle(
                    color: context.uai.textSecondary,
                    fontWeight: FontWeight.bold,
                    fontSize: placeholderSize,
                  ),
                )
              : Icon(
                  Icons.person_rounded,
                  size: placeholderSize,
                  color: context.uai.textMuted,
                ),
        ),
      );
    }

    Widget child;
    if (url.isEmpty ||
        !(url.startsWith('http://') || url.startsWith('https://'))) {
      child = fallback();
    } else {
      child = UaiStudentPhoto(
        studentId: alunoId,
        imageUrl: url,
        profile: cacheWidth <= 192
            ? UaiStudentPhotoProfile.compact
            : UaiStudentPhotoProfile.grid,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        fallback: fallback(),
        placeholder: fallback(),
      );
    }

    if (emEscalaCinza) {
      child = ColorFiltered(
        colorFilter: ColorFilter.matrix(_matrizEscalaCinza()),
        child: child,
      );
    }
    return child;
  }

  // ============================================
  // HEADER DA CHAMADA
  // ============================================
  Widget _buildChamadaHeader() {
    final presentes = _presencas.values.where((v) => v).length;
    final total = _alunos.length;
    final ausentes = total - presentes;
    final porcentagem = total > 0 ? (presentes / total * 100).round() : 0;

    return Container(
      margin: EdgeInsets.fromLTRB(10, 6, 10, 4),
      padding: EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        gradient: context.uai.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.uai.primary.withAlpha(31),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_rounded, color: _onPrimary(), size: 19),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.turmaNome,
                  style: TextStyle(
                    color: _onPrimary(),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${DateFormat('dd/MM').format(_dataChamada)} • $_tipoAulaHoje',
                style: TextStyle(
                  color: _onPrimary().withAlpha(199),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              _buildHeaderTinyStat('P', presentes, context.uai.success),
              SizedBox(width: 6),
              _buildHeaderTinyStat('A', ausentes, context.uai.error),
              SizedBox(width: 6),
              _buildHeaderTinyStat('T', total, _onPrimary()),
              SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: total > 0 ? presentes / total : 0,
                    minHeight: 6,
                    backgroundColor: _onPrimary().withAlpha(51),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _headerAccent(
                        presentes == 0
                            ? context.uai.error
                            : presentes == total
                            ? context.uai.success
                            : context.uai.warning,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Text(
                '$porcentagem%',
                style: TextStyle(
                  color: _onPrimary(),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (_telepatiaAtiva && _telepatiaUsandoChamadaReal) ...[
            const SizedBox(height: 8),
            _buildChamadaMensagemSecreta(
              icon: Icons.psychology_alt_rounded,
              text: _telepatiaRodando
                  ? _telepatiaMensagem
                  : _telepatiaConcluida
                  ? 'Chamada concluída por presença espiritual.'
                  : 'Preparando chamada...',
            ),
          ] else if (_chamadaInversaRodando) ...[
            const SizedBox(height: 8),
            _buildChamadaMensagemSecreta(
              icon: Icons.sync_rounded,
              text: 'Sincronizando presença automática...',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChamadaMensagemSecreta({
    required IconData icon,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _onPrimary().withAlpha(33),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _onPrimary().withAlpha(41)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _onPrimary()),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text.replaceAll('\n', ' '),
              style: TextStyle(
                color: _onPrimary(),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderTinyStat(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: _onPrimary().withAlpha(33),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _onPrimary().withAlpha(41)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(
                color: _onPrimary().withAlpha(179),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: '$value',
              style: TextStyle(
                color: _ensureVisible(color, context.uai.primary),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getTipoAulaColor(String tipoAula) {
    switch (tipoAula.toUpperCase()) {
      case 'OBJETIVA':
        return context.uai.info;
      case 'INSTRUMENTAÇÃO':
        return context.uai.associacao;
      case 'RODA':
        return context.uai.primaryDark;
      default:
        return context.uai.textMuted;
    }
  }

  IconData _getTipoAulaIcon(String tipoAula) {
    switch (tipoAula.toUpperCase()) {
      case 'OBJETIVA':
        return Icons.flag;
      case 'INSTRUMENTAÇÃO':
        return Icons.music_note;
      case 'RODA':
        return Icons.group;
      default:
        return Icons.fitness_center;
    }
  }

  bool _isChamadaDesktop(double width) => width >= 700;

  double _maxChamadaContentWidth(double width) {
    if (width >= 1600) return 1640;
    if (width >= 1200) return 1480;
    if (width >= 900) return 1180;
    return width;
  }

  EdgeInsets _gridPaddingForWidth(double width) {
    if (width >= 1200) return const EdgeInsets.fromLTRB(18, 10, 18, 18);
    if (width >= 700) return const EdgeInsets.fromLTRB(14, 8, 14, 16);
    return const EdgeInsets.fromLTRB(14, 8, 14, 14);
  }

  SliverGridDelegate _gridDelegateForChamada(double width) {
    if (!_isChamadaDesktop(width)) {
      return const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.76,
      );
    }

    return const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 245,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      childAspectRatio: 0.76,
    );
  }

  SliverGridDelegate _compactDelegateForChamada(double width) {
    return const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 560,
      mainAxisExtent: 82,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
    );
  }

  Widget _buildAlunosList() {
    if (_alunos.isEmpty) {
      return _buildListaVazia(
        icon: Icons.people_outline_rounded,
        title: 'Nenhum aluno nesta turma',
        subtitle: 'Confira se os alunos estão ativos e vinculados à turma.',
      );
    }

    final alunos = _alunosFiltrados;

    return LayoutBuilder(
      builder: (context, constraints) {
        final larguraTela = constraints.maxWidth;
        final maxWidth = _maxChamadaContentWidth(larguraTela);
        final isDesktop = _isChamadaDesktop(larguraTela);

        return Column(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: _buildPainelControleChamada(),
              ),
            ),
            Expanded(
              child: alunos.isEmpty
                  ? _buildListaVazia(
                      icon: Icons.search_off_rounded,
                      title: 'Nenhum aluno neste filtro',
                      subtitle:
                          'Toque em "Todos" para voltar para a chamada completa.',
                    )
                  : Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: _modoListaCompacta
                            ? isDesktop
                                  ? GridView.builder(
                                      controller:
                                          (_telepatiaAtiva &&
                                              _telepatiaUsandoChamadaReal)
                                          ? _telepatiaScrollController
                                          : null,
                                      scrollCacheExtent:
                                          const ScrollCacheExtent.pixels(700),
                                      padding: _gridPaddingForWidth(
                                        larguraTela,
                                      ),
                                      gridDelegate: _compactDelegateForChamada(
                                        larguraTela,
                                      ),
                                      itemCount: alunos.length,
                                      itemBuilder: (context, index) =>
                                          _buildAlunoCompactTile(
                                            alunos[index],
                                            margin: EdgeInsets.zero,
                                          ),
                                    )
                                  : ListView.builder(
                                      controller:
                                          (_telepatiaAtiva &&
                                              _telepatiaUsandoChamadaReal)
                                          ? _telepatiaScrollController
                                          : null,
                                      scrollCacheExtent:
                                          const ScrollCacheExtent.pixels(500),
                                      padding: const EdgeInsets.only(
                                        top: 6,
                                        bottom: 14,
                                      ),
                                      itemCount: alunos.length,
                                      itemBuilder: (context, index) =>
                                          _buildAlunoCompactTile(alunos[index]),
                                    )
                            : GridView.builder(
                                controller:
                                    (_telepatiaAtiva &&
                                        _telepatiaUsandoChamadaReal)
                                    ? _telepatiaScrollController
                                    : null,
                                scrollCacheExtent:
                                    const ScrollCacheExtent.pixels(800),
                                padding: _gridPaddingForWidth(larguraTela),
                                gridDelegate: _gridDelegateForChamada(
                                  larguraTela,
                                ),
                                itemCount: alunos.length,
                                itemBuilder: (context, index) =>
                                    _buildAlunoGridItem(alunos[index]),
                              ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPainelControleChamada() {
    final total = _alunos.length;
    final filtrados = _alunosFiltrados.length;
    final presentesFiltrados = _presentesFiltrados;

    return Container(
      color: context.uai.surface,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFiltroPresencaChip('Todos', Icons.groups_rounded),
                _buildFiltroPresencaChip(
                  'Presentes',
                  Icons.check_circle_rounded,
                ),
                _buildFiltroPresencaChip('Ausentes', Icons.cancel_rounded),
                _buildFiltroPresencaChip(
                  'Com observação',
                  Icons.sticky_note_2_rounded,
                ),
                SizedBox(width: 4),
                _buildModoVisualBotao(),
              ],
            ),
          ),
          SizedBox(height: 6),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: context.uai.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.uai.border),
              boxShadow: context.uai.softShadow,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.touch_app_rounded,
                  size: 16,
                  color: context.uai.primary,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$presentesFiltrados presentes • $filtrados/$total alunos',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.uai.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildMiniAcao(
                  label: 'Todos',
                  icon: Icons.done_all_rounded,
                  color: context.uai.success,
                  onTap: () => _marcarTodosFiltrados(true),
                ),
                SizedBox(width: 5),
                _buildMiniAcao(
                  label: 'Zerar',
                  icon: Icons.remove_done_rounded,
                  color: context.uai.primaryDark,
                  onTap: () => _marcarTodosFiltrados(false),
                ),
                SizedBox(width: 5),
                _buildMiniAcao(
                  label: 'Inverter',
                  icon: Icons.swap_vert_rounded,
                  color: context.uai.info,
                  onTap: _inverterFiltrados,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModoVisualBotao() {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: InkWell(
        onTap: () => setState(() => _modoListaCompacta = !_modoListaCompacta),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: context.uai.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.uai.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _modoListaCompacta
                    ? Icons.grid_view_rounded
                    : Icons.view_list_rounded,
                size: 15,
                color: context.uai.primary,
              ),
              SizedBox(width: 6),
              Text(
                _modoListaCompacta ? 'Grade' : 'Lista',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: context.uai.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFiltroPresencaChip(String filtro, IconData icon) {
    final ativo = _filtroPresenca == filtro;

    return Padding(
      padding: EdgeInsets.only(right: 7),
      child: ChoiceChip(
        selected: ativo,
        avatar: Icon(
          icon,
          size: 15,
          color: ativo
              ? _readableOn(context.uai.primary)
              : context.uai.textSecondary,
        ),
        label: Text(
          filtro,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: ativo
                ? _readableOn(context.uai.primary)
                : context.uai.textSecondary,
          ),
        ),
        selectedColor: context.uai.primary,
        backgroundColor: context.uai.card,
        side: BorderSide(
          color: ativo ? context.uai.primary : context.uai.border,
        ),
        onSelected: (_) => setState(() {
          _filtroPresenca = filtro;
          _invalidarCacheFiltro();
        }),
      ),
    );
  }

  Widget _buildMiniAcao({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final accent = _ensureVisible(color, context.uai.card);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withAlpha(31),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withAlpha(61)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: accent),
            SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: accent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListaVazia({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 72, color: context.uai.border),
            SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                color: context.uai.textSecondary,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.uai.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelaProgresso() {
    return Center(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Container(
            margin: EdgeInsets.all(24),
            padding: EdgeInsets.all(30),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [context.uai.primary, context.uai.primaryDark],
              ),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(51),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_upload, size: 60, color: _onPrimary()),
                SizedBox(height: 20),
                Text(
                  'PROCESSANDO CHAMADA',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _onPrimary(),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _onPrimary().withAlpha(36),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _onPrimary().withAlpha(41)),
                  ),
                  child: Text(
                    _statusMensagem,
                    style: TextStyle(
                      fontSize: 14,
                      color: _onPrimary().withAlpha(230),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(height: 30),
                CircularProgressIndicator(color: _onPrimary()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================
  // TELAS DE ESTADO
  // ============================================
  @override
  Widget build(BuildContext context) {
    if (_verificandoLock) {
      return Scaffold(
        backgroundColor: context.uai.background,
        appBar: AppBar(
          backgroundColor: _appBarBg(),
          foregroundColor: _appBarFg(),
          title: Text('VERIFICANDO CHAMADA'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: context.uai.primary),
              SizedBox(height: 20),
              Text(
                '🔒 Verificando disponibilidade da chamada...',
                style: TextStyle(fontSize: 14, color: context.uai.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    if (!_podeAcessarChamada && _ocupanteInfo != null) {
      return _buildTelaChamadaOcupada();
    }

    if (_erroUsuarioId) {
      return Scaffold(
        backgroundColor: context.uai.background,
        appBar: AppBar(
          backgroundColor: _appBarBg(),
          foregroundColor: _appBarFg(),
          title: Text('Erro de Autenticação'),
          leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 80, color: context.uai.error),
                SizedBox(height: 20),
                Text(
                  '❌ ERRO DE AUTENTICAÇÃO',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: context.uai.primaryDark,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 15),
                Text(
                  'Usuário não identificado. Faça login novamente para continuar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: context.uai.textMuted),
                ),
                SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _appBarBg(),
                    foregroundColor: _appBarFg(),
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  icon: Icon(Icons.arrow_back),
                  label: Text('VOLTAR'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        backgroundColor: _appBarBg(),
        foregroundColor: _appBarFg(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CHAMADA', style: TextStyle(fontSize: 16)),
            Text(
              widget.turmaNome,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          if (_isAdmin && !_salvandoChamada)
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: ElevatedButton.icon(
                onPressed: _abrirChamadaEspecial,
                icon: Icon(Icons.calendar_month, size: 18),
                label: Text('ESPECIAL', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _appBarFg().withAlpha(46),
                  foregroundColor: _appBarFg(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 2,
                ),
              ),
            ),
          SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: context.uai.primary),
                  SizedBox(height: 16),
                  Text(
                    'Carregando dados...',
                    style: TextStyle(color: context.uai.textSecondary),
                  ),
                ],
              ),
            )
          : _chamadaJaFeitaHoje &&
                !(_telepatiaAtiva && _telepatiaUsandoChamadaReal)
          ? SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(height: 20),
                  _buildDetalhesChamadaExistente(),
                ],
              ),
            )
          : _podeFazerChamada
          ? _salvandoChamada
                ? _buildTelaProgresso()
                : _buildTelaChamada()
          : _buildTelaSemAula(),
    );
  }

  Widget _buildTelaChamadaOcupada() {
    final ocupanteNome = _ocupanteInfo?['usuario_nome'] ?? 'outro professor';
    final timestamp = _ocupanteInfo?['timestamp'] as Timestamp?;
    final horaOcupacao = timestamp != null
        ? DateFormat('HH:mm').format(timestamp.toDate())
        : 'agora';

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        backgroundColor: _appBarBg(),
        foregroundColor: _appBarFg(),
        title: Text('CHAMADA OCUPADA'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: context.uai.warning.withAlpha(26),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.uai.warning.withAlpha(71),
                    width: 3,
                  ),
                ),
                child: Icon(
                  Icons.lock_outline,
                  size: 80,
                  color: context.uai.warning,
                ),
              ),
              SizedBox(height: 30),
              Text(
                '🔒 CHAMADA OCUPADA',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: context.uai.warning,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'A chamada desta turma já está sendo realizada por:',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: context.uai.textSecondary,
                ),
              ),
              SizedBox(height: 20),
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: context.uai.warning.withAlpha(26),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: context.uai.warning.withAlpha(71)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.person, size: 50, color: context.uai.warning),
                    SizedBox(height: 10),
                    Text(
                      ocupanteNome,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.uai.textPrimary,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Desde às $horaOcupacao',
                      style: TextStyle(
                        fontSize: 14,
                        color: context.uai.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 30),
              Text(
                'Apenas um professor pode realizar a chamada por vez para evitar conflitos.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: context.uai.textMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
              SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _appBarBg(),
                  foregroundColor: _appBarFg(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: Icon(Icons.arrow_back),
                label: Text(
                  'VOLTAR PARA A TURMA',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTelaChamada() {
    final presentes = _presencas.values.where((v) => v).length;
    final total = _alunos.length;
    final ausentes = total - presentes;

    return LayoutBuilder(
      builder: (context, constraints) {
        final larguraTela = constraints.maxWidth;
        final maxWidth = _maxChamadaContentWidth(larguraTela);

        return Column(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: _buildChamadaHeader(),
              ),
            ),
            Expanded(child: _buildAlunosList()),
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  larguraTela >= 700 ? 18 : 14,
                  10,
                  larguraTela >= 700 ? 18 : 14,
                  12,
                ),
                decoration: BoxDecoration(
                  color: context.uai.cardAlt,
                  border: Border(top: BorderSide(color: context.uai.border)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(20),
                      blurRadius: 14,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Align(
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _salvandoChamada
                                ? null
                                : _confirmarLimparChamada,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _ensureVisible(
                                context.uai.primary,
                                context.uai.cardAlt,
                              ),
                              side: BorderSide(
                                color: _ensureVisible(
                                  context.uai.error,
                                  context.uai.cardAlt,
                                ).withAlpha(61),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: Icon(
                              Icons.cleaning_services_rounded,
                              size: 18,
                            ),
                            label: Text(
                              'LIMPAR',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          flex: larguraTela >= 700 ? 3 : 2,
                          child: ElevatedButton(
                            onPressed: _salvandoChamada ? null : _salvarChamada,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _saveButtonBg(),
                              foregroundColor: _saveButtonFg(),
                              disabledBackgroundColor: context.uai.border,
                              disabledForegroundColor:
                                  context.uai.textSecondary,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 4,
                            ),
                            child: _salvandoChamada
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: _saveButtonFg(),
                                        ),
                                      ),
                                      SizedBox(width: 10),
                                      Text(
                                        'SALVANDO...',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        (_telepatiaAtiva &&
                                                _telepatiaUsandoChamadaReal)
                                            ? Icons.psychology_alt_rounded
                                            : Icons.cloud_done_rounded,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          (_telepatiaAtiva &&
                                                  _telepatiaUsandoChamadaReal)
                                              ? 'FINALIZAR • $presentes P / $ausentes A'
                                              : 'SALVAR • $presentes P / $ausentes A',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTelaSemAula() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 80, color: context.uai.textMuted),
            SizedBox(height: 20),
            Text(
              '📅 AULA NÃO MARCADA PARA HOJE',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.uai.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 15),
            Text(
              _mensagemAulaHoje,
              style: TextStyle(fontSize: 14, color: context.uai.textSecondary),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _appBarBg(),
                foregroundColor: _appBarFg(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.arrow_back),
              label: const Text('VOLTAR'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetalhesChamadaExistente() {
    if (_chamadaExistente == null) {
      return const Center(
        child: Text('Nenhuma informação de chamada disponível'),
      );
    }

    final dataTimestamp = _chamadaExistente!['data_chamada'];
    DateTime dataChamada;
    if (dataTimestamp is Timestamp) {
      dataChamada = dataTimestamp.toDate();
    } else if (dataTimestamp is DateTime) {
      dataChamada = dataTimestamp;
    } else {
      dataChamada = DateTime.now();
    }

    final horaFormatada = DateFormat('HH:mm').format(dataChamada);
    final presentes = _chamadaExistente!['presentes'] ?? 0;
    final total = _chamadaExistente!['total_alunos'] ?? 0;
    final porcentagem =
        _chamadaExistente!['porcentagem_frequencia'] ??
        (total > 0 ? (presentes / total * 100).round() : 0);
    final tipoAula = _chamadaExistente!['tipo_aula'] ?? _tipoAulaHoje;
    final professorNome =
        _chamadaExistente!['professor_nome'] ?? _professorNome;
    final professorId = _chamadaExistente!['professor_id'] ?? _professorId;
    final List<dynamic> alunosChamada = _chamadaExistente!['alunos'] ?? [];
    final presentesList = alunosChamada
        .where((a) => a['presente'] == true)
        .toList();
    final ausentesList = alunosChamada
        .where((a) => a['presente'] == false)
        .toList();

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [context.uai.success, context.uai.success],
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(25),
                bottomRight: Radius.circular(25),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.celebration,
                  size: 60,
                  color: _readableOn(context.uai.success),
                ),
                SizedBox(height: 10),
                Text(
                  '🎉 CHAMADA CONCLUÍDA!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _readableOn(context.uai.success),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  DateFormat("EEEE, dd/MM/yyyy", 'pt_BR').format(dataChamada),
                  style: TextStyle(
                    fontSize: 14,
                    color: _readableOn(context.uai.success).withAlpha(230),
                  ),
                ),
                Text(
                  'Horário: $horaFormatada',
                  style: TextStyle(
                    fontSize: 13,
                    color: _readableOn(context.uai.success).withAlpha(204),
                  ),
                ),
                SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getTipoAulaColor(tipoAula).withAlpha(51),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getTipoAulaIcon(tipoAula),
                        size: 14,
                        color: _readableOn(context.uai.success),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'TIPO DA AULA: $tipoAula',
                        style: TextStyle(
                          fontSize: 12,
                          color: _readableOn(context.uai.success),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _readableOn(context.uai.success).withAlpha(41),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person,
                            size: 16,
                            color: _readableOn(context.uai.success),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Professor: $professorNome',
                            style: TextStyle(
                              fontSize: 13,
                              color: _readableOn(context.uai.success),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      if (professorId.isNotEmpty) ...[
                        SizedBox(height: 4),
                        Text(
                          'ID: ${professorId.length > 6 ? professorId.substring(0, 6) : professorId}...',
                          style: TextStyle(
                            fontSize: 10,
                            color: _readableOn(
                              context.uai.success,
                            ).withAlpha(179),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatCardExistente(
                  Icons.check_circle,
                  'Presentes',
                  '$presentes',
                  context.uai.success,
                  '$porcentagem%',
                ),
                _buildStatCardExistente(
                  Icons.cancel,
                  'Ausentes',
                  '${total - presentes}',
                  context.uai.error,
                  '${100 - porcentagem}%',
                ),
                _buildStatCardExistente(
                  Icons.people,
                  'Total',
                  '$total',
                  context.uai.info,
                  '100%',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    children: [
                      Container(height: 12, color: context.uai.error),
                      FractionallySizedBox(
                        widthFactor: total > 0
                            ? (presentes / total).clamp(0.0, 1.0)
                            : 0.0,
                        child: Container(
                          height: 12,
                          color: context.uai.success,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$presentes presentes',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.uai.success,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${total - presentes} ausentes',
                      style: TextStyle(
                        fontSize: 12,
                        color: _ensureVisible(
                          context.uai.error,
                          context.uai.background,
                        ),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              color: context.uai.card,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
                side: BorderSide(color: context.uai.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(bottom: 15),
                      child: Row(
                        children: [
                          Icon(Icons.list, color: _onCard()),
                          SizedBox(width: 10),
                          Text(
                            'LISTA DE ALUNOS',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _onCard(),
                            ),
                          ),
                          const Spacer(),
                          Chip(
                            label: Text(
                              '$total alunos',
                              style: TextStyle(
                                fontSize: 12,
                                color: _readableOn(context.uai.info),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            backgroundColor: context.uai.info,
                          ),
                        ],
                      ),
                    ),
                    if (presentesList.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: context.uai.success,
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'PRESENTES (${presentesList.length})',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _ensureVisible(
                                    context.uai.success,
                                    context.uai.card,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: presentesList.map((aluno) {
                              return Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: context.uai.success.withAlpha(26),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: context.uai.success.withAlpha(
                                      (255.0 * (0.28)).round(),
                                    ),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.person,
                                      size: 14,
                                      color: _ensureVisible(
                                        context.uai.success,
                                        context.uai.card,
                                      ),
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      _abreviarNome(
                                        aluno['aluno_nome']?.toString() ?? '',
                                      ),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _ensureVisible(
                                          context.uai.success,
                                          context.uai.card,
                                        ),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                          SizedBox(height: 15),
                        ],
                      ),
                    if (ausentesList.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(
                                Icons.cancel,
                                color: context.uai.error,
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'AUSENTES (${ausentesList.length})',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _ensureVisible(
                                    context.uai.error,
                                    context.uai.card,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: ausentesList.map((aluno) {
                              return Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: context.uai.error.withAlpha(26),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: context.uai.error.withAlpha(71),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.person_outline,
                                      size: 14,
                                      color: _ensureVisible(
                                        context.uai.error,
                                        context.uai.card,
                                      ),
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      _abreviarNome(
                                        aluno['aluno_nome']?.toString() ?? '',
                                      ),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _ensureVisible(
                                          context.uai.error,
                                          context.uai.card,
                                        ),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_temObservacoes(alunosChamada))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Card(
                color: context.uai.card,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: context.uai.border),
                ),
                child: Padding(
                  padding: EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.note, color: context.uai.warning),
                          SizedBox(width: 10),
                          Text(
                            'OBSERVAÇÕES',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: context.uai.warning,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                      ...alunosChamada
                          .where(
                            (a) =>
                                (a['observacao'] as String?)?.isNotEmpty ==
                                true,
                          )
                          .map((aluno) {
                            return Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.arrow_right,
                                    size: 16,
                                    color: context.uai.textSecondary,
                                  ),
                                  SizedBox(width: 5),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          aluno['aluno_nome']?.toString() ?? '',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: context.uai.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          aluno['observacao']?.toString() ?? '',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: context.uai.textSecondary,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: context.uai.info.withAlpha(26),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.uai.info.withAlpha(71)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.timer, color: context.uai.info, size: 18),
                      SizedBox(width: 8),
                      TweenAnimationBuilder<Duration>(
                        duration: const Duration(seconds: 10),
                        tween: Tween(
                          begin: const Duration(seconds: 10),
                          end: Duration.zero,
                        ),
                        onEnd: () {
                          if (mounted) Navigator.pop(context);
                        },
                        builder: (context, value, child) {
                          final seconds = value.inSeconds;
                          return Text(
                            'Fechando em $seconds segundos...',
                            style: TextStyle(
                              color: _ensureVisible(
                                context.uai.info,
                                context.uai.card,
                              ),
                              fontWeight: FontWeight.w700,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _appBarBg(),
                      foregroundColor: _appBarFg(),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 3,
                    ),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text(
                      'VOLTAR PARA A TURMA',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCardExistente(
    IconData icon,
    String label,
    String value,
    Color color,
    String subValue,
  ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withAlpha(26),
            shape: BoxShape.circle,
            border: Border.all(color: color.withAlpha(77), width: 2),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: context.uai.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 4),
        Text(
          subValue,
          style: TextStyle(fontSize: 10, color: context.uai.textMuted),
        ),
      ],
    );
  }

  String _abreviarNome(String nomeCompleto) {
    final partes = nomeCompleto.split(' ');
    if (partes.length >= 2) {
      return '${partes[0][0]}. ${partes[partes.length - 1]}';
    }
    return nomeCompleto.length > 12
        ? '${nomeCompleto.substring(0, 10)}...'
        : nomeCompleto;
  }

  bool _temObservacoes(List<dynamic> alunosChamada) {
    for (var aluno in alunosChamada) {
      final observacao = aluno['observacao'] as String?;
      if (observacao != null && observacao.isNotEmpty) {
        return true;
      }
    }
    return false;
  }
}
