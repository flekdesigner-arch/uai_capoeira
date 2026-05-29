import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart' as xml;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'cadastro_aluno_turma_screen.dart';
import 'package:uai_capoeira/modules/alunos/screens/aluno_detalhe_screen.dart';
import 'package:uai_capoeira/core/services/sync_service.dart';
import 'package:uai_capoeira/shared/widgets/sync_indicator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

// ============================================
// 🔥 SERVIÇO DE CACHE INTELIGENTE (30 MINUTOS)
// ============================================
class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  final Map<String, CacheEntry> _memoryCache = {};
  final Duration cacheValidity = const Duration(minutes: 30);

  bool isCacheValid(String key) {
    final entry = _memoryCache[key];
    if (entry == null) return false;
    return DateTime.now().difference(entry.timestamp) < cacheValidity;
  }

  void saveToCache(String key, dynamic data) {
    _memoryCache[key] = CacheEntry(data: data, timestamp: DateTime.now());
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

  void limparTodoCache() {
    _memoryCache.clear();
    debugPrint('🗑️ Cache de dados limpo completamente');
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
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Connectivity _connectivity = Connectivity();
  final CacheService _cache = CacheService();
  final SyncService _syncService = SyncService();

  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isRefreshing = false;

  String? _svgContent;
  String _searchQuery = '';
  Timer? _searchDebounce; // 🔥 Debounce para busca avançada
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

  final Map<String, Map<String, dynamic>> _graduacoesCache = {};
  final Map<String, String> _svgCache = {};
  final Map<String, bool> _graduacaoValidaCache = {};

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

    Timer.periodic(const Duration(minutes: 1), (timer) {
      _cache.limparCacheExpirado();
    });
  }

  @override
  void dispose() {
    _alunosSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _searchDebounce?.cancel();
    _syncService.dispose();
    super.dispose();
  }

  // ======================== NORMALIZAÇÃO E BUSCA AVANÇADA ========================
  String _normalizeString(String text) {
    if (text.isEmpty) return '';
    const withAccents = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇñÑ';
    const withoutAccents = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUCnN';
    String normalized = text;
    for (int i = 0; i < withAccents.length; i++) {
      normalized = normalized.replaceAll(withAccents[i], withoutAccents[i]);
    }
    normalized = normalized.replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '');
    return normalized.toLowerCase().trim();
  }

  bool _alunoCorrespondeBusca(Map<String, dynamic> data, String termoBusca) {
    if (termoBusca.isEmpty) return true;
    final termoNormalizado = _normalizeString(termoBusca);
    if (termoNormalizado.isEmpty) return true;

    final campos = [
      _normalizeString(data['nome'] ?? ''),
      _normalizeString(data['apelido'] ?? ''),
      _normalizeString(data['nome_responsavel'] ?? ''),
      _normalizeString(data['contato_aluno'] ?? ''),
      _normalizeString(data['contato_responsavel'] ?? ''),
    ];

    // Busca numérica (telefone)
    if (RegExp(r'^\d+$').hasMatch(termoNormalizado)) {
      return campos.any((c) => c.contains(termoNormalizado));
    }

    final palavras = termoNormalizado.split(RegExp(r'\s+'));
    return palavras.every((palavra) {
      if (palavra.length <= 2 && !RegExp(r'^\d+$').hasMatch(palavra)) return true;
      return campos.any((c) => c.contains(palavra));
    });
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _getAlunosFiltrados() {
    if (_searchQuery.isEmpty) return _alunosCache;
    return _alunosCache.where((doc) {
      return _alunoCorrespondeBusca(doc.data(), _searchQuery);
    }).toList();
  }
  // =====================================================================

  void _monitorarConectividade() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
          (List<ConnectivityResult> results) {
        if (!mounted) return;
        final isOnline = results.isNotEmpty && results.first != ConnectivityResult.none;
        setState(() => _isOnline = isOnline);
        debugPrint('📡 Status de conexão: ${isOnline ? 'ONLINE' : 'OFFLINE'}');
      },
    );
    _verificarConectividadeInicial();
  }

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
      if (mounted) setState(() => _isOnline = false);
    }
  }

  Future<void> _limparCacheImagens() async {
    try {
      final cacheManager = DefaultCacheManager();
      await cacheManager.emptyCache();
      debugPrint('✅ Cache de imagens limpo');
    } catch (e) {
      debugPrint('⚠️ Erro ao limpar cache de imagens: $e');
    }
  }

  Future<void> _forcarRecarregamento() async {
    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🌐 Você precisa estar conectado à internet para recarregar.'), backgroundColor: context.uai.warning),
      );
      return;
    }
    setState(() {
      _isRefreshing = true;
      _isLoading = true;
    });
    try {
      _cache.limparTodoCache();
      _graduacoesCache.clear();
      _svgCache.clear();
      _graduacaoValidaCache.clear();
      await _limparCacheImagens();
      await _carregarAlunosForcado();
      await _preloadGraduacoes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Row(children: [Icon(Icons.check_circle, color: _readableOn(context.uai.success)), SizedBox(width: 12), Expanded(child: Text('Dados recarregados do servidor com sucesso!'))]), backgroundColor: context.uai.success, duration: const Duration(seconds: 3), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      debugPrint('❌ Erro ao recarregar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao recarregar: $e'), backgroundColor: context.uai.error));
      }
    } finally {
      if (mounted) setState(() {
        _isRefreshing = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _carregarAlunosForcado() async {
    try {
      _alunosSubscription?.cancel();
      final snapshot = await _firestore
          .collection('alunos')
          .where('turma_id', isEqualTo: widget.turmaId)
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .get(const GetOptions(source: Source.server));
      final alunos = snapshot.docs;
      alunos.sort((a, b) {
        final nomeA = (a.data()['nome'] ?? '').toLowerCase();
        final nomeB = (b.data()['nome'] ?? '').toLowerCase();
        return nomeA.compareTo(nomeB);
      });
      setState(() => _alunosCache = alunos);
      debugPrint('✅ ${_alunosCache.length} alunos carregados do SERVIDOR');

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
        setState(() => _alunosCache = alunos);
      }, onError: (error) {
        debugPrint('❌ ERRO no snapshot: $error');
        if (mounted) setState(() => _hasError = true);
      });
    } catch (e) {
      debugPrint('❌ Erro ao carregar alunos do servidor: $e');
      rethrow;
    }
  }

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
      if (mounted) setState(() => _svgContent = content);
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar SVG: $e');
    }
  }

  Future<void> _preloadGraduacoes() async {
    Future<QuerySnapshot<Map<String, dynamic>>> buscar(Source source) {
      return _firestore
          .collection('graduacoes')
          .limit(500)
          .get(GetOptions(source: source));
    }

    try {
      QuerySnapshot<Map<String, dynamic>> snapshot;

      try {
        snapshot = await buscar(Source.cache);

        // No web/PWA é comum o cache responder sem erro, mas vazio.
        // Se vier vazio, busca no servidor para realmente popular as cordas.
        if (snapshot.docs.isEmpty && _isOnline) {
          snapshot = await buscar(Source.server);
        }
      } catch (_) {
        snapshot = await buscar(Source.server);
      }

      _graduacoesCache.clear();

      for (final doc in snapshot.docs) {
        _salvarGraduacaoNoCache(doc.id, doc.data());
      }

      if (mounted) setState(() {});

      debugPrint(
        '✅ ${snapshot.docs.length} graduações carregadas para corda.svg',
      );
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar graduações: $e');
    }
  }

  Future<void> _carregarAlunos() async {
    if (mounted) setState(() {
      _isLoading = true;
      _hasError = false;
    });
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
        if (mounted) setState(() {
          _hasError = true;
          _isLoading = false;
        });
      });
    } catch (e) {
      debugPrint('❌ ERRO ao configurar snapshot: $e');
      if (mounted) setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  int _calculateAge(Timestamp? birthDate) {
    if (birthDate == null) return 0;
    final today = DateTime.now();
    final birth = birthDate.toDate();
    int age = today.year - birth.year;
    if (today.month < birth.month || (today.month == birth.month && today.day < birth.day)) age--;
    return age;
  }

  String _graduacaoKey(String value) {
    return _normalizeString(value).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  void _salvarGraduacaoNoCache(
      String docId,
      Map<String, dynamic> data, {
        String? nomeForcado,
      }) {
    final nomeGraduacao = nomeForcado ??
        data['nome_graduacao']?.toString() ??
        data['nome']?.toString() ??
        data['titulo']?.toString() ??
        '';

    if (nomeGraduacao.trim().isEmpty) return;

    final item = {
      'id': docId,
      'hex_cor1': data['hex_cor1'],
      'hex_cor2': data['hex_cor2'],
      'hex_ponta1': data['hex_ponta1'],
      'hex_ponta2': data['hex_ponta2'],
      'nome_graduacao': nomeGraduacao,
    };

    _graduacoesCache[nomeGraduacao] = item;
    _graduacoesCache[_graduacaoKey(nomeGraduacao)] = item;
    _graduacoesCache[docId] = item;
  }

  String _obterNomeGraduacaoAluno(Map<String, dynamic> data) {
    final graduacaoId = data['graduacao_id']?.toString();

    if (graduacaoId != null && graduacaoId.isNotEmpty) {
      final porId = _graduacoesCache[graduacaoId];
      if (porId != null) {
        return porId['nome_graduacao']?.toString() ?? graduacaoId;
      }

      for (final entry in _graduacoesCache.entries) {
        if (entry.value['id']?.toString() == graduacaoId) {
          return entry.value['nome_graduacao']?.toString() ?? entry.key;
        }
      }
    }

    final camposPossiveis = [
      data['graduacao_nome'],
      data['graduacao_atual'],
      data['graduacao_nova'],
      data['graduacao'],
      data['corda'],
      data['corda_atual'],
      data['faixa'],
    ];

    for (final value in camposPossiveis) {
      final texto = value?.toString().trim() ?? '';
      if (texto.isNotEmpty && texto.toUpperCase() != 'SEM GRADUAÇÃO') {
        return texto;
      }
    }

    return 'SEM GRADUAÇÃO';
  }

  Future<String?> _getModifiedSvg(Map<String, dynamic> data) async {
    final nomeGraduacao = _obterNomeGraduacaoAluno(data);
    final graduacaoId = data['graduacao_id']?.toString();

    if (nomeGraduacao.isEmpty ||
        nomeGraduacao == 'SEM GRADUAÇÃO' ||
        _svgContent == null) {
      return null;
    }

    final cacheKey = 'svg_${graduacaoId ?? ''}_${_graduacaoKey(nomeGraduacao)}';
    if (_svgCache.containsKey(cacheKey)) return _svgCache[cacheKey];

    Map<String, dynamic>? coresGraduacao;

    // 1) tenta por id
    if (graduacaoId != null && graduacaoId.isNotEmpty) {
      coresGraduacao = _graduacoesCache[graduacaoId];

      if (coresGraduacao == null) {
        try {
          DocumentSnapshot<Map<String, dynamic>> doc;

          try {
            doc = await _firestore
                .collection('graduacoes')
                .doc(graduacaoId)
                .get(const GetOptions(source: Source.cache));

            if (!doc.exists && _isOnline) {
              doc = await _firestore
                  .collection('graduacoes')
                  .doc(graduacaoId)
                  .get(const GetOptions(source: Source.server));
            }
          } catch (_) {
            doc = await _firestore
                .collection('graduacoes')
                .doc(graduacaoId)
                .get(const GetOptions(source: Source.server));
          }

          if (doc.exists) {
            final docData = doc.data() ?? {};
            _salvarGraduacaoNoCache(doc.id, docData);
            coresGraduacao = _graduacoesCache[doc.id];
          }
        } catch (e) {
          debugPrint('⚠️ Erro ao buscar graduação por id "$graduacaoId": $e');
        }
      }
    }

    // 2) tenta por nome normalizado/cache
    coresGraduacao ??= _graduacoesCache[nomeGraduacao];
    coresGraduacao ??= _graduacoesCache[_graduacaoKey(nomeGraduacao)];

    // 3) tenta por nome exato no Firestore, com cache vazio caindo para servidor
    if (coresGraduacao == null) {
      try {
        QuerySnapshot<Map<String, dynamic>> snapshot;

        try {
          snapshot = await _firestore
              .collection('graduacoes')
              .where('nome_graduacao', isEqualTo: nomeGraduacao)
              .limit(1)
              .get(const GetOptions(source: Source.cache));

          if (snapshot.docs.isEmpty && _isOnline) {
            snapshot = await _firestore
                .collection('graduacoes')
                .where('nome_graduacao', isEqualTo: nomeGraduacao)
                .limit(1)
                .get(const GetOptions(source: Source.server));
          }
        } catch (_) {
          snapshot = await _firestore
              .collection('graduacoes')
              .where('nome_graduacao', isEqualTo: nomeGraduacao)
              .limit(1)
              .get(const GetOptions(source: Source.server));
        }

        if (snapshot.docs.isNotEmpty) {
          final doc = snapshot.docs.first;
          _salvarGraduacaoNoCache(doc.id, doc.data(), nomeForcado: nomeGraduacao);
          coresGraduacao = _graduacoesCache[_graduacaoKey(nomeGraduacao)];
        }
      } catch (e) {
        debugPrint('⚠️ Erro ao buscar graduação por nome "$nomeGraduacao": $e');
      }
    }

    if (coresGraduacao == null) {
      debugPrint('⚠️ Sem cores cadastradas para graduação: $nomeGraduacao');
      return null;
    }

    final document = xml.XmlDocument.parse(_svgContent!);

    Color colorFromHex(String? hexColor) {
      if (hexColor == null || hexColor.trim().isEmpty) return context.uai.textMuted;

      try {
        final cleaned = hexColor.replaceAll('#', '').trim();
        if (cleaned.length == 6) {
          return Color(int.parse('FF$cleaned', radix: 16));
        }

        if (cleaned.length == 8) {
          return Color(int.parse(cleaned, radix: 16));
        }

        return context.uai.textMuted;
      } catch (_) {
        return context.uai.textMuted;
      }
    }

    void changeColor(String id, Color color) {
      final element = document.rootElement.descendants
          .whereType<xml.XmlElement>()
          .firstWhere(
            (e) => e.getAttribute('id') == id,
        orElse: () => xml.XmlElement(xml.XmlName('')),
      );

      if (element.name.local.isEmpty) return;

      final hex = '#${color.value.toRadixString(16).substring(2).toLowerCase()}';
      final oldStyle = element.getAttribute('style') ?? '';

      if (oldStyle.contains('fill:')) {
        final newStyle = oldStyle.replaceAll(
          RegExp(r'fill:\s*#[0-9a-fA-F]{3,8}'),
          'fill:$hex',
        );
        element.setAttribute('style', newStyle);
      } else {
        element.setAttribute('style', 'fill:$hex;$oldStyle');
      }

      element.setAttribute('fill', hex);
    }

    changeColor('cor1', colorFromHex(coresGraduacao['hex_cor1']?.toString()));
    changeColor('cor2', colorFromHex(coresGraduacao['hex_cor2']?.toString()));
    changeColor('corponta1', colorFromHex(coresGraduacao['hex_ponta1']?.toString()));
    changeColor('corponta2', colorFromHex(coresGraduacao['hex_ponta2']?.toString()));

    final svgString = document.toXmlString();
    _svgCache[cacheKey] = svgString;
    return svgString;
  }

  Future<bool> _hasValidGraduation(Map<String, dynamic> data) async {
    final svg = await _getModifiedSvg(data);
    return svg != null;
  }

  String _getGraduacaoNome(Map<String, dynamic> data) => _obterNomeGraduacaoAluno(data);

  void _abrirDetalhesAluno(String alunoId) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => AlunoDetalheScreen(alunoId: alunoId)));
  }

  bool _podeAdicionarAluno() => _permissoes['pode_adicionar_aluno'] == true && _isOnline;

  Future<void> _abrirCadastroAluno() async {
    debugPrint('🔑 Verificando permissão: pode_adicionar_aluno = ${_permissoes['pode_adicionar_aluno']}');
    debugPrint('📡 Status online: $_isOnline');

    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🌐 Você precisa estar conectado à internet para cadastrar um novo aluno.'), backgroundColor: context.uai.warning),
      );
      return;
    }
    if (_permissoes['pode_adicionar_aluno'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⛔ Você não tem permissão para cadastrar alunos.'), backgroundColor: context.uai.error),
      );
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (context) => CadastroAlunoTurmaScreen(
      turmaId: widget.turmaId,
      turmaNome: widget.turmaNome,
      academiaId: widget.academiaId,
      academiaNome: widget.academiaNome,
    )));
    _carregarAlunos();
  }

  Widget _buildErrorView() {
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
              Icon(Icons.error_outline_rounded, size: 64, color: t.error),
              SizedBox(height: 16),
              Text(
                'Erro ao carregar alunos',
                style: TextStyle(
                  fontSize: 18,
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _carregarAlunos,
                icon: Icon(Icons.refresh_rounded),
                label: Text('TENTAR NOVAMENTE'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    final t = context.uai;
    final podeAdicionar = _podeAdicionarAluno();

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
              Icon(Icons.people_outline_rounded, size: 72, color: t.textMuted),
              const SizedBox(height: 16),
              Text(
                'Nenhum aluno ativo nesta turma',
                style: TextStyle(
                  fontSize: 17,
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 7),
              Text(
                'Turma: ${widget.turmaNome}',
                style: TextStyle(
                  fontSize: 13,
                  color: t.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: podeAdicionar ? _abrirCadastroAluno : null,
                icon: const Icon(Icons.person_add_rounded),
                label: const Text('CADASTRAR PRIMEIRO ALUNO'),
              ),
              if (!_isOnline) ...[
                SizedBox(height: 10),
                Text(
                  'Offline. Conecte-se à internet para cadastrar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: t.warning),
                ),
              ],
              if (_permissoes['pode_adicionar_aluno'] != true && _isOnline) ...[
                SizedBox(height: 10),
                Text(
                  'Você não tem permissão para cadastrar alunos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: t.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoSearchResultsView() {
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
              Icon(Icons.search_off_rounded, size: 72, color: t.textMuted),
              const SizedBox(height: 16),
              Text(
                'Nenhum aluno encontrado',
                style: TextStyle(
                  fontSize: 18,
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 7),
              Text(
                "Nome pesquisado: '$_searchQuery'",
                style: TextStyle(
                  fontSize: 13,
                  color: t.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
              SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => setState(() => _searchQuery = ''),
                icon: Icon(Icons.close_rounded),
                label: Text('LIMPAR BUSCA'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final alunosFiltrados = _getAlunosFiltrados();
    final podeAdicionar = _podeAdicionarAluno();
    final t = context.uai;
    final appBarBg = Theme.of(context).appBarTheme.backgroundColor ?? t.primary;
    final appBarFg = Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(appBarBg);
    final searchBg = appBarFg.withOpacity(0.13);
    final searchBorder = appBarFg.withOpacity(0.18);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(widget.turmaNome, style: TextStyle(fontSize: 16, color: appBarFg, fontWeight: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis)),
            SizedBox(width: 8),
            Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: _isOnline ? t.success : t.error)),
          ]),
          Text('ALUNOS ATIVOS (${_alunosCache.length})', style: TextStyle(fontSize: 12, color: appBarFg.withOpacity(0.82), fontWeight: FontWeight.w700)),
        ]),
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        actions: [
          IconButton(icon: Icon(_viewModeIcons[_viewMode], color: appBarFg), tooltip: _viewModeTooltips[_viewMode], onPressed: () => setState(() => _viewMode = (_viewMode + 1) % 3)),
          IconButton(
            icon: Icon(Icons.person_add, color: podeAdicionar ? appBarFg : appBarFg.withOpacity(0.35)),
            tooltip: podeAdicionar ? 'Cadastrar Novo Aluno' : (_isOnline ? 'Sem permissão' : 'Offline - Conecte-se para cadastrar'),
            onPressed: podeAdicionar ? _abrirCadastroAluno : null,
          ),
          IconButton(
            icon: _isRefreshing ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: appBarFg)) : Icon(Icons.refresh, color: appBarFg),
            tooltip: _isRefreshing ? 'Recarregando...' : (_isOnline ? 'Recarregar do servidor (limpa cache)' : 'Offline - Conecte-se para recarregar'),
            onPressed: _isRefreshing ? null : _forcarRecarregamento,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60.0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              style: TextStyle(color: appBarFg, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: 'Buscar aluno por nome...',
                hintStyle: TextStyle(color: appBarFg.withOpacity(0.72)),
                prefixIcon: Icon(Icons.search_rounded, color: appBarFg),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: Icon(Icons.clear_rounded, color: appBarFg),
                  onPressed: () => setState(() => _searchQuery = ''),
                )
                    : null,
                filled: true,
                fillColor: searchBg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  borderSide: BorderSide(color: searchBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  borderSide: BorderSide(color: searchBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  borderSide: BorderSide(color: appBarFg.withOpacity(0.75), width: 1.2),
                ),
              ),
              onChanged: (value) {
                if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                  setState(() => _searchQuery = value);
                });
              },
            ),
          ),
        ),
      ),
      body: _isLoading || _carregandoPermissoes
          ? Center(child: CircularProgressIndicator(color: t.primary))
          : _hasError
          ? _buildErrorView()
          : _alunosCache.isEmpty
          ? _buildEmptyView()
          : alunosFiltrados.isEmpty
          ? _buildNoSearchResultsView()
          : Column(
        children: [
          _buildResumoAlunosHeader(alunosFiltrados.length),
          StreamBuilder<int>(
            stream: _syncService.pendingCountStream,
            initialData: _syncService.currentPendingCount,
            builder: (context, snapshot) => GlobalSyncCounter(pendingCount: snapshot.data ?? 0),
          ),
          Expanded(child: _getCurrentView(alunosFiltrados)),
        ],
      ),
    );
  }


  Widget _buildResumoAlunosHeader(int filtrados) {
    final t = context.uai;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
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
            child: Icon(Icons.groups_rounded, color: t.primary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Alunos ativos',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _searchQuery.isEmpty
                      ? '${_alunosCache.length} aluno${_alunosCache.length == 1 ? '' : 's'} nesta turma'
                      : '$filtrados resultado${filtrados == 1 ? '' : 's'} para a busca',
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (!_isOnline)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: t.warning.withOpacity(0.12),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: t.warning.withOpacity(0.20)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.wifi_off_rounded, size: 13, color: t.warning),
                  const SizedBox(width: 4),
                  Text(
                    'Offline',
                    style: TextStyle(
                      color: t.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
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

  Widget _buildListView(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return RefreshIndicator(
      color: context.uai.primary,
      backgroundColor: context.uai.surface,
      onRefresh: _forcarRecarregamento,
      child: ListView.builder(
        key: const ValueKey('listView'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 18),
        itemCount: docs.length,
        itemBuilder: (context, index) => _buildAlunoListCard(docs[index]),
      ),
    );
  }

  Widget _buildGridView(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return RefreshIndicator(
      color: context.uai.primary,
      backgroundColor: context.uai.surface,
      onRefresh: _forcarRecarregamento,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final crossAxisCount = width >= 1100
              ? 5
              : width >= 850
              ? 4
              : width >= 620
              ? 3
              : 2;

          return GridView.builder(
            key: const ValueKey('gridView'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: width < 390 ? 0.72 : 0.78,
            ),
            itemCount: docs.length,
            itemBuilder: (context, index) => _buildAlunoGridCard(docs[index]),
          );
        },
      ),
    );
  }

  Widget _buildCompactView(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return RefreshIndicator(
      color: context.uai.primary,
      backgroundColor: context.uai.surface,
      onRefresh: _forcarRecarregamento,
      child: ListView.builder(
        key: const ValueKey('compactView'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 18),
        itemCount: docs.length,
        itemBuilder: (context, index) => _buildAlunoCompactCard(docs[index]),
      ),
    );
  }

  Widget _buildAlunoListCard(QueryDocumentSnapshot<Map<String, dynamic>> aluno) {
    final t = context.uai;
    final data = aluno.data();
    final nomeAluno = data['nome'] ?? 'Nome não informado';
    final fotoUrl = data['foto_perfil_aluno'] as String?;
    final idade = _calculateAge(data['data_nascimento']);
    final graduacaoNome = _getGraduacaoNome(data);

    return FutureBuilder<String?>(
      future: _getModifiedSvg(data),
      builder: (context, svgSnapshot) {
        final modifiedSvg = svgSnapshot.data;
        final isLoadingSvg = svgSnapshot.connectionState == ConnectionState.waiting;
        final mostrarCorda = modifiedSvg != null || isLoadingSvg;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius - 5),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _abrirDetalhesAluno(aluno.id),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(t.cardRadius - 5),
                  border: Border.all(color: t.border),
                  boxShadow: t.softShadow,
                ),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        SizedBox(
                          width: 92,
                          height: 92,
                          child: fotoUrl != null && fotoUrl.isNotEmpty
                              ? CachedNetworkImage(
                            imageUrl: fotoUrl,
                            fit: BoxFit.cover,
                            errorWidget: (c, u, e) => _placeholderIcon(),
                          )
                              : _placeholderIcon(),
                        ),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 23,
                            color: t.primary.withOpacity(0.92),
                            child: Center(
                              child: Text(
                                '$idade ANOS',
                                style: TextStyle(
                                  color: _readableOn(t.primary),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nomeAluno,
                              style: TextStyle(
                                color: t.textPrimary,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w900,
                                height: 1.15,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (graduacaoNome.isNotEmpty && graduacaoNome != 'SEM GRADUAÇÃO') ...[
                              const SizedBox(height: 5),
                              Text(
                                graduacaoNome,
                                style: TextStyle(
                                  color: t.textSecondary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 7),
                            SyncIndicator(
                              isPending: _syncService.isDocumentPending(aluno),
                              isCompact: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (mostrarCorda)
                      Container(
                        width: 66,
                        padding: const EdgeInsets.only(right: 8),
                        child: isLoadingSvg
                            ? Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: t.primary,
                          ),
                        )
                            : SvgPicture.string(modifiedSvg!, height: 62),
                      ),
                    SizedBox(width: 6),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlunoGridCard(QueryDocumentSnapshot<Map<String, dynamic>> aluno) {
    final t = context.uai;
    final data = aluno.data();
    final nomeAluno = data['nome'] ?? 'Nome não informado';
    final fotoUrl = data['foto_perfil_aluno'] as String?;
    final idade = _calculateAge(data['data_nascimento']);
    final graduacaoNome = _getGraduacaoNome(data);

    return FutureBuilder<String?>(
      future: _getModifiedSvg(data),
      builder: (context, svgSnapshot) {
        final modifiedSvg = svgSnapshot.data;
        final isLoadingSvg = svgSnapshot.connectionState == ConnectionState.waiting;
        final mostrarCorda = modifiedSvg != null || isLoadingSvg;

        return Material(
          color: t.card,
          borderRadius: BorderRadius.circular(t.cardRadius - 5),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _abrirDetalhesAluno(aluno.id),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(t.cardRadius - 5),
                border: Border.all(color: t.border),
                boxShadow: t.softShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: fotoUrl != null && fotoUrl.isNotEmpty
                              ? CachedNetworkImage(
                            imageUrl: fotoUrl,
                            fit: BoxFit.cover,
                            errorWidget: (c, u, e) => _placeholderIcon(size: 74),
                          )
                              : _placeholderIcon(size: 74),
                        ),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 27,
                            color: t.primary.withOpacity(0.92),
                            child: Center(
                              child: Text(
                                '$idade ANOS',
                                style: TextStyle(
                                  color: _readableOn(t.primary),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(11),
                    color: t.card,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                nomeAluno.toUpperCase(),
                                style: TextStyle(
                                  color: t.textPrimary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  height: 1.15,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (graduacaoNome.isNotEmpty && graduacaoNome != 'SEM GRADUAÇÃO') ...[
                                const SizedBox(height: 4),
                                Text(
                                  graduacaoNome,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: t.textSecondary,
                                    fontWeight: FontWeight.w600,
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
                        if (mostrarCorda) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 38,
                            height: 46,
                            child: isLoadingSvg
                                ? Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: t.primary,
                              ),
                            )
                                : SvgPicture.string(modifiedSvg!, height: 44),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlunoCompactCard(QueryDocumentSnapshot<Map<String, dynamic>> aluno) {
    final t = context.uai;
    final data = aluno.data();
    final nomeAluno = data['nome'] ?? 'Nome não informado';
    final fotoUrl = data['foto_perfil_aluno'] as String?;

    return FutureBuilder<String?>(
      future: _getModifiedSvg(data),
      builder: (context, svgSnapshot) {
        final modifiedSvg = svgSnapshot.data;
        final isLoadingSvg = svgSnapshot.connectionState == ConnectionState.waiting;
        final mostrarCorda = modifiedSvg != null || isLoadingSvg;

        return Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Material(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius - 8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _abrirDetalhesAluno(aluno.id),
              child: Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(t.cardRadius - 8),
                  border: Border.all(color: t.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: t.cardAlt),
                      child: fotoUrl != null && fotoUrl.isNotEmpty
                          ? ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: fotoUrl,
                          fit: BoxFit.cover,
                          errorWidget: (c, u, e) => Icon(Icons.person_rounded, size: 28, color: t.textMuted),
                        ),
                      )
                          : Icon(Icons.person_rounded, size: 28, color: t.textMuted),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        nomeAluno,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
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
                    if (mostrarCorda) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 30,
                        height: 38,
                        child: isLoadingSvg
                            ? Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: t.primary,
                          ),
                        )
                            : SvgPicture.string(modifiedSvg!, height: 36),
                      ),
                    ],
                    SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, color: t.textMuted),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _placeholderIcon({double size = 50}) => Center(child: Icon(Icons.person_rounded, size: size, color: context.uai.textMuted));
}
