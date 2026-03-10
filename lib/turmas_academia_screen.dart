import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uai_capoeira/screens/turmas/tela_turma_screen.dart';
import 'package:uai_capoeira/vincular_aluno_inativo_turma_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // 👈 NOVO

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
  final Connectivity _connectivity = Connectivity(); // 👈 NOVO

  bool _isLoading = true;
  int _pesoUsuarioLogado = 1;
  Map<String, bool> _permissoes = {};
  List<Map<String, dynamic>> _turmas = [];
  bool _erroCarregamento = false;
  String? _mensagemErro;
  DateTime? _ultimaAtualizacao;
  bool _forcarAtualizacao = false;
  bool _mostrarInativos = false;

  // 👇 CACHE LOCAL DAS TURMAS
  List<Map<String, dynamic>> _turmasCache = [];
  DateTime? _ultimoCacheTurmas;
  static const Duration _cacheValidade = Duration(minutes: 30); // Aumentei para 30 minutos para melhor experiência offline

  @override
  void initState() {
    super.initState();
    _carregarDadosIniciais();
  }

  // 👇 VERIFICAR SE PODE USAR CACHE
  bool _podeUsarCache() {
    if (_turmasCache.isEmpty) return false;
    if (_ultimoCacheTurmas == null) return false;

    final tempoDecorrido = DateTime.now().difference(_ultimoCacheTurmas!);
    return tempoDecorrido <= _cacheValidade;
  }

  // 👇 VERIFICAR CONEXÃO COM INTERNET
  Future<bool> _temInternet() async {
    try {
      var connectivityResult = await _connectivity.checkConnectivity();
      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      debugPrint('Erro ao verificar internet: $e');
      return false;
    }
  }

  Future<void> _carregarDadosIniciais() async {
    setState(() {
      _isLoading = true;
      _erroCarregamento = false;
    });

    try {
      // Tenta carregar do cache primeiro
      await _carregarDadosUsuario(forcarAtualizacao: false);
      await _carregarTurmas(forcarAtualizacao: false);

      setState(() {
        _ultimaAtualizacao = DateTime.now();
        _forcarAtualizacao = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar dados iniciais: $e');

      // Se tem cache, usa cache mesmo com erro
      if (_turmasCache.isNotEmpty) {
        setState(() {
          _turmas = List.from(_turmasCache);
          _erroCarregamento = false;
          _isLoading = false;
        });
      } else {
        setState(() {
          _erroCarregamento = true;
          _mensagemErro = 'Falha ao carregar dados. Conecte-se à internet para carregar as turmas.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _carregarDadosUsuario({bool forcarAtualizacao = false}) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        // SEMPRE usa cache primeiro, a menos que force atualização
        DocumentSnapshot userDoc;
        try {
          userDoc = await _firestore
              .collection('usuarios')
              .doc(user.uid)
              .get(const GetOptions(source: Source.cache));

          if (userDoc.exists) {
            final userData = userDoc.data() as Map<String, dynamic>;
            setState(() {
              _pesoUsuarioLogado = userData['peso_permissao'] ?? 1;
            });
          }
        } catch (e) {
          // Se não tem cache, tenta servidor (quando online)
          if (forcarAtualizacao || await _temInternet()) {
            try {
              userDoc = await _firestore
                  .collection('usuarios')
                  .doc(user.uid)
                  .get(const GetOptions(source: Source.server));

              if (userDoc.exists) {
                final userData = userDoc.data() as Map<String, dynamic>;
                setState(() {
                  _pesoUsuarioLogado = userData['peso_permissao'] ?? 1;
                });
              }
            } catch (e) {
              debugPrint('Erro ao carregar usuário do servidor: $e');
            }
          }
        }

        // CARREGAR PERMISSÕES - SEMPRE usa cache primeiro
        try {
          final permissoesDoc = await _firestore
              .collection('usuarios')
              .doc(user.uid)
              .collection('permissoes_usuario')
              .doc('configuracoes')
              .get(const GetOptions(source: Source.cache));

          if (permissoesDoc.exists) {
            final data = permissoesDoc.data() as Map<String, dynamic>;
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
                'pode_visualizar_relatorios': data['pode_visualizar_relatorios'] ?? false,
              };
            });
            debugPrint('✅ Permissões carregadas do cache: $_permissoes');
          }
        } catch (e) {
          debugPrint('❌ Erro ao carregar permissões do cache: $e');

          // Se não tem cache, tenta servidor (quando online)
          if (forcarAtualizacao || await _temInternet()) {
            try {
              final permissoesDoc = await _firestore
                  .collection('usuarios')
                  .doc(user.uid)
                  .collection('permissoes_usuario')
                  .doc('configuracoes')
                  .get(const GetOptions(source: Source.server));

              if (permissoesDoc.exists) {
                final data = permissoesDoc.data() as Map<String, dynamic>;
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
                    'pode_visualizar_relatorios': data['pode_visualizar_relatorios'] ?? false,
                  };
                });
                debugPrint('✅ Permissões carregadas do servidor: $_permissoes');
              }
            } catch (e) {
              debugPrint('❌ Erro ao carregar permissões do servidor: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Erro geral ao carregar dados do usuário: $e');
    }
  }

  Future<void> _carregarTurmas({bool forcarAtualizacao = false}) async {
    try {
      // 👉 VERIFICAR SE PODE USAR CACHE
      if (!forcarAtualizacao && _podeUsarCache()) {
        debugPrint('📦 Usando cache das turmas (${_turmasCache.length} turmas)');
        setState(() {
          _turmas = List.from(_turmasCache);
          _erroCarregamento = false;
        });
        return;
      }

      debugPrint('🌐 Tentando carregar turmas...');

      // TENTA CACHE PRIMEIRO
      try {
        final turmasSnapshot = await _firestore
            .collection('turmas')
            .where('academia_id', isEqualTo: widget.academiaId)
            .where('status', isEqualTo: 'ATIVA')
            .orderBy('nome')
            .get(const GetOptions(source: Source.cache));

        if (turmasSnapshot.docs.isNotEmpty) {
          await _processarTurmas(turmasSnapshot.docs);
          return;
        }
      } catch (e) {
        debugPrint('Cache de turmas vazio ou erro: $e');
      }

      // Se não tem cache, tenta servidor (apenas se estiver online)
      if (await _temInternet()) {
        try {
          final turmasSnapshot = await _firestore
              .collection('turmas')
              .where('academia_id', isEqualTo: widget.academiaId)
              .where('status', isEqualTo: 'ATIVA')
              .orderBy('nome')
              .get(const GetOptions(source: Source.server));

          await _processarTurmas(turmasSnapshot.docs);
        } catch (e) {
          debugPrint('Erro ao carregar turmas do servidor: $e');
          throw Exception('Não foi possível carregar turmas do servidor');
        }
      } else {
        // Se está offline e não tem cache, mostra erro
        if (_turmasCache.isEmpty) {
          setState(() {
            _erroCarregamento = true;
            _mensagemErro = 'Você está offline e não há dados em cache. Conecte-se à internet para carregar as turmas.';
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar turmas: $e');

      // Se tem cache, usa cache mesmo com erro
      if (_turmasCache.isNotEmpty) {
        setState(() {
          _turmas = List.from(_turmasCache);
          _erroCarregamento = false;
        });
      } else {
        setState(() {
          _erroCarregamento = true;
          _mensagemErro = 'Erro ao carregar turmas. Conecte-se à internet para carregar.';
        });
      }
    }
  }

  Future<void> _processarTurmas(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final turmasAcessiveis = <Map<String, dynamic>>[];

    for (var doc in docs) {
      final data = doc.data();

      final pesoTurma = data['peso_do_usuario_para_acessar'] ?? 1;
      final podeAcessar = _pesoUsuarioLogado >= pesoTurma;

      if (!podeAcessar) continue;

      String horarioDisplay = '';
      if (data['horario_inicio'] != null && data['horario_fim'] != null) {
        horarioDisplay = '${data['horario_inicio']} - ${data['horario_fim']}';
      } else if (data['horario_display'] != null) {
        horarioDisplay = data['horario_display'];
      }

      String diasSemanaDisplay = '';
      if (data['dias_semana_display'] is List && (data['dias_semana_display'] as List).isNotEmpty) {
        diasSemanaDisplay = (data['dias_semana_display'] as List).join(', ');
      } else if (data['dias_semana'] is List && (data['dias_semana'] as List).isNotEmpty) {
        diasSemanaDisplay = (data['dias_semana'] as List).join(', ');
      }

      final turma = {
        'id': doc.id,
        'nome': data['nome'] ?? 'Sem nome',
        'nivel': data['nivel'] ?? '',
        'faixa_etaria': data['faixa_etaria'] ?? '',
        'alunos_ativos': data['alunos_ativos'] ?? 0,
        'capacidade_maxima': data['capacidade_maxima'] ?? 0,
        'dias_semana': diasSemanaDisplay,
        'horario': horarioDisplay,
        'duracao_aula': data['duracao_aula_minutos'] ?? 0,
        'professor_principal': data['professor_principal'] ?? '',
        'cor_turma': data['cor_turma'] ?? '#059669',
        'idade_minima': data['idade_minima'] ?? 0,
        'idade_maxima': data['idade_maxima'] ?? 0,
        'nucleo': data['nucleo'] ?? '',
        'status': data['status'] ?? '',
        'ultima_atualizacao': data['ultima_atualizacao'] ?? FieldValue.serverTimestamp(),
        'logo_url': data['logo_url'] ?? '',
      };

      turmasAcessiveis.add(turma);
    }

    turmasAcessiveis.sort((a, b) => a['nome'].compareTo(b['nome']));

    // 👉 ATUALIZAR CACHE
    setState(() {
      _turmas = turmasAcessiveis;
      _turmasCache = List.from(turmasAcessiveis);
      _ultimoCacheTurmas = DateTime.now();
      _erroCarregamento = false;
    });
  }

  Future<void> _recarregarDados({bool forcarServidor = true}) async {
    final temInternet = await _temInternet();

    if (!temInternet) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🌐 Sem conexão com internet. Mostrando dados em cache.'),
          backgroundColor: Colors.orange,
        ),
      );

      if (_turmasCache.isNotEmpty) {
        setState(() {
          _turmas = List.from(_turmasCache);
        });
      }
      return;
    }

    setState(() {
      _forcarAtualizacao = forcarServidor;
    });
    await _carregarDadosIniciais();
  }

  Future<void> _onRefresh() async {
    final temInternet = await _temInternet();

    if (!temInternet) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🌐 Sem conexão com internet. Não é possível atualizar.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 12),
            Text('Sincronizando com o servidor...'),
          ],
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.blue.shade800,
      ),
    );

    await _recarregarDados(forcarServidor: true);

    if (mounted && !_erroCarregamento) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Dados atualizados! ${_turmas.length} turma(s) carregada(s).',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _limparCache() async {
    final temInternet = await _temInternet();

    if (!temInternet) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🌐 Sem conexão com internet. Não é possível limpar cache.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      setState(() {
        _forcarAtualizacao = true;
        _ultimoCacheTurmas = null; // Força recarregar
        _turmasCache = []; // Limpa cache
      });

      await _recarregarDados(forcarServidor: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cache limpo e dados atualizados do servidor'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao limpar cache: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildLogoTurma(Map<String, dynamic> turma, {double size = 40}) {
    final corTurma = _getColorFromHex(turma['cor_turma']);

    if (turma['logo_url'] != null && turma['logo_url'].toString().isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: corTurma.withOpacity(0.3), width: 2),
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
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(corTurma),
                ),
              );
            },
          ),
        ),
      );
    }

    return _buildFallbackLogo(turma, size, corTurma);
  }

  Widget _buildFallbackLogo(Map<String, dynamic> turma, double size, Color corTurma) {
    final iniciais = turma['nome'].isNotEmpty
        ? turma['nome'].substring(0, 1).toUpperCase()
        : 'T';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: corTurma.withOpacity(0.1),
        border: Border.all(color: corTurma, width: 2),
      ),
      child: Center(
        child: Text(
          iniciais,
          style: TextStyle(
            color: corTurma,
            fontWeight: FontWeight.bold,
            fontSize: size * 0.4,
          ),
        ),
      ),
    );
  }

  Color _getColorFromHex(String hexColor) {
    try {
      return Color(int.parse(hexColor.replaceFirst('#', '0xFF')));
    } catch (e) {
      return const Color(0xFF059669);
    }
  }

  Widget _buildTurmaCard(Map<String, dynamic> turma) {
    final alunosAtivos = turma['alunos_ativos'] ?? 0;
    final capacidade = turma['capacidade_maxima'] ?? 0;
    final double porcentagem = capacidade > 0 ? (alunosAtivos / capacidade) * 100 : 0;
    final corTurma = _getColorFromHex(turma['cor_turma']);

    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          // ✅ FUNCIONA OFFLINE - usa cache
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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLogoTurma(turma, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                turma['nome'],
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: corTurma,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (turma['nivel'].isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  turma['nivel'],
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: corTurma.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            turma['faixa_etaria'],
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: corTurma,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (turma['dias_semana'].isNotEmpty)
                          Row(
                            children: [
                              Icon(Icons.calendar_today, size: 16, color: Colors.blue.shade700),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  turma['dias_semana'],
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        if (turma['dias_semana'].isNotEmpty && turma['horario'].isNotEmpty)
                          const SizedBox(height: 6),
                        if (turma['horario'].isNotEmpty)
                          Row(
                            children: [
                              Icon(Icons.access_time, size: 16, color: Colors.orange.shade700),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  turma['horario'],
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Vagas: $alunosAtivos/$capacidade',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${porcentagem.toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: porcentagem >= 90
                                    ? Colors.red
                                    : porcentagem >= 70
                                    ? Colors.orange
                                    : Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: capacidade > 0 ? alunosAtivos / capacidade : 0,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            porcentagem >= 90
                                ? Colors.red
                                : porcentagem >= 70
                                ? Colors.orange
                                : Colors.green,
                          ),
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
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

  // ✅ FUNÇÃO ESPECIAL PARA O BOTÃO INATIVOS (SÓ FUNCIONA ONLINE)
  Future<void> _abrirTelaVincularAluno() async {
    debugPrint('🔑 Verificando permissão: pode_ativar_alunos = ${_permissoes['pode_ativar_alunos']}');

    // 1️⃣ VERIFICAR PERMISSÃO
    if (_permissoes['pode_ativar_alunos'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Você não tem permissão para ativar alunos. Entre em contato com um administrador.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    // 2️⃣ VERIFICAR INTERNET (OBRIGATÓRIO PARA ESTE BOTÃO)
    final temInternet = await _temInternet();
    if (!temInternet) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🌐 Você precisa estar conectado à internet para ativar alunos inativos.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    // 3️⃣ VERIFICAR SE HÁ TURMAS
    if (_turmas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não há turmas disponíveis'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // ✅ TUDO OK - ABRIR TELA
    if (_turmas.length == 1) {
      Navigator.push(
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
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.shade900,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.group_add, color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Selecione uma Turma',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                constraints: const BoxConstraints(maxHeight: 400),
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(0),
                  itemCount: _turmas.length,
                  itemBuilder: (context, index) {
                    final turma = _turmas[index];
                    final corTurma = _getColorFromHex(turma['cor_turma']);

                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => VincularAlunoInativoTurmaScreen(
                                turmaId: turma['id'],
                                turmaNome: turma['nome'],
                                academiaId: widget.academiaId,
                                academiaNome: widget.academiaNome,
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              _buildLogoTurma(turma, size: 44),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      turma['nome'],
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: corTurma,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    if (turma['dias_semana'].isNotEmpty && turma['horario'].isNotEmpty)
                                      Text(
                                        '${turma['dias_semana']} • ${turma['horario']}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    else if (turma['dias_semana'].isNotEmpty)
                                      Text(
                                        turma['dias_semana'],
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${turma['alunos_ativos']}/${turma['capacidade_maxima']} alunos',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: Colors.grey.shade400,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'CANCELAR',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TURMAS DA ACADEMIA',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              widget.academiaNome,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ElevatedButton.icon(
              onPressed: _abrirTelaVincularAluno, // ✅ FUNÇÃO COM VALIDAÇÃO DE INTERNET
              icon: const Icon(Icons.person_add, size: 18),
              label: const Text('INATIVOS'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.red.shade900,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                elevation: 0,
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'refresh') {
                _recarregarDados(forcarServidor: true);
              } else if (value == 'clear_cache') {
                _limparCache();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 20, color: Colors.blue),
                    SizedBox(width: 12),
                    Text('Atualizar do servidor'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear_cache',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep, size: 20, color: Colors.red),
                    SizedBox(width: 12),
                    Text('Limpar cache e atualizar'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Carregando turmas...',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      )
          : _erroCarregamento && _turmas.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 60,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 20),
            Text(
              _mensagemErro ?? 'Erro ao carregar turmas',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _recarregarDados(forcarServidor: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar Novamente'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: _onRefresh,
        color: Colors.red.shade900,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey.shade50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'TURMAS DISPONÍVEIS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          if (_podeUsarCache())
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'CACHE',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade800,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_turmas.length} turma${_turmas.length != 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _forcarAtualizacao
                          ? Colors.blue.shade100
                          : Colors.green.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _forcarAtualizacao
                              ? Icons.cloud_download
                              : Icons.storage,
                          size: 14,
                          color: _forcarAtualizacao
                              ? Colors.blue.shade800
                              : Colors.green.shade800,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _forcarAtualizacao ? 'Servidor' : 'Cache',
                          style: TextStyle(
                            fontSize: 12,
                            color: _forcarAtualizacao
                                ? Colors.blue.shade800
                                : Colors.green.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_mostrarInativos)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Chip(
                  label: const Text('Mostrando alunos inativos'),
                  onDeleted: () {
                    setState(() {
                      _mostrarInativos = false;
                    });
                  },
                  deleteIcon: const Icon(Icons.close),
                  backgroundColor: Colors.orange.shade100,
                ),
              ),
            Expanded(
              child: _turmas.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.class_outlined,
                      size: 80,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Nenhuma turma disponível',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.academiaNome,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Nível de permissão: $_pesoUsuarioLogado',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () => _recarregarDados(forcarServidor: true),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Recarregar do servidor'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade900,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 20),
                itemCount: _turmas.length,
                itemBuilder: (context, index) {
                  return _buildTurmaCard(_turmas[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}