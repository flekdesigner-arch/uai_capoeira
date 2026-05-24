// screens/alunos/avaliacao_alunos_turma_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AvaliacaoAlunosTurmaScreen extends StatefulWidget {
  final String turmaId;
  final String turmaNome;
  final String academiaId;
  final String academiaNome;

  const AvaliacaoAlunosTurmaScreen({
    super.key,
    required this.turmaId,
    required this.turmaNome,
    required this.academiaId,
    required this.academiaNome,
  });

  @override
  State<AvaliacaoAlunosTurmaScreen> createState() => _AvaliacaoAlunosTurmaScreenState();
}

class _AvaliacaoAlunosTurmaScreenState extends State<AvaliacaoAlunosTurmaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _buscaController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isCriandoCiclo = false;
  bool _isCarregandoPerfil = true;

  Map<String, dynamic> _usuarioLogadoDados = {};
  bool _isAdmin = false;
  bool _podeAvaliarAluno = false;

  bool get _podeGerenciarCiclos => _isAdmin;
  bool get _modoSomenteAvaliacao => !_isAdmin && _podeAvaliarAluno;

  String _busca = '';
  String _filtroStatus = 'Todos';

  List<Map<String, dynamic>> _alunos = [];
  List<Map<String, dynamic>> _ciclos = [];

  Map<String, dynamic>? _cicloAtual;
  Map<String, Map<String, dynamic>> _avaliacoesDoCiclo = {};

  final List<String> _filtrosStatus = const [
    'Todos',
    'Avaliados',
    'Pendentes',
    'Top notas',
    'Precisa melhorar',
  ];

  final List<_CriterioAvaliacao> _criterios = const [
    _CriterioAvaliacao(
      chave: 'comportamento_treino',
      titulo: 'Comportamento nos treinos',
      descricao: 'Postura, educação e controle durante as aulas.',
      icone: Icons.sentiment_satisfied_alt_rounded,
      categoria: 'Comportamento',
    ),
    _CriterioAvaliacao(
      chave: 'comportamento_casa',
      titulo: 'Comportamento em casa',
      descricao: 'Relato dos pais/responsáveis sobre comportamento fora do treino.',
      icone: Icons.home_rounded,
      categoria: 'Comportamento',
    ),
    _CriterioAvaliacao(
      chave: 'respeito',
      titulo: 'Respeito',
      descricao: 'Respeito ao professor, colegas, roda e ambiente.',
      icone: Icons.handshake_rounded,
      categoria: 'Comportamento',
    ),
    _CriterioAvaliacao(
      chave: 'disciplina',
      titulo: 'Disciplina',
      descricao: 'Cumpre combinados, presta atenção e aceita correções.',
      icone: Icons.military_tech_rounded,
      categoria: 'Comportamento',
    ),
    _CriterioAvaliacao(
      chave: 'participacao',
      titulo: 'Participação',
      descricao: 'Participa das atividades, jogos, roda e dinâmicas.',
      icone: Icons.groups_rounded,
      categoria: 'Participação',
    ),
    _CriterioAvaliacao(
      chave: 'atencao',
      titulo: 'Atenção',
      descricao: 'Foco durante explicações e execução dos movimentos.',
      icone: Icons.visibility_rounded,
      categoria: 'Participação',
    ),
    _CriterioAvaliacao(
      chave: 'pontualidade',
      titulo: 'Pontualidade/compromisso',
      descricao: 'Chega no horário, mantém constância e responsabilidade.',
      icone: Icons.schedule_rounded,
      categoria: 'Participação',
    ),
    _CriterioAvaliacao(
      chave: 'evolucao_tecnica',
      titulo: 'Evolução técnica',
      descricao: 'Melhora nos golpes, esquivas, quedas e sequências.',
      icone: Icons.trending_up_rounded,
      categoria: 'Capoeira',
    ),
    _CriterioAvaliacao(
      chave: 'ginga_movimento',
      titulo: 'Ginga e movimentação',
      descricao: 'Base, ritmo corporal, equilíbrio e deslocamento.',
      icone: Icons.sports_martial_arts_rounded,
      categoria: 'Capoeira',
    ),
    _CriterioAvaliacao(
      chave: 'ritmo_musicalidade',
      titulo: 'Ritmo e musicalidade',
      descricao: 'Noção de ritmo, palma, canto e energia da roda.',
      icone: Icons.music_note_rounded,
      categoria: 'Capoeira',
    ),
    _CriterioAvaliacao(
      chave: 'instrumentos_canto',
      titulo: 'Instrumentos e canto',
      descricao: 'Contato com berimbau, pandeiro, atabaque e cantos.',
      icone: Icons.graphic_eq_rounded,
      categoria: 'Capoeira',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _buscaController.addListener(() {
      if (!mounted) return;
      setState(() => _busca = _normalizar(_buscaController.text));
    });

    _carregarTudo();
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> get _ciclosRef => _firestore
      .collection('turmas')
      .doc(widget.turmaId)
      .collection('ciclos_avaliacao');

  CollectionReference<Map<String, dynamic>> get _resumoAvaliacoesRef => _firestore
      .collection('turmas')
      .doc(widget.turmaId)
      .collection('avaliacoes_alunos');

  bool _boolSeguro(dynamic value) {
    if (value == true) return true;
    if (value is String) {
      final normalizado = value.toLowerCase().trim();
      return normalizado == 'true' || normalizado == '1' || normalizado == 'sim';
    }
    if (value is num) return value == 1;
    return false;
  }

  bool _isAdminFromDados(Map<String, dynamic> dados) {
    final tipo = dados['tipo']?.toString().toLowerCase().trim() ?? '';
    final peso = _parseInt(dados['peso_permissao']);

    return peso >= 90 ||
        tipo == 'admin' ||
        tipo == 'administrador';
  }

  Future<void> _carregarPerfilEPermissoesUsuario() async {
    final user = _auth.currentUser;

    if (user == null) {
      _usuarioLogadoDados = {};
      _isAdmin = false;
      _podeAvaliarAluno = false;
      _isCarregandoPerfil = false;
      return;
    }

    try {
      final usuarioDoc = await _firestore
          .collection('usuarios')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));

      final dadosUsuario = usuarioDoc.data() ?? {};
      final isAdmin = _isAdminFromDados(dadosUsuario);

      bool podeAvaliar = isAdmin;

      if (!isAdmin) {
        final permissoesDoc = await _firestore
            .collection('usuarios')
            .doc(user.uid)
            .collection('permissoes_usuario')
            .doc('configuracoes')
            .get(const GetOptions(source: Source.server));

        final permissoes = permissoesDoc.data() ?? {};
        podeAvaliar = _boolSeguro(permissoes['pode_avaliar_aluno']);
      }

      _usuarioLogadoDados = dadosUsuario;
      _isAdmin = isAdmin;
      _podeAvaliarAluno = podeAvaliar;
      _isCarregandoPerfil = false;

      debugPrint(
        '⭐ Avaliação: usuário=${user.uid} admin=$_isAdmin podeAvaliar=$_podeAvaliarAluno modoSomenteAvaliacao=$_modoSomenteAvaliacao',
      );
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar perfil/permissões da avaliação: $e');
      _usuarioLogadoDados = {};
      _isAdmin = false;
      _podeAvaliarAluno = false;
      _isCarregandoPerfil = false;
    }
  }

  String _normalizar(String texto) {
    return texto
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c')
        .trim();
  }

  int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is String) return double.tryParse(value.replaceAll(',', '.')) ?? 0;
    return 0;
  }

  DateTime _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  String _mesNome(int mes) {
    const nomes = [
      '',
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];

    if (mes < 1 || mes > 12) return 'Mês';
    return nomes[mes];
  }

  String _cicloIdDoMes(DateTime data) {
    return '${data.year}-${data.month.toString().padLeft(2, '0')}';
  }

  String _nomeCiclo(DateTime data) {
    return 'Avaliação ${_mesNome(data.month)} ${data.year}';
  }

  String _formatarData(dynamic value) {
    DateTime? data;
    if (value is Timestamp) data = value.toDate();
    if (value is DateTime) data = value;
    if (value is String) data = DateTime.tryParse(value);

    if (data == null) return 'Nunca avaliado';

    return '${data.day.toString().padLeft(2, '0')}/'
        '${data.month.toString().padLeft(2, '0')}/'
        '${data.year}';
  }

  String _conceito(double nota) {
    if (nota >= 9) return 'Excelente';
    if (nota >= 8) return 'Muito bom';
    if (nota >= 7) return 'Bom';
    if (nota >= 6) return 'Regular';
    return 'Precisa melhorar';
  }

  Color _corNota(double nota) {
    if (nota >= 9) return Colors.green.shade800;
    if (nota >= 8) return Colors.lightGreen.shade700;
    if (nota >= 7) return Colors.blue.shade700;
    if (nota >= 6) return Colors.orange.shade800;
    return Colors.red.shade800;
  }

  double _calcularMedia(Map<String, double> notas) {
    if (notas.isEmpty) return 0;
    final soma = notas.values.fold<double>(0, (s, n) => s + n);
    return soma / notas.length;
  }

  void _mostrarSnack(String mensagem, Color cor) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: cor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _carregarTudo() async {
    setState(() {
      _isLoading = true;
      _isCarregandoPerfil = true;
    });

    try {
      await _carregarPerfilEPermissoesUsuario();

      if (!_podeAvaliarAluno && !_isAdmin) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _mostrarSnack('Você não tem permissão para acessar avaliações.', Colors.red);
        return;
      }

      // Admin pode criar automaticamente o ciclo do mês atual.
      // Professor/avaliador só entra no ciclo que já estiver aberto.
      if (_podeGerenciarCiclos) {
        await _garantirCicloMesAtual();
      }

      await Future.wait([
        _carregarAlunos(),
        _carregarCiclos(),
      ]);

      if (_cicloAtual == null) {
        await _definirCicloAtualPadrao();
      }

      await _carregarAvaliacoesDoCicloAtual();

      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _mostrarSnack('Erro ao carregar avaliações: $e', Colors.red);
    }
  }

  Future<void> _carregarAlunos() async {
    final alunosSnap = await _firestore
        .collection('alunos')
        .where('turma_id', isEqualTo: widget.turmaId)
        .get(const GetOptions(source: Source.server));

    final alunos = alunosSnap.docs.map((doc) {
      return {
        'id': doc.id,
        ...doc.data(),
      };
    }).toList();

    alunos.sort((a, b) {
      final nomeA = a['nome']?.toString() ?? '';
      final nomeB = b['nome']?.toString() ?? '';
      return nomeA.compareTo(nomeB);
    });

    _alunos = alunos;
  }

  Future<void> _carregarCiclos() async {
    final snap = await _ciclosRef
        .orderBy('ano', descending: true)
        .orderBy('mes', descending: true)
        .get(const GetOptions(source: Source.server));

    final ciclos = snap.docs.map((doc) {
      return {
        'id': doc.id,
        ...doc.data(),
      };
    }).toList();

    _ciclos = ciclos;

    if (_cicloAtual != null) {
      final idAtual = _cicloAtual!['id']?.toString();
      final atualizado = ciclos.where((c) => c['id'] == idAtual).toList();
      if (atualizado.isNotEmpty) {
        _cicloAtual = atualizado.first;
      }
    }
  }

  Future<void> _definirCicloAtualPadrao() async {
    if (_ciclos.isEmpty && _podeGerenciarCiclos) {
      await _garantirCicloMesAtual();
      await _carregarCiclos();
    }

    final idMesAtual = _cicloIdDoMes(DateTime.now());
    final cicloMesAtual = _ciclos.where((c) => c['id'] == idMesAtual).toList();

    if (_podeGerenciarCiclos) {
      if (cicloMesAtual.isNotEmpty) {
        _cicloAtual = cicloMesAtual.first;
      } else if (_ciclos.isNotEmpty) {
        _cicloAtual = _ciclos.first;
      }
      return;
    }

    // Professor/avaliador não escolhe ciclo e não cria ciclo.
    // Ele só avalia o ciclo aberto atual.
    final cicloAtualAberto = cicloMesAtual
        .where((c) => (c['status']?.toString() ?? 'aberto') == 'aberto')
        .toList();

    if (cicloAtualAberto.isNotEmpty) {
      _cicloAtual = cicloAtualAberto.first;
      return;
    }

    final ciclosAbertos = _ciclos
        .where((c) => (c['status']?.toString() ?? 'aberto') == 'aberto')
        .toList();

    if (ciclosAbertos.isNotEmpty) {
      _cicloAtual = ciclosAbertos.first;
    } else {
      _cicloAtual = null;
    }
  }

  Future<void> _garantirCicloMesAtual() async {
    final now = DateTime.now();
    final cicloId = _cicloIdDoMes(now);
    final docRef = _ciclosRef.doc(cicloId);
    final doc = await docRef.get(const GetOptions(source: Source.server));

    if (doc.exists) return;

    await docRef.set({
      'id': cicloId,
      'nome': _nomeCiclo(now),
      'mes': now.month,
      'ano': now.year,
      'status': 'aberto',
      'turma_id': widget.turmaId,
      'turma_nome': widget.turmaNome,
      'academia_id': widget.academiaId,
      'academia_nome': widget.academiaNome,
      'criado_em': FieldValue.serverTimestamp(),
      'atualizado_em': FieldValue.serverTimestamp(),
      'cache_versao': 1,
    });
  }

  Future<void> _carregarAvaliacoesDoCicloAtual() async {
    if (_cicloAtual == null) {
      _avaliacoesDoCiclo = {};
      return;
    }

    final cicloId = _cicloAtual!['id'].toString();

    final avaliacoesSnap = await _ciclosRef
        .doc(cicloId)
        .collection('avaliacoes')
        .get(const GetOptions(source: Source.server));

    final avaliacoes = <String, Map<String, dynamic>>{};
    for (final doc in avaliacoesSnap.docs) {
      avaliacoes[doc.id] = {
        'id': doc.id,
        ...doc.data(),
      };
    }

    _avaliacoesDoCiclo = avaliacoes;
  }

  Future<void> _trocarCiclo(Map<String, dynamic> ciclo) async {
    if (!_podeGerenciarCiclos) {
      _mostrarSnack('Apenas administradores podem trocar o ciclo.', Colors.orange);
      return;
    }

    setState(() {
      _cicloAtual = ciclo;
      _isLoading = true;
    });

    try {
      await _carregarAvaliacoesDoCicloAtual();
    } catch (e) {
      _mostrarSnack('Erro ao trocar ciclo: $e', Colors.red);
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _criarNovoCicloDialog() async {
    if (!_podeGerenciarCiclos) {
      _mostrarSnack('Apenas administradores podem criar ciclos.', Colors.orange);
      return;
    }

    final now = DateTime.now();
    int mesSelecionado = now.month;
    int anoSelecionado = now.year;

    final resultado = await showDialog<Map<String, int>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: const Text(
                'Novo ciclo de avaliação',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: mesSelecionado,
                    decoration: const InputDecoration(
                      labelText: 'Mês',
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(12, (index) {
                      final mes = index + 1;
                      return DropdownMenuItem<int>(
                        value: mes,
                        child: Text(_mesNome(mes)),
                      );
                    }),
                    onChanged: (value) {
                      if (value != null) {
                        setModalState(() => mesSelecionado = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: anoSelecionado,
                    decoration: const InputDecoration(
                      labelText: 'Ano',
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(5, (index) {
                      final ano = now.year - 1 + index;
                      return DropdownMenuItem<int>(
                        value: ano,
                        child: Text('$ano'),
                      );
                    }),
                    onChanged: (value) {
                      if (value != null) {
                        setModalState(() => anoSelecionado = value);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context, {
                      'mes': mesSelecionado,
                      'ano': anoSelecionado,
                    });
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Criar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (resultado == null) return;

    await _criarOuAbrirCiclo(resultado['mes']!, resultado['ano']!);
  }

  Future<void> _criarOuAbrirCiclo(int mes, int ano) async {
    if (!_podeGerenciarCiclos) {
      _mostrarSnack('Apenas administradores podem criar ou abrir ciclos.', Colors.orange);
      return;
    }

    if (_isCriandoCiclo) return;

    setState(() => _isCriandoCiclo = true);

    try {
      final data = DateTime(ano, mes);
      final cicloId = _cicloIdDoMes(data);
      final docRef = _ciclosRef.doc(cicloId);
      final doc = await docRef.get(const GetOptions(source: Source.server));

      if (!doc.exists) {
        await docRef.set({
          'id': cicloId,
          'nome': _nomeCiclo(data),
          'mes': mes,
          'ano': ano,
          'status': 'aberto',
          'turma_id': widget.turmaId,
          'turma_nome': widget.turmaNome,
          'academia_id': widget.academiaId,
          'academia_nome': widget.academiaNome,
          'criado_em': FieldValue.serverTimestamp(),
          'atualizado_em': FieldValue.serverTimestamp(),
          'cache_versao': 1,
        });

        _mostrarSnack('Ciclo criado com sucesso!', Colors.green);
      } else {
        _mostrarSnack('Ciclo já existia, abrindo avaliação.', Colors.blue);
      }

      await _carregarCiclos();
      final ciclo = _ciclos.firstWhere(
            (c) => c['id'] == cicloId,
        orElse: () => {'id': cicloId, 'nome': _nomeCiclo(data), 'mes': mes, 'ano': ano},
      );

      _cicloAtual = ciclo;
      await _carregarAvaliacoesDoCicloAtual();

      if (!mounted) return;
      setState(() {});
    } catch (e) {
      _mostrarSnack('Erro ao criar ciclo: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isCriandoCiclo = false);
    }
  }

  Future<void> _abrirSeletorCiclo() async {
    if (!_podeGerenciarCiclos) {
      _mostrarSnack('Professor avalia somente o ciclo aberto atual.', Colors.orange);
      return;
    }

    if (_ciclos.isEmpty) {
      _mostrarSnack('Nenhum ciclo encontrado.', Colors.orange);
      return;
    }

    final selecionado = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.deepPurple.shade50,
                      child: Icon(Icons.calendar_month_rounded, color: Colors.deepPurple.shade700),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Escolher ciclo',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _ciclos.length,
                    itemBuilder: (context, index) {
                      final ciclo = _ciclos[index];
                      final ativo = ciclo['id'] == _cicloAtual?['id'];

                      return ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        tileColor: ativo ? Colors.deepPurple.shade50 : null,
                        leading: Icon(
                          ativo ? Icons.check_circle_rounded : Icons.calendar_today_rounded,
                          color: ativo ? Colors.deepPurple.shade700 : Colors.grey.shade700,
                        ),
                        title: Text(
                          ciclo['nome']?.toString() ?? 'Ciclo',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('${ciclo['mes']}/${ciclo['ano']} • ${ciclo['status'] ?? 'aberto'}'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.pop(context, ciclo),
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

    if (selecionado != null) {
      await _trocarCiclo(selecionado);
    }
  }

  Future<void> _alternarStatusCiclo() async {
    if (!_podeGerenciarCiclos) {
      _mostrarSnack('Apenas administradores podem finalizar ou reabrir ciclos.', Colors.orange);
      return;
    }

    if (_cicloAtual == null) return;

    final cicloId = _cicloAtual!['id'].toString();
    final statusAtual = _cicloAtual!['status']?.toString() ?? 'aberto';
    final novoStatus = statusAtual == 'aberto' ? 'finalizado' : 'aberto';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(novoStatus == 'finalizado' ? 'Finalizar ciclo?' : 'Reabrir ciclo?'),
        content: Text(
          novoStatus == 'finalizado'
              ? 'Depois de finalizado, o ciclo fica como histórico. Ainda será possível reabrir depois.'
              : 'O ciclo será reaberto para novas edições.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar')),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await _ciclosRef.doc(cicloId).set({
        'status': novoStatus,
        'atualizado_em': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _carregarCiclos();
      await _definirCicloAtualPorId(cicloId);

      if (!mounted) return;
      setState(() {});

      _mostrarSnack(
        novoStatus == 'finalizado' ? 'Ciclo finalizado.' : 'Ciclo reaberto.',
        novoStatus == 'finalizado' ? Colors.orange : Colors.green,
      );
    } catch (e) {
      _mostrarSnack('Erro ao alterar status do ciclo: $e', Colors.red);
    }
  }

  Future<void> _definirCicloAtualPorId(String cicloId) async {
    final encontrados = _ciclos.where((c) => c['id'] == cicloId).toList();
    if (encontrados.isNotEmpty) {
      _cicloAtual = encontrados.first;
    }
  }

  List<Map<String, dynamic>> get _alunosFiltrados {
    Iterable<Map<String, dynamic>> lista = _alunos;

    if (_busca.isNotEmpty) {
      lista = lista.where((aluno) {
        final nome = _normalizar(aluno['nome']?.toString() ?? '');
        final apelido = _normalizar(aluno['apelido']?.toString() ?? '');
        final graduacao = _normalizar(aluno['graduacao_atual']?.toString() ?? '');
        return nome.contains(_busca) || apelido.contains(_busca) || graduacao.contains(_busca);
      });
    }

    if (_filtroStatus == 'Avaliados') {
      lista = lista.where((a) => _avaliacoesDoCiclo.containsKey(a['id']?.toString()));
    } else if (_filtroStatus == 'Pendentes') {
      lista = lista.where((a) => !_avaliacoesDoCiclo.containsKey(a['id']?.toString()));
    } else if (_filtroStatus == 'Precisa melhorar') {
      lista = lista.where((a) {
        final av = _avaliacoesDoCiclo[a['id']?.toString()];
        return av != null && _parseDouble(av['nota_final']) < 6;
      });
    }

    final resultado = lista.toList();

    if (_filtroStatus == 'Top notas') {
      resultado.sort((a, b) {
        final notaA = _parseDouble(_avaliacoesDoCiclo[a['id']?.toString()]?['nota_final']);
        final notaB = _parseDouble(_avaliacoesDoCiclo[b['id']?.toString()]?['nota_final']);
        return notaB.compareTo(notaA);
      });
    }

    return resultado;
  }

  bool get _cicloFinalizado {
    return _cicloAtual?['status']?.toString() == 'finalizado';
  }

  Future<void> _abrirDialogAvaliacao(Map<String, dynamic> aluno) async {
    if (!_podeAvaliarAluno && !_isAdmin) {
      _mostrarSnack('Você não tem permissão para avaliar alunos.', Colors.red);
      return;
    }

    if (_cicloAtual == null) {
      _mostrarSnack(
        _podeGerenciarCiclos
            ? 'Crie ou selecione um ciclo primeiro.'
            : 'Nenhum ciclo aberto disponível para avaliação.',
        Colors.orange,
      );
      return;
    }

    if (_cicloFinalizado) {
      _mostrarSnack(
        _podeGerenciarCiclos
            ? 'Este ciclo está finalizado. Reabra para editar.'
            : 'Este ciclo foi finalizado pelo administrador.',
        Colors.orange,
      );
      return;
    }

    final alunoId = aluno['id'].toString();
    final avaliacaoAtual = _avaliacoesDoCiclo[alunoId];

    final resultado = await showModalBottomSheet<_ResultadoAvaliacao>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AvaliacaoAlunoSheet(
        aluno: aluno,
        avaliacaoAtual: avaliacaoAtual,
        criterios: _criterios,
        cicloNome: _cicloAtual?['nome']?.toString() ?? 'Ciclo',
      ),
    );

    if (resultado == null) return;

    await _salvarAvaliacao(aluno, resultado);
  }

  Future<void> _salvarAvaliacao(
      Map<String, dynamic> aluno,
      _ResultadoAvaliacao resultado,
      ) async {
    if (_isSaving || _cicloAtual == null) return;

    setState(() => _isSaving = true);

    try {
      final user = _auth.currentUser;
      final alunoId = aluno['id'].toString();
      final cicloId = _cicloAtual!['id'].toString();
      final agora = Timestamp.now();

      final avaliacaoRef = _ciclosRef.doc(cicloId).collection('avaliacoes').doc(alunoId);
      final resumoRef = _resumoAvaliacoesRef.doc(alunoId);

      final data = {
        'aluno_id': alunoId,
        'aluno_nome': aluno['nome'] ?? '',
        'aluno_apelido': aluno['apelido'] ?? '',
        'aluno_foto': aluno['foto_perfil_aluno'] ?? '',
        'graduacao_atual': aluno['graduacao_atual'] ?? '',
        'turma_id': widget.turmaId,
        'turma_nome': widget.turmaNome,
        'academia_id': widget.academiaId,
        'academia_nome': widget.academiaNome,
        'ciclo_id': cicloId,
        'ciclo_nome': _cicloAtual!['nome'] ?? cicloId,
        'ciclo_mes': _parseInt(_cicloAtual!['mes']),
        'ciclo_ano': _parseInt(_cicloAtual!['ano']),
        'notas': resultado.notas,
        'nota_final': resultado.notaFinal,
        'conceito': _conceito(resultado.notaFinal),
        'observacao_professor': resultado.observacaoProfessor,
        'pontos_fortes': resultado.pontosFortes,
        'pontos_melhorar': resultado.pontosMelhorar,
        'avaliado': true,
        'avaliado_por_id': user?.uid,
        'avaliado_por_nome': _usuarioLogadoDados['nome_completo'] ??
            user?.displayName ??
            user?.email ??
            'Usuário',
        'avaliado_por_tipo': _usuarioLogadoDados['tipo'] ?? '',
        'atualizado_em': agora,
        'cache_versao': 2,
      };

      final existe = await avaliacaoRef.get();

      final batch = _firestore.batch();

      batch.set(avaliacaoRef, {
        ...data,
        if (!existe.exists) 'criado_em': agora,
      }, SetOptions(merge: true));

      batch.set(resumoRef, {
        'aluno_id': alunoId,
        'aluno_nome': aluno['nome'] ?? '',
        'aluno_foto': aluno['foto_perfil_aluno'] ?? '',
        'turma_id': widget.turmaId,
        'turma_nome': widget.turmaNome,
        'academia_id': widget.academiaId,
        'ultima_nota_final': resultado.notaFinal,
        'ultimo_conceito': _conceito(resultado.notaFinal),
        'ultimo_ciclo_id': cicloId,
        'ultimo_ciclo_nome': _cicloAtual!['nome'] ?? cicloId,
        'ultimo_ciclo_mes': _parseInt(_cicloAtual!['mes']),
        'ultimo_ciclo_ano': _parseInt(_cicloAtual!['ano']),
        'notas': resultado.notas,
        'nota_final': resultado.notaFinal,
        'conceito': _conceito(resultado.notaFinal),
        'atualizado_em': agora,
        'cache_versao': 2,
      }, SetOptions(merge: true));

      final historicoRef = avaliacaoRef.collection('historico').doc();
      batch.set(historicoRef, {
        ...data,
        'criado_em': agora,
        'tipo': existe.exists ? 'atualizacao' : 'primeira_avaliacao',
      });

      batch.set(_ciclosRef.doc(cicloId), {
        'total_avaliacoes': FieldValue.increment(existe.exists ? 0 : 1),
        'atualizado_em': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();

      if (!mounted) return;

      setState(() {
        _avaliacoesDoCiclo[alunoId] = {
          'id': alunoId,
          ...data,
          if (!existe.exists) 'criado_em': agora,
        };
        _isSaving = false;
      });

      _mostrarSnack('Avaliação salva no ciclo ${_cicloAtual!['nome']}.', Colors.green);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _mostrarSnack('Erro ao salvar avaliação: $e', Colors.red);
    }
  }

  Widget _buildBusca() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _buscaController,
        decoration: InputDecoration(
          hintText: 'Buscar aluno, apelido ou graduação...',
          prefixIcon: Icon(Icons.search_rounded, color: Colors.deepPurple.shade700),
          suffixIcon: _buscaController.text.isNotEmpty
              ? IconButton(
            onPressed: () => _buscaController.clear(),
            icon: const Icon(Icons.close_rounded),
          )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.deepPurple.shade700, width: 1.4),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final avaliados = _avaliacoesDoCiclo.length;
    final pendentes = (_alunos.length - avaliados).clamp(0, _alunos.length);
    double media = 0;

    if (_avaliacoesDoCiclo.isNotEmpty) {
      media = _avaliacoesDoCiclo.values
          .map((a) => _parseDouble(a['nota_final']))
          .fold<double>(0, (s, n) => s + n) /
          _avaliacoesDoCiclo.length;
    }

    final cicloNome = _cicloAtual?['nome']?.toString() ?? 'Nenhum ciclo';
    final status = _cicloAtual?['status']?.toString() ?? 'aberto';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.deepPurple.shade800,
            Colors.deepPurple.shade600,
            Colors.red.shade700,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.shade800.withOpacity(0.22),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.star_rate_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Avaliação do Aluno',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.turmaNome,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.82),
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (_isCriandoCiclo)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: _podeGerenciarCiclos ? _abrirSeletorCiclo : null,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.13),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.13)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      cicloNome,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: status == 'aberto'
                          ? Colors.green.withOpacity(0.20)
                          : Colors.orange.withOpacity(0.24),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more_rounded, color: Colors.white, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _headerMetric('${_alunos.length}', 'Alunos', Icons.groups_rounded)),
              const SizedBox(width: 8),
              Expanded(child: _headerMetric('$avaliados', 'Avaliados', Icons.check_circle_rounded)),
              const SizedBox(width: 8),
              Expanded(child: _headerMetric('$pendentes', 'Pendentes', Icons.pending_actions_rounded)),
              const SizedBox(width: 8),
              Expanded(child: _headerMetric(media.toStringAsFixed(1), 'Média', Icons.insights_rounded)),
            ],
          ),
          const SizedBox(height: 12),
          if (_podeGerenciarCiclos)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _abrirSeletorCiclo,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text('Trocar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withOpacity(0.45)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _criarNovoCicloDialog,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Novo ciclo'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withOpacity(0.45)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: status == 'aberto' ? 'Finalizar ciclo' : 'Reabrir ciclo',
                  onPressed: _alternarStatusCiclo,
                  icon: Icon(
                    status == 'aberto' ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
                    color: Colors.white,
                  ),
                ),
              ],
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.13),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_person_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Modo professor: permitido apenas avaliar o ciclo aberto',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.88),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
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

  Widget _headerMetric(String valor, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.13),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(height: 4),
          Text(
            valor,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.78),
              fontSize: 9,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFiltrosStatus() {
    return SizedBox(
      height: 42,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filtrosStatus.length,
        itemBuilder: (context, index) {
          final filtro = _filtrosStatus[index];
          final ativo = filtro == _filtroStatus;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                filtro,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: ativo ? Colors.white : Colors.grey.shade700,
                ),
              ),
              selected: ativo,
              selectedColor: Colors.deepPurple.shade700,
              backgroundColor: Colors.white,
              onSelected: (_) {
                setState(() => _filtroStatus = filtro);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildAlunoCard(Map<String, dynamic> aluno) {
    final alunoId = aluno['id'].toString();
    final avaliacao = _avaliacoesDoCiclo[alunoId];
    final nota = _parseDouble(avaliacao?['nota_final']);
    final temAvaliacao = avaliacao != null;
    final nome = aluno['nome']?.toString() ?? 'Sem nome';
    final apelido = aluno['apelido']?.toString() ?? '';
    final graduacao = aluno['graduacao_atual']?.toString() ?? 'Sem graduação';
    final foto = aluno['foto_perfil_aluno']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: temAvaliacao ? _corNota(nota).withOpacity(0.26) : Colors.grey.shade200,
          width: temAvaliacao ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _abrirDialogAvaliacao(aluno),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              _avatar(foto, nome),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      apelido.isNotEmpty ? '$nome ($apelido)' : nome,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      graduacao,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        _miniChip(
                          temAvaliacao ? _conceito(nota) : 'Pendente',
                          temAvaliacao ? _corNota(nota) : Colors.orange.shade800,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            _formatarData(avaliacao?['atualizado_em']),
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 10.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  Container(
                    width: 48,
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: temAvaliacao ? _corNota(nota).withOpacity(0.10) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Text(
                          temAvaliacao ? nota.toStringAsFixed(1) : '-',
                          style: TextStyle(
                            color: temAvaliacao ? _corNota(nota) : Colors.grey.shade600,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          'nota',
                          style: TextStyle(
                            color: temAvaliacao ? _corNota(nota) : Colors.grey.shade600,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Icon(
                    _cicloFinalizado ? Icons.lock_outline_rounded : Icons.edit_note_rounded,
                    color: _cicloFinalizado ? Colors.grey : Colors.deepPurple.shade600,
                    size: 22,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar(String foto, String nome) {
    final letra = nome.trim().isNotEmpty ? nome.trim()[0].toUpperCase() : '?';

    if (foto.startsWith('http')) {
      return ClipOval(
        child: Image.network(
          foto,
          width: 54,
          height: 54,
          fit: BoxFit.cover,
          cacheWidth: 140,
          errorBuilder: (_, __, ___) => _avatarFallback(letra),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return _avatarFallback(letra);
          },
        ),
      );
    }

    return _avatarFallback(letra);
  }

  Widget _avatarFallback(String letra) {
    return CircleAvatar(
      radius: 27,
      backgroundColor: Colors.deepPurple.shade50,
      child: Text(
        letra,
        style: TextStyle(
          color: Colors.deepPurple.shade700,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );
  }

  Widget _miniChip(String texto, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withOpacity(0.18)),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: cor,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search_rounded, size: 72, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              _busca.isEmpty ? 'Nenhum aluno encontrado nessa turma' : 'Nenhum aluno encontrado na busca',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _busca.isEmpty
                  ? 'Quando houver alunos nessa turma, eles aparecerão aqui.'
                  : 'Tente buscar por outro nome, apelido ou graduação.',
              style: TextStyle(color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final alunos = _alunosFiltrados;

    if (!_isLoading && !_podeAvaliarAluno && !_isAdmin) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: const Text(
            'Avaliação do Aluno',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: Colors.deepPurple.shade700,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_person_rounded, size: 76, color: Colors.red.shade700),
                const SizedBox(height: 16),
                const Text(
                  'Acesso negado',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Seu usuário não tem permissão para acessar a avaliação dos alunos.',
                  style: TextStyle(color: Colors.grey.shade600, height: 1.35),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Avaliação do Aluno',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.deepPurple.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _isLoading || _isSaving ? null : _carregarTudo,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _isLoading || _isCarregandoPerfil
          ? Center(child: CircularProgressIndicator(color: Colors.deepPurple.shade700))
          : Column(
        children: [
          _buildHeader(),
          _buildBusca(),
          _buildFiltrosStatus(),
          if (_isSaving)
            LinearProgressIndicator(
              color: Colors.deepPurple.shade700,
              backgroundColor: Colors.deepPurple.shade50,
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _carregarTudo,
              color: Colors.deepPurple.shade700,
              child: alunos.isEmpty
                  ? ListView(
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.18),
                  _buildEmpty(),
                ],
              )
                  : ListView.builder(
                padding: const EdgeInsets.only(bottom: 18, top: 8),
                itemCount: alunos.length,
                itemBuilder: (context, index) => _buildAlunoCard(alunos[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvaliacaoAlunoSheet extends StatefulWidget {
  final Map<String, dynamic> aluno;
  final Map<String, dynamic>? avaliacaoAtual;
  final List<_CriterioAvaliacao> criterios;
  final String cicloNome;

  const _AvaliacaoAlunoSheet({
    required this.aluno,
    required this.avaliacaoAtual,
    required this.criterios,
    required this.cicloNome,
  });

  @override
  State<_AvaliacaoAlunoSheet> createState() => _AvaliacaoAlunoSheetState();
}

class _AvaliacaoAlunoSheetState extends State<_AvaliacaoAlunoSheet> {
  late final Map<String, double> _notas;
  late final TextEditingController _observacaoController;
  late final TextEditingController _pontosFortesController;
  late final TextEditingController _pontosMelhorarController;

  @override
  void initState() {
    super.initState();

    final notasAtuais = widget.avaliacaoAtual?['notas'];
    _notas = {};

    for (final criterio in widget.criterios) {
      double nota = 7;
      if (notasAtuais is Map && notasAtuais[criterio.chave] != null) {
        final value = notasAtuais[criterio.chave];
        if (value is int) nota = value.toDouble();
        if (value is double) nota = value;
        if (value is String) nota = double.tryParse(value.replaceAll(',', '.')) ?? 7;
      }
      _notas[criterio.chave] = nota.clamp(0, 10);
    }

    _observacaoController = TextEditingController(
      text: widget.avaliacaoAtual?['observacao_professor']?.toString() ?? '',
    );
    _pontosFortesController = TextEditingController(
      text: widget.avaliacaoAtual?['pontos_fortes']?.toString() ?? '',
    );
    _pontosMelhorarController = TextEditingController(
      text: widget.avaliacaoAtual?['pontos_melhorar']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _observacaoController.dispose();
    _pontosFortesController.dispose();
    _pontosMelhorarController.dispose();
    super.dispose();
  }

  double get _media {
    if (_notas.isEmpty) return 0;
    return _notas.values.fold<double>(0, (s, n) => s + n) / _notas.length;
  }

  Color _corNota(double nota) {
    if (nota >= 9) return Colors.green.shade800;
    if (nota >= 8) return Colors.lightGreen.shade700;
    if (nota >= 7) return Colors.blue.shade700;
    if (nota >= 6) return Colors.orange.shade800;
    return Colors.red.shade800;
  }

  String _conceito(double nota) {
    if (nota >= 9) return 'Excelente';
    if (nota >= 8) return 'Muito bom';
    if (nota >= 7) return 'Bom';
    if (nota >= 6) return 'Regular';
    return 'Precisa melhorar';
  }

  Map<String, List<_CriterioAvaliacao>> get _criteriosPorCategoria {
    final map = <String, List<_CriterioAvaliacao>>{};
    for (final criterio in widget.criterios) {
      map.putIfAbsent(criterio.categoria, () => []);
      map[criterio.categoria]!.add(criterio);
    }
    return map;
  }

  void _salvar() {
    Navigator.pop(
      context,
      _ResultadoAvaliacao(
        notas: Map<String, double>.from(_notas),
        notaFinal: _media,
        observacaoProfessor: _observacaoController.text.trim(),
        pontosFortes: _pontosFortesController.text.trim(),
        pontosMelhorar: _pontosMelhorarController.text.trim(),
      ),
    );
  }

  Widget _buildCampoTexto({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: Colors.deepPurple.shade600),
          filled: true,
          fillColor: Colors.grey.shade50,
          alignLabelWithHint: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.deepPurple.shade600, width: 1.4),
          ),
        ),
      ),
    );
  }

  Widget _buildCriterio(_CriterioAvaliacao criterio) {
    final nota = _notas[criterio.chave] ?? 0;
    final cor = _corNota(nota);

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: cor.withOpacity(0.18)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(criterio.icone, color: cor, size: 22),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      criterio.titulo,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    Text(
                      criterio.descricao,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 10.5),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                width: 43,
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  color: cor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  nota.toStringAsFixed(1),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cor, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          Slider(
            value: nota,
            min: 0,
            max: 10,
            divisions: 20,
            activeColor: cor,
            label: nota.toStringAsFixed(1),
            onChanged: (value) {
              setState(() => _notas[criterio.chave] = value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoria(String categoria, List<_CriterioAvaliacao> criterios) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
          child: Text(
            categoria,
            style: TextStyle(
              color: Colors.deepPurple.shade700,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...criterios.map(_buildCriterio),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final nome = widget.aluno['nome']?.toString() ?? 'Aluno';
    final graduacao = widget.aluno['graduacao_atual']?.toString() ?? 'Sem graduação';
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        margin: const EdgeInsets.all(10),
        padding: EdgeInsets.only(bottom: bottom),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade700,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white.withOpacity(0.16),
                    child: const Icon(Icons.star_rate_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Avaliar aluno',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                        ),
                        Text(
                          '$nome • ${widget.cicloNome}',
                          style: TextStyle(color: Colors.white.withOpacity(0.82), fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.deepPurple.shade700, _corNota(_media)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                graduacao,
                                style: TextStyle(color: Colors.white.withOpacity(0.82), fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                _conceito(_media),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              Text(
                                _media.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 25,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'nota final',
                                style: TextStyle(color: Colors.white.withOpacity(0.78), fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._criteriosPorCategoria.entries.map((e) => _buildCategoria(e.key, e.value)),
                  const SizedBox(height: 8),
                  _buildCampoTexto(
                    controller: _pontosFortesController,
                    label: 'Pontos fortes',
                    icon: Icons.thumb_up_alt_rounded,
                    hint: 'Ex: respeitoso, dedicado, bom ritmo...',
                  ),
                  _buildCampoTexto(
                    controller: _pontosMelhorarController,
                    label: 'Pontos para melhorar',
                    icon: Icons.build_circle_rounded,
                    hint: 'Ex: atenção, pontualidade, disciplina...',
                  ),
                  _buildCampoTexto(
                    controller: _observacaoController,
                    label: 'Observação do professor',
                    icon: Icons.notes_rounded,
                    hint: 'Observações gerais sobre o aluno...',
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _salvar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  icon: const Icon(Icons.save_rounded),
                  label: const Text(
                    'SALVAR AVALIAÇÃO',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultadoAvaliacao {
  final Map<String, double> notas;
  final double notaFinal;
  final String observacaoProfessor;
  final String pontosFortes;
  final String pontosMelhorar;

  const _ResultadoAvaliacao({
    required this.notas,
    required this.notaFinal,
    required this.observacaoProfessor,
    required this.pontosFortes,
    required this.pontosMelhorar,
  });
}

class _CriterioAvaliacao {
  final String chave;
  final String titulo;
  final String descricao;
  final IconData icone;
  final String categoria;

  const _CriterioAvaliacao({
    required this.chave,
    required this.titulo,
    required this.descricao,
    required this.icone,
    required this.categoria,
  });
}
