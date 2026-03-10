import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uai_capoeira/screens/alunos/alunos_turma_screen.dart';
import 'package:uai_capoeira/screens/alunos/dashboard_turmas_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

// ✅ TELAS IMPORTADAS
import 'package:uai_capoeira/chamada_turma_screen.dart';
import 'package:uai_capoeira/listas_chamada_screen.dart';

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

  bool _isLoading = false;
  bool _isLoadingPermissoes = true;
  Map<String, dynamic> _dadosTurma = {};
  Map<String, dynamic> _permissoes = {};
  Color _corTurma = Colors.red.shade900;

  // 🔥 CONTROLE DE CONEXÃO
  bool _temInternet = true;
  Stream<List<ConnectivityResult>>? _connectivityStream;

  @override
  void initState() {
    super.initState();
    _carregarDadosTurma();
    _inicializarPermissoesInteligente();
    _monitorarConexao();
  }

  @override
  void dispose() {
    _connectivityStream = null;
    super.dispose();
  }

  // 🔥 MONITORAR MUDANÇAS NA CONEXÃO
  void _monitorarConexao() {
    _connectivityStream = _connectivity.onConnectivityChanged;
    _connectivityStream!.listen((List<ConnectivityResult> results) {
      final tinhaInternet = _temInternet;
      _temInternet = !results.contains(ConnectivityResult.none);

      // Se voltou a ter internet, recarrega permissões
      if (!tinhaInternet && _temInternet) {
        debugPrint('🌐 Internet voltou! Recarregando permissões...');
        _recarregarPermissoes();
      } else if (tinhaInternet && !_temInternet) {
        // Só atualiza a UI quando perde internet
        if (mounted) setState(() {});
      }

      debugPrint('📱 Conexão mudou: ${_temInternet ? "ONLINE" : "OFFLINE"}');
    });
  }

  // 🔥 INICIALIZAR PERMISSÕES DE FORMA INTELIGENTE
  Future<void> _inicializarPermissoesInteligente() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() => _isLoadingPermissoes = false);
      return;
    }

    try {
      // 1️⃣ PRIMEIRO: TENTA CARREGAR DO CACHE
      try {
        final cacheDoc = await _firestore
            .collection('usuarios')
            .doc(user.uid)
            .collection('permissoes_usuario')
            .doc('configuracoes')
            .get(const GetOptions(source: Source.cache));

        if (cacheDoc.exists) {
          setState(() {
            _permissoes = cacheDoc.data() as Map<String, dynamic>;
            _isLoadingPermissoes = false;
          });
          debugPrint('✅ Permissões carregadas do CACHE');
        }
      } catch (e) {
        debugPrint('⚠️ Sem cache disponível: $e');
      }

      // 2️⃣ VERIFICA INTERNET E CONFIGURA STREAM
      _temInternet = await _verificarInternet();

      if (_temInternet) {
        debugPrint('🌐 Internet disponível - Ativando tempo real');
        _configurarStreamPermissoes(user.uid);
      } else {
        debugPrint('📴 Sem internet - Usando apenas cache');
        setState(() => _isLoadingPermissoes = false);
      }

    } catch (e) {
      debugPrint('❌ Erro ao inicializar permissões: $e');
      setState(() => _isLoadingPermissoes = false);
    }
  }

  // 🔥 CONFIGURAR STREAM EM TEMPO REAL
  void _configurarStreamPermissoes(String uid) {
    _firestore
        .collection('usuarios')
        .doc(uid)
        .collection('permissoes_usuario')
        .doc('configuracoes')
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        final novasPermissoes = snapshot.data() as Map<String, dynamic>;

        setState(() {
          _permissoes = novasPermissoes;
          _isLoadingPermissoes = false;
        });

        debugPrint('🔄 Permissões atualizadas');
      }
    }, onError: (error) {
      debugPrint('❌ Erro no stream de permissões: $error');
      setState(() => _isLoadingPermissoes = false);
    });
  }

  // 🔥 RECARREGAR PERMISSÕES (quando internet volta)
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

      if (doc.exists && mounted) {
        setState(() {
          _permissoes = doc.data() as Map<String, dynamic>;
        });
        debugPrint('🔄 Permissões recarregadas do servidor');
      }
    } catch (e) {
      debugPrint('❌ Erro ao recarregar permissões: $e');
    }
  }

  // 🔥 VERIFICAR INTERNET
  Future<bool> _verificarInternet() async {
    try {
      var result = await _connectivity.checkConnectivity();
      return !result.contains(ConnectivityResult.none);
    } catch (e) {
      debugPrint('Erro ao verificar internet: $e');
      return false;
    }
  }

  // 🔐 VERIFICAR PERMISSÃO
  bool _temPermissao(String permissao) {
    return _permissoes[permissao] == true;
  }

  // 🌐 VERIFICAR CONEXÃO PARA AÇÕES
  Future<bool> _temInternetParaAcao() async {
    if (!_temInternet) {
      _mostrarMensagem(
        '📴 Modo offline - Conecte-se à internet para esta ação',
        Colors.orange.shade800,
      );
      return false;
    }
    return true;
  }

  // ✅ VALIDAÇÃO PARA CHAMADA
  Future<void> _validarEAbrirChamada() async {
    if (!_temPermissao('pode_fazer_chamada')) {
      _mostrarMensagem(
        '⛔ Você não tem permissão para realizar chamadas.',
        Colors.red.shade800,
      );
      return;
    }

    if (!await _temInternetParaAcao()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _mostrarMensagem('❌ Erro: Usuário não logado', Colors.red.shade800);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChamadaTurmaScreen(
          turmaId: widget.turmaId,
          turmaNome: _dadosTurma['nome']?.toString() ?? widget.turmaNome,
          academiaId: widget.academiaId,
          academiaNome: widget.academiaNome,
          usuarioId: user.uid,
        ),
      ),
    );
  }

  // 📱 MENSAGEM PERSONALIZADA
  void _mostrarMensagem(String mensagem, Color cor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              mensagem.contains('permissão') ? Icons.lock :
              mensagem.contains('internet') ? Icons.wifi_off :
              Icons.error,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                mensagem,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: cor,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(10),
      ),
    );
  }

  Future<void> _carregarDadosTurma() async {
    setState(() => _isLoading = true);
    try {
      DocumentSnapshot turmaDoc;
      try {
        turmaDoc = await _firestore
            .collection('turmas')
            .doc(widget.turmaId)
            .get(const GetOptions(source: Source.cache));
      } catch (e) {
        turmaDoc = await _firestore
            .collection('turmas')
            .doc(widget.turmaId)
            .get(const GetOptions(source: Source.server));
      }

      if (turmaDoc.exists) {
        final data = turmaDoc.data() as Map<String, dynamic>;
        setState(() {
          _dadosTurma = data;
          try {
            _corTurma = Color(int.parse((data['cor_turma'] ?? '#EF4444').replaceFirst('#', '0xFF')));
          } catch (e) {
            _corTurma = Colors.red.shade900;
          }
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados da turma: $e');
      if (mounted) {
        _mostrarMensagem('Erro ao carregar dados: $e', Colors.red);
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ✅ BOTÃO QUE SÓ APARECE SE TIVER PERMISSÃO
  Widget _buildFunctionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    required String permissao,
  }) {
    final bool temPermissao = _temPermissao(permissao);

    // 🔥 NÃO MOSTRA O BOTÃO SE NÃO TIVER PERMISSÃO
    if (!temPermissao) {
      return const SizedBox.shrink(); // 🔥 CORRIGIDO: Retorna um widget vazio em vez de null
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 28, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),

                    // 🔥 MOSTRA ÍCONE DE OFFLINE APENAS QUANDO NÃO TEM INTERNET
                    if (!_temInternet)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(Icons.wifi_off, size: 12, color: Colors.orange.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'offline',
                              style: TextStyle(fontSize: 10, color: Colors.orange.shade700),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPermissoes) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: _corTurma,
          foregroundColor: Colors.white,
          title: const Text('CARREGANDO...'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                _temInternet ? '🔄 Carregando permissões...' : '📴 Modo offline',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    final String logoUrl = _dadosTurma['logo_url'] as String? ?? '';
    final List diasSemana = _dadosTurma['dias_semana_display'] is List
        ? (_dadosTurma['dias_semana_display'] as List)
        : [];
    final String diasSemanaTexto = diasSemana.isNotEmpty ? diasSemana.join(', ') : '';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _corTurma,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _dadosTurma['nome']?.toString().toUpperCase() ?? widget.turmaNome.toUpperCase(),
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              widget.academiaNome,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          // 🔥 MOSTRA ÍCONE DE WIFI APENAS QUANDO ESTÁ OFFLINE
          if (!_temInternet)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                Icons.wifi_off,
                size: 18,
                color: Colors.orange.shade200,
              ),
            ),
          IconButton(
            onPressed: _carregarDadosTurma,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // CARD DA TURMA
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _corTurma.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _corTurma.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (logoUrl.isNotEmpty)
                        Container(
                          width: 60,
                          height: 60,
                          margin: const EdgeInsets.only(right: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _corTurma.withOpacity(0.3)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: logoUrl,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey[200],
                                child: Icon(Icons.class_, size: 30, color: _corTurma),
                              ),
                              placeholder: (context, url) => Container(
                                color: Colors.grey[200],
                                child: const Center(
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _dadosTurma['nome']?.toString().toUpperCase() ?? 'TURMA',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _corTurma),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            if (diasSemanaTexto.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _corTurma.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  diasSemanaTexto,
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _corTurma),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    Icons.people_outline,
                    'ALUNOS ATIVOS',
                    '${_dadosTurma['alunos_ativos'] ?? 0} / ${_dadosTurma['capacidade_maxima'] ?? 0}',
                  ),
                  if (_dadosTurma['horario_display'] != null && _dadosTurma['horario_display'].toString().isNotEmpty)
                    _buildInfoRow(
                      Icons.access_time,
                      'HORÁRIO',
                      _dadosTurma['horario_display'].toString(),
                    ),
                  if (_dadosTurma['nivel'] != null && _dadosTurma['nivel'].toString().isNotEmpty)
                    _buildInfoRow(
                      Icons.star,
                      'NÍVEL',
                      _dadosTurma['nivel'].toString(),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // BOTÕES - SÓ APARECEM SE TIVER PERMISSÃO
            _buildFunctionCard(
              icon: Icons.person_search,
              title: 'VER ALUNOS',
              subtitle: 'Lista completa de alunos',
              color: Colors.purple.shade600,
              permissao: 'pode_visualizar_alunos',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AlunosTurmaScreen(
                      turmaId: widget.turmaId,
                      turmaNome: _dadosTurma['nome']?.toString() ?? widget.turmaNome,
                      academiaId: widget.academiaId,
                      academiaNome: widget.academiaNome,
                    ),
                  ),
                );
              },
            ),

            _buildFunctionCard(
              icon: Icons.people,
              title: 'FAZER CHAMADA',
              subtitle: 'Registrar presença dos alunos',
              color: Colors.green.shade600,
              permissao: 'pode_fazer_chamada',
              onTap: _validarEAbrirChamada,
            ),

            _buildFunctionCard(
              icon: Icons.list_alt,
              title: 'LISTAS DE CHAMADA',
              subtitle: 'Histórico de presenças',
              color: Colors.blue.shade600,
              permissao: 'pode_ver_lista_de_chamada',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ListasChamadaScreen(
                      turmaId: widget.turmaId,
                      turmaNome: _dadosTurma['nome']?.toString() ?? widget.turmaNome,
                      academiaId: widget.academiaId,
                      academiaNome: widget.academiaNome,
                    ),
                  ),
                );
              },
            ),

            _buildFunctionCard(
              icon: Icons.summarize,
              title: 'RESUMO DA TURMA',
              subtitle: 'Estatísticas e relatórios',
              color: Colors.orange.shade600,
              permissao: 'pode_visualizar_relatorios',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DashboardTurmasPage(
                      turmaId: widget.turmaId,
                      turmaNome: widget.turmaNome,
                      academiaId: widget.academiaId,
                    ),
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