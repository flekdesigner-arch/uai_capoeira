// chamada_turma_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uai_capoeira/services/lock_chamada_service.dart';
import 'chamada_especial_screen.dart';

// ============================================
// TELA PRINCIPAL - CHAMADA TURMA (COM CLOUD FUNCTION)
// ============================================

class ChamadaTurmaScreen extends StatefulWidget {
  final String turmaId;
  final String turmaNome;
  final String academiaId;
  final String academiaNome;
  final String usuarioId;

  const ChamadaTurmaScreen({
    super.key,
    required this.turmaId,
    required this.turmaNome,
    required this.academiaId,
    required this.academiaNome,
    required this.usuarioId,
  });

  @override
  State<ChamadaTurmaScreen> createState() => _ChamadaTurmaScreenState();
}

class _ChamadaTurmaScreenState extends State<ChamadaTurmaScreen> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // 🔥 ESTADOS PARA LOCK
  bool _verificandoLock = true;
  bool _podeAcessarChamada = false;
  Map<String, dynamic>? _ocupanteInfo;
  Stream<Map<String, dynamic>?>? _ocupacaoStream;

  // Estados principais
  bool _isLoading = true;
  bool _podeFazerChamada = false;
  bool _chamadaJaFeitaHoje = false;
  bool _salvandoChamada = false;

  String _mensagemAulaHoje = '';

  // Dados da chamada
  List<Map<String, dynamic>> _alunos = [];
  Map<String, bool> _presencas = {};
  Map<String, String> _observacoes = {};
  DateTime _dataChamada = DateTime.now();

  // Controles
  final TextEditingController _observacaoController = TextEditingController();

  // Dados da turma
  List<String> _diasTreinoTurma = [];
  String _diaSemanaHoje = '';
  String _diaSemanaAbrevHoje = '';
  String _tipoAulaHoje = 'OBJETIVA';
  Map<String, dynamic>? _chamadaExistente;

  // Dados do professor
  String _professorNome = 'Carregando...';
  String _professorId = '';
  bool _carregouDadosProfessor = false;
  bool _erroUsuarioId = false;

  // Permissões
  bool _isAdmin = false;
  bool _modoExtraForcado = false;

  // UI
  final Map<String, Map<String, dynamic>> _graduacoesCache = {};
  String? _svgContent;

  // 🔥 ANIMAÇÕES
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // 🔥 CONTROLE DA ANIMAÇÃO DE SALVAMENTO
  bool _mostrarProgresso = false;
  String _statusMensagem = '';

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
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    debugPrint('🚀 ChamadaTurmaScreen initState');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verificarEAcessarChamada();
    });
  }

  @override
  void dispose() {
    if (_podeAcessarChamada) {
      debugPrint('🔓 Liberando lock no dispose');
      LockChamadaService.liberarChamada(widget.turmaId);
    }
    _animationController.dispose();
    _observacaoController.dispose();
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

      if (_chamadaJaFeitaHoje) {
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
      _ocupacaoStream = _firestore
          .collection('locks_chamada')
          .doc(widget.turmaId)
          .snapshots()
          .map((snapshot) => snapshot.data());

      _ocupacaoStream!.listen((ocupante) {
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
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Icon(Icons.warning_amber, color: Colors.orange, size: 50),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '⚠️ CHAMADA INTERROMPIDA',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange),
            ),
            const SizedBox(height: 16),
            Text(
              'Outro professor assumiu o controle desta chamada:\n\n'
                  '👤 ${ocupante['usuario_nome'] ?? 'Professor'}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Você será redirecionado.',
              style: TextStyle(fontStyle: FontStyle.italic),
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
              backgroundColor: Colors.red.shade900,
              foregroundColor: Colors.white,
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
        final nomeCompleto = usuarioData['nome_completo']?.toString() ??
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
      final hoje = DateTime.now();
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
          _chamadaExistente = querySnapshot.docs.first.data();
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
      final turmaDoc = await _firestore.collection('turmas').doc(widget.turmaId).get();

      if (!turmaDoc.exists) {
        setState(() {
          _isLoading = false;
          _podeFazerChamada = false;
          _mensagemAulaHoje = 'Turma não encontrada';
        });
        return;
      }

      final turmaData = turmaDoc.data()!;
      final diasTreino = (turmaData['dias_semana'] as List<dynamic>?)
          ?.map((dia) => dia.toString().toUpperCase().trim())
          .toList() ??
          [];

      setState(() => _diasTreinoTurma = diasTreino);

      final agora = DateTime.now();
      final diaSemanaOriginal = DateFormat('EEEE', 'pt_BR').format(agora).toLowerCase();

      String diaSemanaFormatado = diaSemanaOriginal;
      if (diaSemanaOriginal.contains('segunda')) {
        diaSemanaFormatado = 'SEGUNDA';
      } else if (diaSemanaOriginal.contains('terça') || diaSemanaOriginal.contains('terca')) {
        diaSemanaFormatado = 'TERCA';
      } else if (diaSemanaOriginal.contains('quarta')) {
        diaSemanaFormatado = 'QUARTA';
      } else if (diaSemanaOriginal.contains('quinta')) {
        diaSemanaFormatado = 'QUINTA';
      } else if (diaSemanaOriginal.contains('sexta')) {
        diaSemanaFormatado = 'SEXTA';
      } else if (diaSemanaOriginal.contains('sábado') || diaSemanaOriginal.contains('sabado')) {
        diaSemanaFormatado = 'SABADO';
      } else if (diaSemanaOriginal.contains('domingo')) {
        diaSemanaFormatado = 'DOMINGO';
      }

      final diaSemanaCompleto = diaSemanaFormatado;
      final diaSemanaAbrev = _getDiaAbreviado(diaSemanaCompleto);

      final diasConfiguracao = turmaData['dias_configuracao'] as Map<String, dynamic>?;
      String tipoAulaHoje = 'OBJETIVA';

      if (diasConfiguracao != null) {
        final configuracaoDia = diasConfiguracao[diaSemanaCompleto] as Map<String, dynamic>?;
        if (configuracaoDia != null) {
          tipoAulaHoje = configuracaoDia['tipoAula']?.toString() ?? 'OBJETIVA';
        }
      }

      setState(() {
        _diaSemanaHoje = diaSemanaCompleto;
        _diaSemanaAbrevHoje = diaSemanaAbrev;
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

      if (encontrouDia || _modoExtraForcado) {
        setState(() {
          _podeFazerChamada = true;
          _mensagemAulaHoje = encontrouDia
              ? 'AULA HOJE: $diaCorrespondente'
              : '🔴 MODO ADMIN: CHAMADA EXTRA (fora do dia)';
        });
        await _carregarAlunos();
      } else {
        final diasTreinoTexto = _diasTreinoTurma.isNotEmpty
            ? _diasTreinoTurma.join(', ')
            : 'nenhum dia definido';

        setState(() {
          _podeFazerChamada = false;
          _mensagemAulaHoje = '📅 Esta turma não tem aula hoje.\n'
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
          .where('status_atividade', whereIn: ['ATIVO(A)', 'ATIVO(A) '])
          .get();

      final alunosList = alunosSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'nome': data['nome'] ?? 'Sem nome',
          'foto': data['foto_perfil_aluno'] as String?,
          'graduacao_id': data['graduacao_id'] as String?,
        };
      }).toList();

      alunosList.sort((a, b) => (a['nome'] as String).compareTo(b['nome'] as String));

      final presencasIniciais = <String, bool>{};
      for (var aluno in alunosList) {
        presencasIniciais[aluno['id'] as String] = false;
      }

      setState(() {
        _alunos = alunosList;
        _presencas = presencasIniciais;
      });

      _preloadGraduacoes();
      _loadSvg();
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

  Future<void> _loadSvg() async {
    try {
      final content = await DefaultAssetBundle.of(context).loadString('assets/images/corda.svg');
      if (mounted) {
        setState(() => _svgContent = content);
      }
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar SVG: $e');
    }
  }

  Future<void> _preloadGraduacoes() async {
    try {
      final snapshot = await _firestore.collection('graduacoes').get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        _graduacoesCache[doc.id] = {
          'hex_cor1': data.containsKey('hex_cor1') ? data['hex_cor1'] : '#CCCCCC',
          'hex_cor2': data.containsKey('hex_cor2') ? data['hex_cor2'] : '#CCCCCC',
          'hex_ponta1': data.containsKey('hex_ponta1') ? data['hex_ponta1'] : '#CCCCCC',
          'hex_ponta2': data.containsKey('hex_ponta2') ? data['hex_ponta2'] : '#CCCCCC',
          'nome_graduacao': data.containsKey('nome_graduacao') ? data['nome_graduacao'] : 'Sem graduação',
        };
      }
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
      );

      if (dataSelecionada == null) return;

      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('📅 CHAMADA ESPECIAL'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Data selecionada: ${DateFormat('dd/MM/yyyy').format(dataSelecionada)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Deseja fazer chamada para esta data?\n\n'
                      '• Pode ser qualquer dia (inclusive retroativo)\n'
                      '• A chamada será salva normalmente\n'
                      '• Os alunos serão os mesmos da turma atual',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900,
                  foregroundColor: Colors.white,
                ),
                child: const Text('CONTINUAR'),
              ),
            ],
          );
        },
      );

      if (confirm != true) return;

      if (!mounted) return;

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChamadaEspecialScreen(
            turmaId: widget.turmaId,
            turmaNome: widget.turmaNome,
            academiaId: widget.academiaId,
            academiaNome: widget.academiaNome,
            usuarioId: widget.usuarioId,
            dataSelecionada: dataSelecionada,
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
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ============================================
  // FUNÇÕES AUXILIARES
  // ============================================
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
    return diaUpper.length >= 3 ? diaUpper.substring(0, 3).toLowerCase() : diaUpper.toLowerCase();
  }

  String _formatarDiaParaComparacao(String dia) {
    final lower = dia.toLowerCase();
    return lower
        .replaceAll('segunda', 'seg')
        .replaceAll('terça', 'ter')
        .replaceAll('terca', 'ter')
        .replaceAll('quarta', 'qua')
        .replaceAll('quinta', 'qui')
        .replaceAll('sexta', 'sex')
        .replaceAll('sábado', 'sab')
        .replaceAll('sabado', 'sab')
        .replaceAll('domingo', 'dom');
  }

  void _togglePresenca(String alunoId) {
    setState(() {
      _presencas[alunoId] = !(_presencas[alunoId] ?? false);
    });
  }

  void _adicionarObservacao(String alunoId, String nomeAluno) {
    _observacaoController.text = _observacoes[alunoId] ?? '';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Observação para $nomeAluno'),
          content: TextField(
            controller: _observacaoController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Digite uma observação...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _observacoes[alunoId] = _observacaoController.text;
                });
                _observacaoController.clear();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Observação salva!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
                Navigator.pop(context);
              },
              child: const Text('Salvar'),
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
          const SnackBar(
            content: Text('❌ Erro: Usuário não identificado. Faça login novamente.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
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
          backgroundColor: Colors.red,
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
        title: const Icon(Icons.timer_off, color: Colors.red, size: 50),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '⏰ TEMPO EXPIRADO',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
            ),
            SizedBox(height: 16),
            Text(
              'O tempo para realizar esta chamada expirou.\n\n'
                  'Outro professor pode ter assumido o controle.',
              textAlign: TextAlign.center,
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
              backgroundColor: Colors.red.shade900,
              foregroundColor: Colors.white,
            ),
            child: const Text('VOLTAR'),
          ),
        ],
      ),
    );
  }

  // ============================================
  // FUNÇÃO PRINCIPAL DE SALVAR CHAMADA (COM CLOUD FUNCTION)
  // ============================================
  Future<void> _salvarChamada() async {
    final aindaTemLock = await _verificarLockAindaAtivo();
    if (!aindaTemLock) {
      _mostrarAvisoLockExpirado();
      return;
    }

    if (_alunos.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Não há alunos para salvar chamada'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final presentes = _presencas.values.where((v) => v).length;

    if (presentes == 0) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('❌ Nenhum aluno presente'),
          content: const Text('Deseja salvar a chamada mesmo sem nenhum aluno presente?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Salvar mesmo assim'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    // Preparar dados para a Cloud Function
    final dadosChamada = {
      'turmaId': widget.turmaId,
      'turmaNome': widget.turmaNome,
      'academiaId': widget.academiaId,
      'academiaNome': widget.academiaNome,
      'dataChamada': _dataChamada.toIso8601String(),
      'tipoAula': _tipoAulaHoje,
      'professorId': _professorId,
      'professorNome': _professorNome,
      'alunos': _alunos.map((aluno) => {
        'id': aluno['id'],
        'nome': aluno['nome'],
        'presente': _presencas[aluno['id']] ?? false,
        'observacao': _observacoes[aluno['id']] ?? '',
      }).toList(),
    };

    setState(() {
      _salvandoChamada = true;
      _mostrarProgresso = true;
      _statusMensagem = 'Enviando para processamento...';
    });
    _animationController.forward();

    try {
      // Chamar a Cloud Function
      setState(() {
        _statusMensagem = 'Processando chamada na nuvem...';
      });

      final HttpsCallable callable = _functions.httpsCallable('processarChamada');
      final result = await callable.call(dadosChamada);

      setState(() {
        _statusMensagem = '✅ Chamada salva com sucesso!';
      });
      await Future.delayed(const Duration(milliseconds: 500));

      if (result.data['success']) {
        // Liberar lock
        await LockChamadaService.liberarChamada(widget.turmaId);

        if (mounted) {
          _mostrarTelaConclusao({
            'presentes': result.data['presentes'],
            'ausentes': result.data['ausentes'],
            'total_alunos': result.data['processados'],
            'porcentagem_frequencia': (result.data['presentes'] / result.data['processados'] * 100).round(),
          });
        }
      }

    } catch (e) {
      debugPrint('❌ Erro ao processar chamada: $e');
      setState(() {
        _salvandoChamada = false;
        _mostrarProgresso = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar chamada: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _salvandoChamada = false;
          _mostrarProgresso = false;
        });
      }
    }
  }

  // ============================================
  // TELA DE CONCLUSÃO DA CHAMADA
  // ============================================
  void _mostrarTelaConclusao(Map<String, dynamic> dados) {
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
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.green.shade700, Colors.green.shade500],
            ),
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
                    child: const Icon(Icons.celebration, size: 80, color: Colors.white),
                  );
                },
              ),
              const SizedBox(height: 20),
              const Text(
                '🎉 CHAMADA CONCLUÍDA!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                DateFormat("EEEE, dd/MM/yyyy", 'pt_BR').format(_dataChamada),
                style: const TextStyle(fontSize: 16, color: Colors.white70),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildResumoItem('${dados['presentes']}', 'Presentes', Icons.check_circle),
                    _buildResumoItem('${dados['ausentes']}', 'Ausentes', Icons.cancel),
                    _buildResumoItem('${dados['porcentagem_frequencia']}%', 'Frequência', Icons.trending_up),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Professor: $_professorNome',
                style: const TextStyle(fontSize: 14, color: Colors.white),
              ),
              const SizedBox(height: 10),
              Text(
                'Tipo de aula: $_tipoAulaHoje',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 25),
              TweenAnimationBuilder<Duration>(
                duration: const Duration(seconds: 5),
                tween: Tween(begin: const Duration(seconds: 5), end: Duration.zero),
                onEnd: () {
                  Navigator.pop(context);
                  if (mounted) Navigator.pop(context);
                },
                builder: (context, value, child) {
                  return Column(
                    children: [
                      LinearProgressIndicator(
                        value: value.inSeconds / 5,
                        backgroundColor: Colors.white.withOpacity(0.3),
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Fechando em ${value.inSeconds} segundos...',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
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
                child: const Text(
                  'FECHAR AGORA',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResumoItem(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ],
    );
  }

  // ============================================
  // GRADE DE ALUNOS
  // ============================================
  Widget _buildAlunoGridItem(Map<String, dynamic> aluno) {
    final alunoId = aluno['id'] as String;
    final nomeAluno = aluno['nome'] as String;
    final estaPresente = _presencas[alunoId] ?? false;
    final fotoUrl = aluno['foto'] as String?;

    return Card(
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: estaPresente ? Colors.green : Colors.transparent, width: estaPresente ? 2 : 0),
      ),
      child: InkWell(
        onTap: () => _togglePresenca(alunoId),
        child: Container(
          decoration: BoxDecoration(
            color: estaPresente ? Colors.green.shade50.withOpacity(0.3) : Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      color: Colors.grey[200],
                      child: fotoUrl != null && fotoUrl.isNotEmpty
                          ? CachedNetworkImage(
                        imageUrl: fotoUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorWidget: (c, u, e) => _placeholderIcon(size: 80),
                      )
                          : _placeholderIcon(size: 80),
                    ),
                    if (estaPresente)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                          child: const Icon(Icons.check, size: 14, color: Colors.white),
                        ),
                      ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => _adicionarObservacao(alunoId, nomeAluno),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2)),
                            ],
                          ),
                          child: const Icon(Icons.note_add, size: 16, color: Colors.blue),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nomeAluno.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        height: 1.2,
                        color: estaPresente ? Colors.green.shade800 : Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.center,
                      child: Transform.scale(
                        scale: 0.8,
                        child: Switch(
                          value: estaPresente,
                          activeColor: Colors.green,
                          inactiveTrackColor: Colors.grey.shade400,
                          onChanged: (_) => _togglePresenca(alunoId),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholderIcon({double size = 50}) {
    return Center(child: Icon(Icons.person, size: size, color: Colors.white));
  }

  // ============================================
  // HEADER DA CHAMADA
  // ============================================
  Widget _buildChamadaHeader() {
    final presentes = _presencas.values.where((v) => v).length;
    final total = _alunos.length;
    final porcentagem = total > 0 ? (presentes / total * 100).round() : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat("EEEE, dd 'de' MMMM", 'pt_BR').format(_dataChamada),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    if (_modoExtraForcado)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.red.shade900, borderRadius: BorderRadius.circular(4)),
                        child: const Text(
                          'MODO ADMIN: CHAMADA EXTRA',
                          style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getTipoAulaColor(_tipoAulaHoje).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _getTipoAulaColor(_tipoAulaHoje).withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_getTipoAulaIcon(_tipoAulaHoje), size: 12, color: _getTipoAulaColor(_tipoAulaHoje)),
                    const SizedBox(width: 6),
                    Text(
                      'TIPO DA AULA: $_tipoAulaHoje',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: _getTipoAulaColor(_tipoAulaHoje)),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    Icon(Icons.person, size: 12, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      _professorNome.split(' ').first,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStatItem(value: '$presentes', label: 'Presentes', color: Colors.green, icon: Icons.check_circle),
              const SizedBox(width: 12),
              _buildStatItem(value: '${total - presentes}', label: 'Ausentes', color: Colors.red, icon: Icons.cancel),
              const SizedBox(width: 12),
              _buildStatItem(value: '$porcentagem%', label: 'Frequência', color: Colors.blue, icon: Icons.trending_up),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            children: [
              LinearProgressIndicator(
                value: total > 0 ? presentes / total : 0,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  presentes == 0 ? Colors.red : presentes == total ? Colors.green : Colors.orange,
                ),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('$presentes de $total', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  Text(
                    _getStatusText(presentes, total),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _getStatusColor(presentes, total)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({required String value, required String label, required Color color, required IconData icon}) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }

  String _getStatusText(int presentes, int total) {
    if (presentes == 0) return 'NENHUM PRESENTE';
    if (presentes == total) return 'TODOS PRESENTES';
    return 'CHAMADA EM ANDAMENTO';
  }

  Color _getStatusColor(int presentes, int total) {
    if (presentes == 0) return Colors.red;
    if (presentes == total) return Colors.green;
    return Colors.orange;
  }

  Color _getTipoAulaColor(String tipoAula) {
    switch (tipoAula.toUpperCase()) {
      case 'OBJETIVA': return Colors.blue;
      case 'INSTRUMENTAÇÃO': return Colors.purple;
      case 'RODA': return Colors.orange;
      default: return Colors.grey;
    }
  }

  IconData _getTipoAulaIcon(String tipoAula) {
    switch (tipoAula.toUpperCase()) {
      case 'OBJETIVA': return Icons.flag;
      case 'INSTRUMENTAÇÃO': return Icons.music_note;
      case 'RODA': return Icons.group;
      default: return Icons.fitness_center;
    }
  }

  Widget _buildAlunosList() {
    if (_alunos.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 60, color: Colors.grey),
            SizedBox(height: 16),
            Text('Nenhum aluno nesta turma', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.75,
      ),
      itemCount: _alunos.length,
      itemBuilder: (context, index) => _buildAlunoGridItem(_alunos[index]),
    );
  }

  Widget _buildTelaProgresso() {
    return Center(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.red.shade900, Colors.red.shade700],
              ),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_upload, size: 60, color: Colors.white),
                const SizedBox(height: 20),
                const Text(
                  'PROCESSANDO CHAMADA',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _statusMensagem,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 30),
                const CircularProgressIndicator(color: Colors.white),
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
        appBar: AppBar(
          backgroundColor: Colors.red.shade900,
          foregroundColor: Colors.white,
          title: const Text('VERIFICANDO CHAMADA'),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('🔒 Verificando disponibilidade da chamada...', style: TextStyle(fontSize: 14, color: Colors.grey)),
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
        appBar: AppBar(
          backgroundColor: Colors.red.shade900,
          foregroundColor: Colors.white,
          title: const Text('Erro de Autenticação'),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 80, color: Colors.red.shade600),
                const SizedBox(height: 20),
                Text(
                  '❌ ERRO DE AUTENTICAÇÃO',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red.shade700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 15),
                const Text(
                  'Usuário não identificado. Faça login novamente para continuar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade900,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('VOLTAR'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('CHAMADA', style: TextStyle(fontSize: 16)),
            Text(widget.turmaNome, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          if (_isAdmin && !_salvandoChamada)
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: ElevatedButton.icon(
                onPressed: _abrirChamadaEspecial,
                icon: const Icon(Icons.calendar_month, size: 18),
                label: const Text('ESPECIAL', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red.shade900,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 2,
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Carregando dados...', style: TextStyle(color: Colors.grey))],
        ),
      )
          : _chamadaJaFeitaHoje
          ? SingleChildScrollView(child: Column(children: [const SizedBox(height: 20), _buildDetalhesChamadaExistente()]))
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
    final horaOcupacao = timestamp != null ? DateFormat('HH:mm').format(timestamp.toDate()) : 'agora';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        title: const Text('CHAMADA OCUPADA'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.orange.shade200, width: 3),
                ),
                child: const Icon(Icons.lock_outline, size: 80, color: Colors.orange),
              ),
              const SizedBox(height: 30),
              const Text('🔒 CHAMADA OCUPADA', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange)),
              const SizedBox(height: 16),
              Text(
                'A chamada desta turma já está sendo realizada por:',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.person, size: 50, color: Colors.orange),
                    const SizedBox(height: 10),
                    Text(ocupanteNome, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Text('Desde às $horaOcupacao', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                'Apenas um professor pode realizar a chamada por vez para evitar conflitos.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.arrow_back),
                label: const Text('VOLTAR PARA A TURMA', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTelaChamada() {
    return Column(
      children: [
        _buildChamadaHeader(),
        Expanded(child: _buildAlunosList()),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade300)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, -3))],
          ),
          child: ElevatedButton.icon(
            onPressed: _salvandoChamada ? null : _salvarChamada,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade900,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 55),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 3,
            ),
            icon: _salvandoChamada
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, size: 24),
            label: _salvandoChamada
                ? const Text('SALVANDO...')
                : const Text('✅ SALVAR CHAMADA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildTelaSemAula() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 20),
            Text(
              '📅 AULA NÃO MARCADA PARA HOJE',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 15),
            Text(_mensagemAulaHoje, style: TextStyle(fontSize: 14, color: Colors.grey.shade600), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
      return const Center(child: Text('Nenhuma informação de chamada disponível'));
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
    final porcentagem = _chamadaExistente!['porcentagem_frequencia'] ?? (total > 0 ? (presentes / total * 100).round() : 0);
    final tipoAula = _chamadaExistente!['tipo_aula'] ?? _tipoAulaHoje;
    final professorNome = _chamadaExistente!['professor_nome'] ?? _professorNome;
    final professorId = _chamadaExistente!['professor_id'] ?? _professorId;
    final List<dynamic> alunosChamada = _chamadaExistente!['alunos'] ?? [];
    final presentesList = alunosChamada.where((a) => a['presente'] == true).toList();
    final ausentesList = alunosChamada.where((a) => a['presente'] == false).toList();

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.green.shade700, Colors.green.shade500],
              ),
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(25), bottomRight: Radius.circular(25)),
            ),
            child: Column(
              children: [
                const Icon(Icons.celebration, size: 60, color: Colors.white),
                const SizedBox(height: 10),
                const Text(
                  '🎉 CHAMADA CONCLUÍDA!',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  DateFormat("EEEE, dd/MM/yyyy", 'pt_BR').format(dataChamada),
                  style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.9)),
                ),
                Text('Horário: $horaFormatada', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8))),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getTipoAulaColor(tipoAula).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_getTipoAulaIcon(tipoAula), size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Text('TIPO DA AULA: $tipoAula', style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                  child: Column(
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person, size: 16, color: Colors.white),
                          const SizedBox(width: 8),
                          Text('Professor: $professorNome', style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500)),
                        ],
                      ),
                      if (professorId.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'ID: ${professorId.substring(0, 6)}...',
                          style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.7), fontStyle: FontStyle.italic),
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
                _buildStatCardExistente(Icons.check_circle, 'Presentes', '$presentes', Colors.green, '$porcentagem%'),
                _buildStatCardExistente(Icons.cancel, 'Ausentes', '${total - presentes}', Colors.red, '${100 - porcentagem}%'),
                _buildStatCardExistente(Icons.people, 'Total', '$total', Colors.blue, '100%'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 12,
                        decoration: const BoxDecoration(color: Colors.green, borderRadius: BorderRadius.only(topLeft: Radius.circular(6), bottomLeft: Radius.circular(6))),
                      ),
                      flex: presentes,
                    ),
                    Expanded(
                      child: Container(
                        height: 12,
                        decoration: const BoxDecoration(color: Colors.red, borderRadius: BorderRadius.only(topRight: Radius.circular(6), bottomRight: Radius.circular(6))),
                      ),
                      flex: total - presentes,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$presentes presentes', style: TextStyle(fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.bold)),
                    Text('${total - presentes} ausentes', style: TextStyle(fontSize: 12, color: Colors.red.shade700, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 15),
                      child: Row(
                        children: [
                          Icon(Icons.list, color: Colors.grey.shade700),
                          const SizedBox(width: 10),
                          Text('LISTA DE ALUNOS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                          const Spacer(),
                          Chip(label: Text('$total alunos', style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Colors.blue.shade700),
                        ],
                      ),
                    ),
                    if (presentesList.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green.shade600, size: 18),
                              const SizedBox(width: 8),
                              Text('PRESENTES (${presentesList.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: presentesList.map((aluno) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.green.shade200, width: 1),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.person, size: 14, color: Colors.green.shade700),
                                    const SizedBox(width: 6),
                                    Text(_abreviarNome(aluno['aluno_nome']?.toString() ?? ''), style: TextStyle(fontSize: 12, color: Colors.green.shade800, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 15),
                        ],
                      ),
                    if (ausentesList.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(Icons.cancel, color: Colors.red.shade600, size: 18),
                              const SizedBox(width: 8),
                              Text('AUSENTES (${ausentesList.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: ausentesList.map((aluno) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.red.shade200, width: 1),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.person_outline, size: 14, color: Colors.red.shade700),
                                    const SizedBox(width: 6),
                                    Text(_abreviarNome(aluno['aluno_nome']?.toString() ?? ''), style: TextStyle(fontSize: 12, color: Colors.red.shade800, fontWeight: FontWeight.w500)),
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
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.note, color: Colors.orange.shade600),
                          const SizedBox(width: 10),
                          Text('OBSERVAÇÕES', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ...alunosChamada
                          .where((a) => (a['observacao'] as String?)?.isNotEmpty == true)
                          .map((aluno) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.arrow_right, size: 16, color: Colors.grey.shade600),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(aluno['aluno_nome']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
                                    Text(aluno['observacao']?.toString() ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade200)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.timer, color: Colors.blue.shade700, size: 18),
                      const SizedBox(width: 8),
                      TweenAnimationBuilder<Duration>(
                        duration: const Duration(seconds: 10),
                        tween: Tween(begin: const Duration(seconds: 10), end: Duration.zero),
                        onEnd: () {
                          if (mounted) Navigator.pop(context);
                        },
                        builder: (context, value, child) {
                          final seconds = value.inSeconds;
                          return Text('Fechando em $seconds segundos...', style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.w600));
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade900,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 3,
                    ),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('VOLTAR PARA A TURMA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCardExistente(IconData icon, String label, String value, Color color, String subValue) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.3), width: 2),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(subValue, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
      ],
    );
  }

  String _abreviarNome(String nomeCompleto) {
    final partes = nomeCompleto.split(' ');
    if (partes.length >= 2) {
      return '${partes[0][0]}. ${partes[partes.length - 1]}';
    }
    return nomeCompleto.length > 12 ? '${nomeCompleto.substring(0, 10)}...' : nomeCompleto;
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