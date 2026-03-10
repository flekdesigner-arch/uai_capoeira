import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart' as xml;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'cadastro_aluno_turma_screen.dart';
import 'aluno_detalhe_screen.dart';
import 'package:uai_capoeira/services/sync_service.dart';
import 'package:uai_capoeira/widgets/sync_indicator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

// ============================================
// 🔥 SERVIÇO DE CACHE INTELIGENTE (30 MINUTOS)
// ============================================
class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  final Map<String, CacheEntry> _memoryCache = {};
  final Duration cacheValidity = const Duration(minutes: 30); // ✅ 30 MINUTOS

  bool isCacheValid(String key) {
    final entry = _memoryCache[key];
    if (entry == null) return false;
    return DateTime.now().difference(entry.timestamp) < cacheValidity;
  }

  void saveToCache(String key, dynamic data) {
    _memoryCache[key] = CacheEntry(
      data: data,
      timestamp: DateTime.now(),
    );
  }

  dynamic loadFromCache(String key) {
    if (_memoryCache.containsKey(key) && isCacheValid(key)) {
      debugPrint('✅ Cache válido encontrado para $key');
      return _memoryCache[key]!.data;
    }
    return null;
  }

  void limparCacheExpirado() {
    final agora = DateTime.now();
    _memoryCache.removeWhere((key, entry) {
      return agora.difference(entry.timestamp) >= cacheValidity;
    });
  }
}

class CacheEntry {
  final dynamic data;
  final DateTime timestamp;

  CacheEntry({required this.data, required this.timestamp});
}

class AlunosTurmaScreen extends StatefulWidget {
  final String turmaId;
  final String turmaNome;
  final String academiaId;
  final String academiaNome;

  const AlunosTurmaScreen({
    super.key,
    required this.turmaId,
    required this.turmaNome,
    required this.academiaId,
    required this.academiaNome,
  });

  @override
  State<AlunosTurmaScreen> createState() => _AlunosTurmaScreenState();
}

class _AlunosTurmaScreenState extends State<AlunosTurmaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Connectivity _connectivity = Connectivity();
  final CacheService _cache = CacheService();
  final SyncService _syncService = SyncService();

  // ✅ CONTROLE DE CONECTIVIDADE EM TEMPO REAL
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  String? _svgContent;
  String _searchQuery = '';
  int _viewMode = 0;
  final List<IconData> _viewModeIcons = [
    Icons.view_list,
    Icons.grid_view,
    Icons.format_list_bulleted
  ];
  final List<String> _viewModeTooltips = [
    'Visualizar em Lista',
    'Visualizar em Grade',
    'Visualização Compacta'
  ];

  Map<String, bool> _permissoes = {};
  bool _carregandoPermissoes = true;

  // CACHES - AGORA POR NOME DA GRADUAÇÃO
  final Map<String, Map<String, dynamic>> _graduacoesCache = {}; // Key: nome_graduacao
  final Map<String, String> _svgCache = {}; // Key: nome_graduacao
  final Map<String, bool> _graduacaoValidaCache = {}; // Key: nome_graduacao

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _alunosCache = [];
  bool _isLoading = true;
  bool _hasError = false;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _alunosSubscription;

  @override
  void initState() {
    super.initState();
    _carregarPermissoes();
    _loadSvg();
    _preloadGraduacoes();
    _carregarAlunos();
    _monitorarConectividade();

    // Limpar cache expirado a cada minuto
    Timer.periodic(const Duration(minutes: 1), (timer) {
      _cache.limparCacheExpirado();
    });
  }

  @override
  void dispose() {
    _alunosSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _syncService.dispose();
    super.dispose();
  }

  // ✅ MONITORAR CONECTIVIDADE EM TEMPO REAL
  void _monitorarConectividade() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
          (List<ConnectivityResult> results) {
        if (!mounted) return;

        final isOnline = results.isNotEmpty && results.first != ConnectivityResult.none;

        setState(() {
          _isOnline = isOnline;
        });

        debugPrint('📡 Status de conexão: ${isOnline ? 'ONLINE' : 'OFFLINE'}');
      },
    );

    _verificarConectividadeInicial();
  }

  // ✅ VERIFICAR CONECTIVIDADE INICIAL
  Future<void> _verificarConectividadeInicial() async {
    try {
      var results = await _connectivity.checkConnectivity();
      if (mounted) {
        setState(() {
          _isOnline = results.isNotEmpty && results.first != ConnectivityResult.none;
        });
      }
    } catch (e) {
      debugPrint('Erro ao verificar conectividade inicial: $e');
      if (mounted) {
        setState(() {
          _isOnline = false;
        });
      }
    }
  }

  // 🔐 PERMISSÕES COM CACHE
  Future<void> _carregarPermissoes() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        DocumentSnapshot permissoesDoc;
        try {
          permissoesDoc = await _firestore
              .collection('usuarios')
              .doc(user.uid)
              .collection('permissoes_usuario')
              .doc('configuracoes')
              .get(const GetOptions(source: Source.cache));
        } catch (e) {
          permissoesDoc = await _firestore
              .collection('usuarios')
              .doc(user.uid)
              .collection('permissoes_usuario')
              .doc('configuracoes')
              .get(const GetOptions(source: Source.server));
        }

        if (permissoesDoc.exists) {
          final data = permissoesDoc.data() as Map<String, dynamic>;
          setState(() {
            _permissoes = {
              'pode_adicionar_aluno': data['pode_adicionar_aluno'] ?? false,
              'pode_ativar_alunos': data['pode_ativar_alunos'] ?? false,
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
            _carregandoPermissoes = false;
          });
        } else {
          setState(() {
            _permissoes = {};
            _carregandoPermissoes = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar permissões: $e');
      setState(() {
        _permissoes = {};
        _carregandoPermissoes = false;
      });
    }
  }

  Future<void> _loadSvg() async {
    try {
      final content = await DefaultAssetBundle.of(context).loadString('assets/images/corda.svg');
      if (mounted) {
        setState(() {
          _svgContent = content;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar SVG: $e');
    }
  }

  // 📚 GRADUAÇÕES COM CACHE - AGORA INDEXADO POR NOME
  Future<void> _preloadGraduacoes() async {
    try {
      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await FirebaseFirestore.instance
            .collection('graduacoes')
            .limit(50)
            .get(const GetOptions(source: Source.cache));
      } catch (e) {
        snapshot = await FirebaseFirestore.instance
            .collection('graduacoes')
            .limit(50)
            .get(const GetOptions(source: Source.server));
      }

      for (var doc in snapshot.docs) {
        final nomeGraduacao = doc['nome_graduacao']?.toString();
        if (nomeGraduacao != null && nomeGraduacao.isNotEmpty) {
          _graduacoesCache[nomeGraduacao] = {
            'id': doc.id,
            'hex_cor1': doc['hex_cor1'],
            'hex_cor2': doc['hex_cor2'],
            'hex_ponta1': doc['hex_ponta1'],
            'hex_ponta2': doc['hex_ponta2'],
            'nome_graduacao': nomeGraduacao,
          };
        }
      }
      debugPrint('✅ ${_graduacoesCache.length} graduações carregadas em cache (indexadas por nome)');
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar graduações: $e');
    }
  }

  // 👥 CARREGAR ALUNOS
  Future<void> _carregarAlunos() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }

    try {
      _alunosSubscription?.cancel();

      _alunosSubscription = _firestore
          .collection('alunos')
          .where('turma_id', isEqualTo: widget.turmaId)
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .snapshots(includeMetadataChanges: true)
          .listen((snapshot) {
        if (!mounted) return;

        final alunos = snapshot.docs;
        alunos.sort((a, b) {
          final nomeA = (a.data()['nome'] ?? '').toLowerCase();
          final nomeB = (b.data()['nome'] ?? '').toLowerCase();
          return nomeA.compareTo(nomeB);
        });

        _syncService.updatePendingCount(snapshot);

        setState(() {
          _alunosCache = alunos;
          _isLoading = false;
        });

        debugPrint('✅ ${_alunosCache.length} alunos carregados');
      }, onError: (error) {
        debugPrint('❌ ERRO no snapshot: $error');
        if (mounted) {
          setState(() {
            _hasError = true;
            _isLoading = false;
          });
        }
      });
    } catch (e) {
      debugPrint('❌ ERRO ao configurar snapshot: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  int _calculateAge(Timestamp? birthDate) {
    if (birthDate == null) return 0;
    final today = DateTime.now();
    final birth = birthDate.toDate();
    int age = today.year - birth.year;
    if (today.month < birth.month ||
        (today.month == birth.month && today.day < birth.day)) {
      age--;
    }
    return age;
  }

  // 🔍 NOVO MÉTODO: OBTER NOME DA GRADUAÇÃO DO ALUNO
  String _obterNomeGraduacaoAluno(Map<String, dynamic> data) {
    // Prioridade 1: Nome da graduação vindo do cache/graduacoes
    final graduacaoId = data['graduacao_id']?.toString();
    if (graduacaoId != null && graduacaoId.isNotEmpty) {
      // Se temos o ID, tenta encontrar no cache por ID (mas vamos converter para nome)
      for (var entry in _graduacoesCache.entries) {
        if (entry.value['id'] == graduacaoId) {
          return entry.key; // Retorna o nome (que é a chave do cache)
        }
      }
    }

    // Prioridade 2: Campo graduacao_nome direto
    final graduacaoNome = data['graduacao_nome']?.toString();
    if (graduacaoNome != null && graduacaoNome.isNotEmpty) {
      return graduacaoNome;
    }

    // Prioridade 3: Campo graduacao_atual
    final graduacaoAtual = data['graduacao_atual']?.toString();
    if (graduacaoAtual != null && graduacaoAtual.isNotEmpty) {
      return graduacaoAtual;
    }

    // Prioridade 4: Graduação padrão
    return 'SEM GRADUAÇÃO';
  }

  // 🎨 GET MODIFIED SVG - AGORA POR NOME DA GRADUAÇÃO
  Future<String?> _getModifiedSvg(Map<String, dynamic> data) async {
    final nomeGraduacao = _obterNomeGraduacaoAluno(data);

    if (nomeGraduacao.isEmpty || nomeGraduacao == 'SEM GRADUAÇÃO' || _svgContent == null) {
      return null;
    }

    final cacheKey = 'svg_$nomeGraduacao';
    if (_svgCache.containsKey(cacheKey)) {
      return _svgCache[cacheKey];
    }

    // Busca as cores da graduação pelo nome
    Map<String, dynamic>? coresGraduacao;

    if (_graduacoesCache.containsKey(nomeGraduacao)) {
      coresGraduacao = _graduacoesCache[nomeGraduacao];
    } else {
      // Se não está no cache, busca no Firestore pelo nome
      try {
        QuerySnapshot<Map<String, dynamic>> snapshot;
        try {
          snapshot = await _firestore
              .collection('graduacoes')
              .where('nome_graduacao', isEqualTo: nomeGraduacao)
              .limit(1)
              .get(const GetOptions(source: Source.cache));
        } catch (e) {
          snapshot = await _firestore
              .collection('graduacoes')
              .where('nome_graduacao', isEqualTo: nomeGraduacao)
              .limit(1)
              .get(const GetOptions(source: Source.server));
        }

        if (snapshot.docs.isNotEmpty) {
          final doc = snapshot.docs.first;
          coresGraduacao = {
            'id': doc.id,
            'hex_cor1': doc['hex_cor1'],
            'hex_cor2': doc['hex_cor2'],
            'hex_ponta1': doc['hex_ponta1'],
            'hex_ponta2': doc['hex_ponta2'],
            'nome_graduacao': nomeGraduacao,
          };
          _graduacoesCache[nomeGraduacao] = coresGraduacao;
        }
      } catch (e) {
        debugPrint('⚠️ Erro ao buscar graduação por nome "$nomeGraduacao": $e');
      }
    }

    if (coresGraduacao == null) return null;

    final document = xml.XmlDocument.parse(_svgContent!);

    Color colorFromHex(String? hexColor) {
      if (hexColor == null || hexColor.length < 7) return Colors.grey;
      try {
        return Color(int.parse('FF${hexColor.replaceAll('#', '')}', radix: 16));
      } catch (e) {
        return Colors.grey;
      }
    }

    void changeColor(String id, Color color) {
      final element = document.rootElement.descendants
          .whereType<xml.XmlElement>()
          .firstWhere(
            (e) => e.getAttribute('id') == id,
        orElse: () => xml.XmlElement(xml.XmlName('')),
      );
      if (element.name.local.isNotEmpty) {
        final style = element.getAttribute('style') ?? '';
        final hex = '#${color.value.toRadixString(16).substring(2).toLowerCase()}';
        final newStyle = style.replaceAll(RegExp(r'fill:#[0-9a-fA-F]{6}'), '');
        element.setAttribute('style', 'fill:$hex;$newStyle');
      }
    }

    changeColor('cor1', colorFromHex(coresGraduacao['hex_cor1']));
    changeColor('cor2', colorFromHex(coresGraduacao['hex_cor2']));
    changeColor('corponta1', colorFromHex(coresGraduacao['hex_ponta1']));
    changeColor('corponta2', colorFromHex(coresGraduacao['hex_ponta2']));

    final svgString = document.toXmlString();
    _svgCache[cacheKey] = svgString;

    return svgString;
  }

  // ✅ HAS VALID GRADUATION - AGORA POR NOME
  Future<bool> _hasValidGraduation(Map<String, dynamic> data) async {
    final nomeGraduacao = _obterNomeGraduacaoAluno(data);

    if (nomeGraduacao.isEmpty || nomeGraduacao == 'SEM GRADUAÇÃO') {
      return false;
    }

    if (_graduacaoValidaCache.containsKey(nomeGraduacao)) {
      return _graduacaoValidaCache[nomeGraduacao]!;
    }

    // Verifica se já está no cache de graduações
    if (_graduacoesCache.containsKey(nomeGraduacao)) {
      _graduacaoValidaCache[nomeGraduacao] = true;
      return true;
    }

    // Se não está no cache, busca no Firestore pelo nome
    try {
      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await _firestore
            .collection('graduacoes')
            .where('nome_graduacao', isEqualTo: nomeGraduacao)
            .limit(1)
            .get(const GetOptions(source: Source.cache));
      } catch (e) {
        snapshot = await _firestore
            .collection('graduacoes')
            .where('nome_graduacao', isEqualTo: nomeGraduacao)
            .limit(1)
            .get(const GetOptions(source: Source.server));
      }

      final isValid = snapshot.docs.isNotEmpty;
      _graduacaoValidaCache[nomeGraduacao] = isValid;

      if (isValid) {
        final doc = snapshot.docs.first;
        _graduacoesCache[nomeGraduacao] = {
          'id': doc.id,
          'hex_cor1': doc['hex_cor1'],
          'hex_cor2': doc['hex_cor2'],
          'hex_ponta1': doc['hex_ponta1'],
          'hex_ponta2': doc['hex_ponta2'],
          'nome_graduacao': nomeGraduacao,
        };
      }

      return isValid;
    } catch (e) {
      _graduacaoValidaCache[nomeGraduacao] = false;
      return false;
    }
  }

  // 📝 GET GRADUAÇÃO NOME - SIMPLIFICADO
  String _getGraduacaoNome(Map<String, dynamic> data) {
    return _obterNomeGraduacaoAluno(data);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _getAlunosFiltrados() {
    if (_searchQuery.isEmpty) {
      return _alunosCache;
    }

    return _alunosCache.where((doc) {
      final data = doc.data();
      final nome = (data['nome'] as String? ?? '').toLowerCase();
      return nome.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  void _abrirDetalhesAluno(String alunoId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AlunoDetalheScreen(
          alunoId: alunoId,
        ),
      ),
    );
  }

  // ✅ VERIFICAR SE PODE ADICIONAR ALUNO (PERMISSÃO + ONLINE)
  bool _podeAdicionarAluno() {
    return _permissoes['pode_adicionar_aluno'] == true && _isOnline;
  }

  Future<void> _abrirCadastroAluno() async {
    debugPrint('🔑 Verificando permissão: pode_adicionar_aluno = ${_permissoes['pode_adicionar_aluno']}');
    debugPrint('📡 Status online: $_isOnline');

    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🌐 Você precisa estar conectado à internet para cadastrar um novo aluno.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    if (_permissoes['pode_adicionar_aluno'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⛔ Você não tem permissão para cadastrar alunos.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CadastroAlunoTurmaScreen(
          turmaId: widget.turmaId,
          turmaNome: widget.turmaNome,
          academiaId: widget.academiaId,
          academiaNome: widget.academiaNome,
        ),
      ),
    );

    _carregarAlunos();
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 80,
            color: Colors.red,
          ),
          const SizedBox(height: 20),
          const Text(
            'Erro ao carregar alunos',
            style: TextStyle(
              fontSize: 18,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: _carregarAlunos,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade900,
              foregroundColor: Colors.white,
            ),
            child: const Text('TENTAR NOVAMENTE'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    final podeAdicionar = _podeAdicionarAluno();

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 80,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 20),
          const Text(
            'Nenhum aluno ativo nesta turma',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Turma: ${widget.turmaNome}',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: podeAdicionar ? _abrirCadastroAluno : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: podeAdicionar
                  ? Colors.teal.shade600
                  : Colors.grey.shade400,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            icon: const Icon(Icons.person_add),
            label: const Text('CADASTRAR PRIMEIRO ALUNO'),
          ),
          if (!_isOnline)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                '⛔ Offline - Conecte-se à internet para cadastrar',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.orange.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else if (_permissoes['pode_adicionar_aluno'] != true)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                'Você não tem permissão para cadastrar alunos',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNoSearchResultsView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.search_off,
            size: 80,
            color: Colors.grey,
          ),
          const SizedBox(height: 20),
          const Text(
            "Nenhum aluno encontrado",
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey,
            ),
          ),
          Text(
            "Nome pesquisado: '$_searchQuery'",
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () => setState(() => _searchQuery = ''),
            child: const Text('LIMPAR BUSCA'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final alunosFiltrados = _getAlunosFiltrados();
    final podeAdicionar = _podeAdicionarAluno();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  widget.turmaNome,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isOnline ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            Text(
              'ALUNOS ATIVOS (${_alunosCache.length})',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_viewModeIcons[_viewMode]),
            tooltip: _viewModeTooltips[_viewMode],
            onPressed: () => setState(() => _viewMode = (_viewMode + 1) % 3),
          ),
          IconButton(
            icon: Icon(
              Icons.person_add,
              color: podeAdicionar ? Colors.white : Colors.grey.shade400,
            ),
            tooltip: podeAdicionar
                ? 'Cadastrar Novo Aluno'
                : (_isOnline ? 'Sem permissão' : 'Offline - Conecte-se para cadastrar'),
            onPressed: podeAdicionar ? _abrirCadastroAluno : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar',
            onPressed: _carregarAlunos,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60.0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar aluno por nome...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                prefixIcon: const Icon(Icons.search, color: Colors.white),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white),
                  onPressed: () => setState(() => _searchQuery = ''),
                )
                    : null,
                enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white54)),
                focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white)),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
        ),
      ),
      body: _isLoading || _carregandoPermissoes
          ? const Center(child: CircularProgressIndicator())
          : _hasError
          ? _buildErrorView()
          : _alunosCache.isEmpty
          ? _buildEmptyView()
          : alunosFiltrados.isEmpty
          ? _buildNoSearchResultsView()
          : Column(
        children: [
          StreamBuilder<int>(
            stream: _syncService.pendingCountStream,
            initialData: _syncService.currentPendingCount,
            builder: (context, snapshot) {
              final pendingCount = snapshot.data ?? 0;
              return GlobalSyncCounter(
                pendingCount: pendingCount,
              );
            },
          ),
          Expanded(
            child: _getCurrentView(alunosFiltrados),
          ),
        ],
      ),
    );
  }

  Widget _getCurrentView(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    switch (_viewMode) {
      case 0:
        return _buildListView(docs);
      case 1:
        return _buildGridView(docs);
      case 2:
        return _buildCompactView(docs);
      default:
        return _buildListView(docs);
    }
  }

  // ============================================
  // VISUALIZAÇÃO EM LISTA
  // ============================================
  Widget _buildListView(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return RefreshIndicator(
      onRefresh: _carregarAlunos,
      child: ListView.builder(
        key: const ValueKey('listView'),
        padding: const EdgeInsets.all(12.0),
        itemCount: docs.length,
        itemBuilder: (context, index) {
          final aluno = docs[index];
          final data = aluno.data();
          final alunoId = aluno.id;
          final nomeAluno = data['nome'] ?? 'Nome não informado';
          final fotoUrl = data['foto_perfil_aluno'] as String?;
          final idade = _calculateAge(data['data_nascimento']);
          final graduacaoNome = _getGraduacaoNome(data);

          return FutureBuilder<bool>(
            future: _hasValidGraduation(data),
            builder: (context, graduationSnapshot) {
              final hasValidGraduation = graduationSnapshot.data ?? false;

              return FutureBuilder<String?>(
                future: hasValidGraduation
                    ? _getModifiedSvg(data)
                    : Future.value(null),
                builder: (context, svgSnapshot) {
                  final modifiedSvg = svgSnapshot.data;
                  final isLoadingSvg =
                      svgSnapshot.connectionState == ConnectionState.waiting;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 3,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: InkWell(
                      onTap: () => _abrirDetalhesAluno(aluno.id),
                      child: Row(
                        children: [
                          // Foto + idade
                          Stack(
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                color: Colors.grey[200],
                                child: fotoUrl != null && fotoUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                  imageUrl: fotoUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (c, u, e) =>
                                      _placeholderIcon(),
                                )
                                    : _placeholderIcon(),
                              ),
                              // IDADE NA PARTE INFERIOR
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  height: 24,
                                  color: Colors.red.shade900.withOpacity(0.9),
                                  child: Center(
                                    child: Text(
                                      '$idade ANOS',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // Informações do aluno
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    nomeAluno,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (graduacaoNome.isNotEmpty && graduacaoNome != 'SEM GRADUAÇÃO') ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      graduacaoNome,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  SyncIndicator(
                                    isPending:
                                    _syncService.isDocumentPending(aluno),
                                    isCompact: true,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Corda SVG
                          if (hasValidGraduation)
                            Container(
                              width: 60,
                              padding: const EdgeInsets.only(right: 12),
                              child: isLoadingSvg
                                  ? const CircularProgressIndicator(
                                  strokeWidth: 2)
                                  : (modifiedSvg != null
                                  ? SvgPicture.string(modifiedSvg,
                                  height: 60)
                                  : const SizedBox.shrink()),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  // ============================================
  // VISUALIZAÇÃO EM GRADE
  // ============================================
  Widget _buildGridView(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return RefreshIndicator(
      onRefresh: _carregarAlunos,
      child: GridView.builder(
        key: const ValueKey('gridView'),
        padding: const EdgeInsets.all(16.0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.75,
        ),
        itemCount: docs.length,
        itemBuilder: (context, index) {
          final aluno = docs[index];
          final data = aluno.data();
          final alunoId = aluno.id;
          final nomeAluno = data['nome'] ?? 'Nome não informado';
          final fotoUrl = data['foto_perfil_aluno'] as String?;
          final idade = _calculateAge(data['data_nascimento']);
          final graduacaoNome = _getGraduacaoNome(data);

          return Card(
            elevation: 4,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              onTap: () => _abrirDetalhesAluno(aluno.id),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Área da foto
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
                            errorWidget: (c, u, e) =>
                                _placeholderIcon(size: 80),
                          )
                              : _placeholderIcon(size: 80),
                        ),
                        // IDADE NA PARTE INFERIOR
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 28,
                            color: Colors.red.shade900.withOpacity(0.9),
                            child: Center(
                              child: Text(
                                '$idade ANOS',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Informações do aluno
                  Container(
                    padding: const EdgeInsets.all(12.0),
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nomeAluno.toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (graduacaoNome.isNotEmpty && graduacaoNome != 'SEM GRADUAÇÃO') ...[
                          const SizedBox(height: 4),
                          Text(
                            graduacaoNome,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 6),
                        SyncIndicator(
                          isPending: _syncService.isDocumentPending(aluno),
                          isCompact: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ============================================
  // VISUALIZAÇÃO COMPACTA
  // ============================================
  Widget _buildCompactView(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return RefreshIndicator(
      onRefresh: _carregarAlunos,
      child: ListView.builder(
        key: const ValueKey('compactView'),
        padding: const EdgeInsets.all(8.0),
        itemCount: docs.length,
        itemBuilder: (context, index) {
          final aluno = docs[index];
          final data = aluno.data();
          final nomeAluno = data['nome'] ?? 'Nome não informado';
          final fotoUrl = data['foto_perfil_aluno'] as String?;

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            elevation: 1,
            child: InkWell(
              onTap: () => _abrirDetalhesAluno(aluno.id),
              child: Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[200],
                      ),
                      child: fotoUrl != null && fotoUrl.isNotEmpty
                          ? ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: fotoUrl,
                          fit: BoxFit.cover,
                          errorWidget: (c, u, e) => Icon(Icons.person,
                              size: 30, color: Colors.grey[400]),
                        ),
                      )
                          : Icon(Icons.person,
                          size: 30, color: Colors.grey[400]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              nomeAluno,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SyncIndicator(
                            isPending: _syncService.isDocumentPending(aluno),
                            isCompact: true,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _placeholderIcon({double size = 50}) {
    return Center(
      child: Icon(Icons.person, size: size, color: Colors.white),
    );
  }
}