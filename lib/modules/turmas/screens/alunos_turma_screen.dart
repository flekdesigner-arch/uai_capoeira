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

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance()).abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation(((hsl.saturation + 0.10).clamp(0.0, 1.0)).toDouble())
        .toColor();
  }

  Color _capacidadeColor(double porcentagem) {
    if (porcentagem >= 0.90) return context.uai.error;
    if (porcentagem >= 0.70) return context.uai.warning;
    return context.uai.success;
  }

  int _parseInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
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
    Icons.view_list_rounded,
    Icons.warning_amber_rounded,
    Icons.workspace_premium_rounded,
    Icons.format_list_bulleted_rounded,
  ];
  final List<String> _viewModeTooltips = [
    'Visual principal',
    'Filtrar por Indicadores',
    'Filtrar por Graduação',
    'Lista compacta',
  ];

  String? _indicadorExpandidoKey;
  String? _graduacaoExpandidaKey;

  Map<String, bool> _permissoes = {};
  bool _carregandoPermissoes = true;

  final Map<String, Map<String, dynamic>> _graduacoesCache = {};
  final Map<String, String> _svgCache = {};
  final Map<String, bool> _graduacaoValidaCache = {};

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _alunosCache = [];
  int _capacidadeMaximaTurma = 0;

  bool _indicadoresAusenciaAtivos = true;
  bool _mostrarTextoUltimaPresenca = true;
  List<Map<String, dynamic>> _faixasIndicadoresAusencia = const [
    {'ate_dias': 3, 'cor': '#2196F3', 'label': 'Frequente'},
    {'ate_dias': 6, 'cor': '#4CAF50', 'label': 'Regular'},
    {'ate_dias': 12, 'cor': '#FFC107', 'label': 'Atenção'},
    {'ate_dias': 24, 'cor': '#FF9800', 'label': 'Ausente'},
    {'ate_dias': 35, 'cor': '#FF5722', 'label': 'Muito ausente'},
    {'ate_dias': 9999, 'cor': '#F44336', 'label': 'Risco de inatividade'},
  ];

  bool _isLoading = true;
  bool _hasError = false;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _alunosSubscription;

  @override
  void initState() {
    super.initState();
    _carregarPermissoes();
    _loadSvg();
    _preloadGraduacoes();
    _carregarInfoTurma();
    _carregarConfiguracoesIndicadoresAusencia();
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
      await _carregarInfoTurma();
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

  Future<void> _carregarInfoTurma() async {
    try {
      DocumentSnapshot<Map<String, dynamic>> turmaDoc;

      try {
        turmaDoc = await _firestore
            .collection('turmas')
            .doc(widget.turmaId)
            .get(const GetOptions(source: Source.cache));

        if (!turmaDoc.exists && _isOnline) {
          turmaDoc = await _firestore
              .collection('turmas')
              .doc(widget.turmaId)
              .get(const GetOptions(source: Source.server));
        }
      } catch (_) {
        turmaDoc = await _firestore
            .collection('turmas')
            .doc(widget.turmaId)
            .get(const GetOptions(source: Source.server));
      }

      if (!mounted || !turmaDoc.exists) return;

      final data = turmaDoc.data() ?? {};
      setState(() {
        _capacidadeMaximaTurma = _parseInt(data['capacidade_maxima'], 0);
      });
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar capacidade da turma: $e');
    }
  }


  Future<void> _carregarConfiguracoesIndicadoresAusencia() async {
    try {
      DocumentSnapshot<Map<String, dynamic>> doc;

      try {
        doc = await _firestore
            .collection('configuracoes_sistema')
            .doc('indicadores_ausencia')
            .get(const GetOptions(source: Source.cache));

        if (!doc.exists && _isOnline) {
          doc = await _firestore
              .collection('configuracoes_sistema')
              .doc('indicadores_ausencia')
              .get(const GetOptions(source: Source.server));
        }
      } catch (_) {
        doc = await _firestore
            .collection('configuracoes_sistema')
            .doc('indicadores_ausencia')
            .get(const GetOptions(source: Source.server));
      }

      if (!mounted || !doc.exists) return;

      final data = doc.data() ?? {};
      final faixasRaw = data['faixas'];

      final faixas = <Map<String, dynamic>>[];
      if (faixasRaw is List) {
        for (final item in faixasRaw) {
          if (item is Map) {
            final ateDias = _parseInt(item['ate_dias'], -1);
            final cor = item['cor']?.toString().trim() ?? '';
            final label = item['label']?.toString().trim() ?? '';

            if (ateDias >= 0 && cor.isNotEmpty) {
              faixas.add({
                'ate_dias': ateDias,
                'cor': cor,
                'label': label.isEmpty ? 'Indicador' : label,
              });
            }
          }
        }
      }

      faixas.sort((a, b) {
        final aDias = _parseInt(a['ate_dias'], 0);
        final bDias = _parseInt(b['ate_dias'], 0);
        return aDias.compareTo(bDias);
      });

      setState(() {
        _indicadoresAusenciaAtivos = data['ativo'] != false;
        _mostrarTextoUltimaPresenca =
            data['mostrar_texto_ultima_presenca'] != false;

        if (faixas.isNotEmpty) {
          _faixasIndicadoresAusencia = faixas;
        }
      });

      debugPrint(
        '✅ Configuração de indicadores carregada na tela de alunos: '
            '${_faixasIndicadoresAusencia.length} faixas',
      );
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar indicadores de ausência: $e');
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


  DateTime? _normalizarDataUltimaPresenca(dynamic value) {
    if (value == null) return null;

    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;

    if (value is String) {
      final texto = value.trim();
      if (texto.isEmpty) return null;

      final iso = DateTime.tryParse(texto);
      if (iso != null) return iso;

      final partes = texto.split('/');
      if (partes.length == 3) {
        final dia = int.tryParse(partes[0]);
        final mes = int.tryParse(partes[1]);
        final ano = int.tryParse(partes[2]);
        if (dia != null && mes != null && ano != null) {
          return DateTime(ano, mes, dia);
        }
      }
    }

    return null;
  }

  DateTime? _extrairUltimaPresenca(Map<String, dynamic> data) {
    const camposPossiveis = [
      'ultimo_dia_presente',
      'ultimoDiaPresente',
      'ultima_presenca',
      'ultimaPresenca',
      'data_ultima_presenca',
      'dataUltimaPresenca',
      'ultima_presenca_data',
      'ultimaPresencaData',
      'last_presence',
      'lastPresence',
    ];

    for (final campo in camposPossiveis) {
      final dataPresenca = _normalizarDataUltimaPresenca(data[campo]);
      if (dataPresenca != null) return dataPresenca;
    }

    return null;
  }

  int? _diasSemPresenca(Map<String, dynamic> data) {
    final dataUltimaPresenca = _extrairUltimaPresenca(data);
    if (dataUltimaPresenca == null) return null;

    final hoje = DateTime.now();
    final hojeLimpo = DateTime(hoje.year, hoje.month, hoje.day);
    final ultimaLimpa = DateTime(
      dataUltimaPresenca.year,
      dataUltimaPresenca.month,
      dataUltimaPresenca.day,
    );

    final dias = hojeLimpo.difference(ultimaLimpa).inDays;
    return dias < 0 ? 0 : dias;
  }

  Color _colorFromHexSeguro(String? hexColor, Color fallback) {
    if (hexColor == null || hexColor.trim().isEmpty) return fallback;

    try {
      final cleaned = hexColor.replaceAll('#', '').trim();

      if (cleaned.length == 6) {
        return Color(int.parse('FF$cleaned', radix: 16));
      }

      if (cleaned.length == 8) {
        return Color(int.parse(cleaned, radix: 16));
      }
    } catch (_) {}

    return fallback;
  }

  Map<String, dynamic>? _faixaAusenciaPorDias(int? dias) {
    if (dias == null || _faixasIndicadoresAusencia.isEmpty) return null;

    final ordenadas = [..._faixasIndicadoresAusencia];
    ordenadas.sort((a, b) {
      final aDias = _parseInt(a['ate_dias'], 0);
      final bDias = _parseInt(b['ate_dias'], 0);
      return aDias.compareTo(bDias);
    });

    for (final faixa in ordenadas) {
      final ateDias = _parseInt(faixa['ate_dias'], 9999);
      if (dias <= ateDias) return faixa;
    }

    return ordenadas.last;
  }

  Color _corAusenciaPorDias(int? dias) {
    if (dias == null) return context.uai.textMuted;

    final faixa = _faixaAusenciaPorDias(dias);
    return _colorFromHexSeguro(
      faixa?['cor']?.toString(),
      dias <= 3
          ? Colors.blue
          : dias <= 6
          ? Colors.green
          : dias <= 12
          ? Colors.amber
          : dias <= 24
          ? Colors.orange
          : dias <= 35
          ? Colors.deepOrange
          : Colors.red,
    );
  }

  String _labelAusenciaPorDias(int? dias) {
    final faixa = _faixaAusenciaPorDias(dias);
    final label = faixa?['label']?.toString().trim() ?? '';
    return label.isEmpty ? 'Indicador' : label;
  }

  String _textoAusenciaPorDias(int? dias) {
    if (dias == null) return '?';
    if (dias <= 0) return 'HOJ';
    return '${dias}d';
  }

  String _descricaoAusenciaPorDias(int? dias) {
    if (dias == null) return 'Sem registro de última presença';
    if (dias <= 0) return 'Última presença hoje';
    if (dias == 1) return 'Última presença há 1 dia';
    return 'Última presença há $dias dias';
  }

  Widget _buildIndicadorAusencia(
      Map<String, dynamic> data, {
        bool cantoCard = false,
      }) {
    if (!_indicadoresAusenciaAtivos) return const SizedBox.shrink();

    final dias = _diasSemPresenca(data);
    final cor = _corAusenciaPorDias(dias);
    const tamanho = 46.0;

    final badge = Container(
      width: tamanho,
      height: tamanho,
      decoration: BoxDecoration(
        color: cor.withOpacity(0.92),
        borderRadius: cantoCard
            ? const BorderRadius.only(bottomLeft: Radius.circular(999))
            : BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: cor.withOpacity(0.28),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );

    return Tooltip(
      message: _descricaoAusenciaPorDias(dias),
      child: badge,
    );
  }

  Widget _buildLinhaUltimaPresenca(Map<String, dynamic> data) {
    if (!_indicadoresAusenciaAtivos || !_mostrarTextoUltimaPresenca) {
      return const SizedBox.shrink();
    }

    final dias = _diasSemPresenca(data);
    final cor = _corAusenciaPorDias(dias);

    return Row(
      children: [
        Icon(Icons.event_available_rounded, size: 13, color: cor),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            _descricaoAusenciaPorDias(dias),
            style: TextStyle(
              color: cor,
              fontSize: 10.8,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
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
      'nivel_graduacao': data['nivel_graduacao'] ?? data['nivel'] ?? data['ordem'] ?? 9999,
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
        title: _buildAppBarTitle(
          appBarFg: appBarFg,
          appBarBg: appBarBg,
        ),
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        actions: [
          IconButton(icon: Icon(_viewModeIcons[_viewMode], color: appBarFg), tooltip: _viewModeTooltips[_viewMode], onPressed: () => setState(() => _viewMode = (_viewMode + 1) % 4)),
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxSearchWidth =
              constraints.maxWidth >= 1200 ? 1180.0 : double.infinity;

              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxSearchWidth),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: TextField(
                      style: TextStyle(
                        color: appBarFg,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Buscar aluno por nome...',
                        hintStyle: TextStyle(color: appBarFg.withOpacity(0.72)),
                        prefixIcon: Icon(Icons.search_rounded, color: appBarFg),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                          icon: Icon(Icons.clear_rounded, color: appBarFg),
                          onPressed: () =>
                              setState(() => _searchQuery = ''),
                        )
                            : null,
                        filled: true,
                        fillColor: searchBg,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
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
                          borderSide: BorderSide(
                            color: appBarFg.withOpacity(0.75),
                            width: 1.2,
                          ),
                        ),
                      ),
                      onChanged: (value) {
                        if (_searchDebounce?.isActive ?? false) {
                          _searchDebounce!.cancel();
                        }
                        _searchDebounce =
                            Timer(const Duration(milliseconds: 300), () {
                              setState(() => _searchQuery = value);
                            });
                      },
                    ),
                  ),
                ),
              );
            },
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


  Widget _buildAppBarTitle({
    required Color appBarFg,
    required Color appBarBg,
  }) {
    final t = context.uai;
    final alunosAtivos = _alunosCache.length;
    final capacidade = _capacidadeMaximaTurma;
    final temCapacidade = capacidade > 0;
    final value = temCapacidade
        ? (alunosAtivos / capacidade).clamp(0.0, 1.0)
        : 0.0;
    final porcentagem = temCapacidade ? value : 0.0;
    final barColor = _capacidadeColor(porcentagem);
    final barraFundo = appBarFg.withOpacity(0.22);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.turmaNome,
                style: TextStyle(
                  fontSize: 16,
                  color: appBarFg,
                  fontWeight: FontWeight.w900,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isOnline ? t.success : t.error,
                border: Border.all(color: appBarFg.withOpacity(0.20)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: temCapacidade ? value : null,
                  minHeight: 6,
                  backgroundColor: barraFundo,
                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              temCapacidade
                  ? '$alunosAtivos/$capacidade'
                  : '$alunosAtivos ativos',
              style: TextStyle(
                color: appBarFg.withOpacity(0.88),
                fontSize: 10.8,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ],
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
        return _buildVisualPrincipalResponsivo(docs);
      case 1:
        return _buildIndicadoresView(docs);
      case 2:
        return _buildGraduacoesView(docs);
      case 3:
        return _buildCompactView(docs);
      default:
        return _buildVisualPrincipalResponsivo(docs);
    }
  }

  int _calcularColunasAlunos(double width) {
    if (width >= 1640) return 5;
    if (width >= 1280) return 4;
    if (width >= 960) return 3;
    if (width >= 720) return 2;
    return 1;
  }

  double _larguraMaximaConteudo(double width) {
    if (width >= 1640) return 1560;
    if (width >= 1280) return 1240;
    if (width >= 960) return 1120;
    return double.infinity;
  }

  Widget _buildVisualPrincipalResponsivo(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final colunas = _calcularColunasAlunos(width);

        if (colunas <= 1) {
          return _buildListView(docs);
        }

        return _buildGridView(docs, crossAxisCount: colunas);
      },
    );
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

  Widget _buildGridView(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
        required int crossAxisCount,
      }) {
    return RefreshIndicator(
      color: context.uai.primary,
      backgroundColor: context.uai.surface,
      onRefresh: _forcarRecarregamento,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final maxWidth = _larguraMaximaConteudo(width);
          final horizontalPadding = width >= 960 ? 18.0 : 12.0;
          final spacing = width >= 1280 ? 14.0 : 12.0;
          final usableWidth = (maxWidth.isFinite ? maxWidth : width) -
              (horizontalPadding * 2) -
              (spacing * (crossAxisCount - 1));
          final tileWidth = usableWidth / crossAxisCount;
          final tileHeight = width >= 1280 ? 104.0 : 100.0;

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: GridView.builder(
                key: ValueKey('gridView_$crossAxisCount'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  8,
                  horizontalPadding,
                  18,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                  childAspectRatio: tileWidth / tileHeight,
                ),
                itemCount: docs.length,
                itemBuilder: (context, index) => _buildAlunoGridCard(docs[index]),
              ),
            ),
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

  int _nivelGraduacaoAluno(String nomeGraduacao) {
    if (nomeGraduacao.trim().isEmpty || nomeGraduacao == 'SEM GRADUAÇÃO') {
      return 999999;
    }

    final direto = _graduacoesCache[nomeGraduacao];
    final normalizado = _graduacoesCache[_graduacaoKey(nomeGraduacao)];
    final data = direto ?? normalizado;

    return _parseInt(data?['nivel_graduacao'], 9999);
  }

  List<_GrupoGraduacaoAlunos> _agruparAlunosPorGraduacao(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    final grupos = <String, _GrupoGraduacaoAlunos>{};

    for (final doc in docs) {
      final data = doc.data();
      final nome = _getGraduacaoNome(data).trim().isEmpty
          ? 'SEM GRADUAÇÃO'
          : _getGraduacaoNome(data).trim();
      final key = _graduacaoKey(nome);
      final ordem = _nivelGraduacaoAluno(nome);

      grupos.putIfAbsent(
        key,
            () => _GrupoGraduacaoAlunos(
          titulo: nome,
          ordem: ordem,
          alunos: [],
        ),
      );

      grupos[key]!.alunos.add(doc);
    }

    final lista = grupos.values.toList();
    lista.sort((a, b) {
      final ordem = a.ordem.compareTo(b.ordem);
      if (ordem != 0) return ordem;
      return a.titulo.compareTo(b.titulo);
    });

    for (final grupo in lista) {
      grupo.alunos.sort((a, b) {
        final nomeA = (a.data()['nome'] ?? '').toString().toLowerCase();
        final nomeB = (b.data()['nome'] ?? '').toString().toLowerCase();
        return nomeA.compareTo(nomeB);
      });
    }

    return lista;
  }

  Widget _buildGraduacoesView(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final grupos = _agruparAlunosPorGraduacao(docs);

    return RefreshIndicator(
      color: context.uai.primary,
      backgroundColor: context.uai.surface,
      onRefresh: _forcarRecarregamento,
      child: ListView.builder(
        key: const ValueKey('graduacoesView'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 18),
        itemCount: grupos.length,
        itemBuilder: (context, index) => _buildGraduacaoGrupoCard(grupos[index]),
      ),
    );
  }

  Widget _buildGraduacaoGrupoCard(_GrupoGraduacaoAlunos grupo) {
    final t = context.uai;
    final isSemGraduacao = grupo.titulo == 'SEM GRADUAÇÃO';
    final key = _graduacaoKey(grupo.titulo);
    final expandido = _graduacaoExpandidaKey == key;
    final primeiroAluno = grupo.alunos.isNotEmpty ? grupo.alunos.first.data() : <String, dynamic>{};

    Color corBase = t.associacao;
    final cache = _graduacoesCache[grupo.titulo] ?? _graduacoesCache[key];
    if (cache != null && !isSemGraduacao) {
      corBase = _colorFromHexSeguro(cache['hex_cor1']?.toString(), t.associacao);
    }
    final cor = _ensureVisible(corBase, t.card);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius - 4),
        border: Border.all(color: cor.withOpacity(0.20)),
        boxShadow: t.softShadow,
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(t.cardRadius - 4),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                setState(() {
                  _graduacaoExpandidaKey = expandido ? null : key;
                  if (!expandido) _indicadorExpandidoKey = null;
                });
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 58,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isSemGraduacao ? t.cardAlt : cor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cor.withOpacity(0.22)),
                      ),
                      child: isSemGraduacao
                          ? Icon(Icons.workspace_premium_outlined, color: t.textMuted)
                          : FutureBuilder<String?>(
                        future: _getModifiedSvg(primeiroAluno),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cor,
                                ),
                              ),
                            );
                          }

                          final svg = snapshot.data;
                          if (svg == null || svg.isEmpty) {
                            return Icon(Icons.workspace_premium_rounded, color: cor);
                          }

                          return SvgPicture.string(svg, fit: BoxFit.contain);
                        },
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            grupo.titulo,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              height: 1.08,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 7),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: _alunosCache.isEmpty
                                  ? 0
                                  : ((grupo.alunos.length / _alunosCache.length).clamp(0.0, 1.0)).toDouble(),
                              minHeight: 6,
                              backgroundColor: t.border,
                              valueColor: AlwaysStoppedAnimation<Color>(cor),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${grupo.alunos.length} aluno${grupo.alunos.length == 1 ? '' : 's'} nesta graduação',
                            style: TextStyle(
                              color: t.textSecondary,
                              fontSize: 11.2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: expandido ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(Icons.keyboard_arrow_down_rounded, color: cor),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                children: grupo.alunos.map(_buildAlunoCompactCard).toList(),
              ),
            ),
            crossFadeState:
            expandido ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    );
  }

  List<_GrupoIndicadorAlunos> _agruparAlunosPorIndicador(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    final grupos = <String, _GrupoIndicadorAlunos>{};

    for (final doc in docs) {
      final data = doc.data();
      final dias = _diasSemPresenca(data);
      final faixa = _faixaAusenciaPorDias(dias);

      final titulo = dias == null
          ? 'Sem presença registrada'
          : (faixa?['label']?.toString().trim().isNotEmpty == true
          ? faixa!['label'].toString().trim()
          : 'Indicador');

      final ateDias = faixa == null
          ? 999999
          : _parseInt(faixa['ate_dias'], 9999);

      final subtitulo = dias == null
          ? 'Alunos sem data de última presença'
          : ateDias >= 9999
          ? 'Acima das faixas anteriores'
          : 'Até $ateDias dias sem presença';

      final cor = _corAusenciaPorDias(dias);
      final ordem = dias == null ? 999999 : ateDias;
      final key = '$ordem::$titulo';

      grupos.putIfAbsent(
        key,
            () => _GrupoIndicadorAlunos(
          titulo: titulo,
          subtitulo: subtitulo,
          cor: cor,
          ordem: ordem,
          alunos: [],
        ),
      );

      grupos[key]!.alunos.add(doc);
    }

    final lista = grupos.values.toList();
    lista.sort((a, b) {
      final ordem = a.ordem.compareTo(b.ordem);
      if (ordem != 0) return ordem;
      return a.titulo.compareTo(b.titulo);
    });

    for (final grupo in lista) {
      grupo.alunos.sort((a, b) {
        final nomeA = (a.data()['nome'] ?? '').toString().toLowerCase();
        final nomeB = (b.data()['nome'] ?? '').toString().toLowerCase();
        return nomeA.compareTo(nomeB);
      });
    }

    return lista;
  }

  Widget _buildIndicadoresView(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final grupos = _agruparAlunosPorIndicador(docs);

    return RefreshIndicator(
      color: context.uai.primary,
      backgroundColor: context.uai.surface,
      onRefresh: _forcarRecarregamento,
      child: ListView.builder(
        key: const ValueKey('indicadoresView'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 18),
        itemCount: grupos.length,
        itemBuilder: (context, index) => _buildIndicadorGrupoCard(grupos[index]),
      ),
    );
  }

  Widget _buildIndicadorGrupoCard(_GrupoIndicadorAlunos grupo) {
    final t = context.uai;
    final cor = _ensureVisible(grupo.cor, t.card);
    final key = '${grupo.ordem}::${grupo.titulo}';
    final expandido = _indicadorExpandidoKey == key;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(cor.withOpacity(0.05), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius - 4),
        border: Border.all(color: cor.withOpacity(0.22)),
        boxShadow: t.softShadow,
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(t.cardRadius - 4),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                setState(() {
                  _indicadorExpandidoKey = expandido ? null : key;
                  if (!expandido) _graduacaoExpandidaKey = null;
                });
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: cor.withOpacity(0.14),
                        shape: BoxShape.circle,
                        border: Border.all(color: cor.withOpacity(0.32)),
                      ),
                      child: Center(
                        child: Container(
                          width: 15,
                          height: 15,
                          decoration: BoxDecoration(
                            color: grupo.cor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: grupo.cor.withOpacity(0.24),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            grupo.titulo,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              height: 1.08,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            grupo.subtitulo,
                            style: TextStyle(
                              color: t.textSecondary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: cor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: cor.withOpacity(0.22)),
                      ),
                      child: Text(
                        '${grupo.alunos.length}',
                        style: TextStyle(
                          color: cor,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: expandido ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(Icons.keyboard_arrow_down_rounded, color: cor),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                children: grupo.alunos.map(_buildAlunoCompactCard).toList(),
              ),
            ),
            crossFadeState:
            expandido ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    );
  }

  Widget _buildAlunoListCard(QueryDocumentSnapshot<Map<String, dynamic>> aluno) {
    final t = context.uai;
    final data = aluno.data();
    final nomeAluno = (data['nome'] ?? 'Nome não informado').toString();
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
          child: SizedBox(
            height: 92,
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
                  child: Stack(
                    children: [
                      Positioned(
                        top: 0,
                        right: 0,
                        child: _buildIndicadorAusencia(
                          data,
                          cantoCard: true,
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 92,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                fotoUrl != null && fotoUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                  imageUrl: fotoUrl,
                                  fit: BoxFit.cover,
                                  alignment: Alignment.center,
                                  errorWidget: (c, u, e) => _placeholderIcon(),
                                )
                                    : _placeholderIcon(),
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
                          ),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                12,
                                graduacaoNome.isNotEmpty &&
                                    graduacaoNome != 'SEM GRADUAÇÃO'
                                    ? 7
                                    : 10,
                                8,
                                7,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    nomeAluno.toUpperCase(),
                                    style: TextStyle(
                                      color: t.textPrimary,
                                      fontSize: 14.2,
                                      fontWeight: FontWeight.w900,
                                      height: 1.08,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (graduacaoNome.isNotEmpty &&
                                      graduacaoNome != 'SEM GRADUAÇÃO') ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      graduacaoNome,
                                      style: TextStyle(
                                        color: t.textSecondary,
                                        fontSize: 11.2,
                                        fontWeight: FontWeight.w600,
                                        height: 1.05,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  _buildLinhaUltimaPresenca(data),
                                  const SizedBox(height: 3),
                                  SyncIndicator(
                                    isPending: _syncService.isDocumentPending(aluno),
                                    isCompact: true,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (mostrarCorda)
                            SizedBox(
                              width: 58,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Center(
                                  child: isLoadingSvg
                                      ? SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: t.primary,
                                    ),
                                  )
                                      : SvgPicture.string(
                                    modifiedSvg!,
                                    height: 58,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ],
                  ),
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
    final nomeAluno = (data['nome'] ?? 'Nome não informado').toString();
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
          borderRadius: BorderRadius.circular(t.cardRadius - 6),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _abrirDetalhesAluno(aluno.id),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(t.cardRadius - 6),
                border: Border.all(color: t.border),
                boxShadow: t.softShadow,
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    right: 0,
                    child: _buildIndicadorAusencia(
                      data,
                      cantoCard: true,
                    ),
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cardWidth = constraints.maxWidth;
                      final fotoWidth = cardWidth < 340 ? 78.0 : 88.0;
                      final cordaWidth = mostrarCorda
                          ? (cardWidth < 340 ? 42.0 : 50.0)
                          : 0.0;

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: fotoWidth,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                fotoUrl != null && fotoUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                  imageUrl: fotoUrl,
                                  fit: BoxFit.cover,
                                  alignment: Alignment.center,
                                  errorWidget: (c, u, e) =>
                                      _placeholderIcon(size: 42),
                                )
                                    : _placeholderIcon(size: 42),
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    height: 22,
                                    color: t.primary.withOpacity(0.92),
                                    child: Center(
                                      child: Text(
                                        '$idade ANOS',
                                        style: TextStyle(
                                          color: _readableOn(t.primary),
                                          fontSize: 9.8,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                cardWidth < 340 ? 9 : 12,
                                8,
                                6,
                                7,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    nomeAluno.toUpperCase(),
                                    style: TextStyle(
                                      color: t.textPrimary,
                                      fontWeight: FontWeight.w900,
                                      fontSize: cardWidth < 340 ? 12.4 : 13.2,
                                      height: 1.08,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (graduacaoNome.isNotEmpty &&
                                      graduacaoNome != 'SEM GRADUAÇÃO') ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      graduacaoNome,
                                      style: TextStyle(
                                        fontSize: cardWidth < 340 ? 10.2 : 10.8,
                                        color: t.textSecondary,
                                        fontWeight: FontWeight.w600,
                                        height: 1.05,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  _buildLinhaUltimaPresenca(data),
                                  const SizedBox(height: 3),
                                  SyncIndicator(
                                    isPending:
                                    _syncService.isDocumentPending(aluno),
                                    isCompact: true,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (mostrarCorda)
                            SizedBox(
                              width: cordaWidth,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 5),
                                child: Center(
                                  child: isLoadingSvg
                                      ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: t.primary,
                                    ),
                                  )
                                      : SvgPicture.string(
                                    modifiedSvg!,
                                    height: cardWidth < 340 ? 42 : 50,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(width: 4),
                        ],
                      );
                    },
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
                    const SizedBox(width: 4),
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



class _GrupoGraduacaoAlunos {
  final String titulo;
  final int ordem;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> alunos;

  _GrupoGraduacaoAlunos({
    required this.titulo,
    required this.ordem,
    required this.alunos,
  });
}

class _GrupoIndicadorAlunos {
  final String titulo;
  final String subtitulo;
  final Color cor;
  final int ordem;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> alunos;

  _GrupoIndicadorAlunos({
    required this.titulo,
    required this.subtitulo,
    required this.cor,
    required this.ordem,
    required this.alunos,
  });
}
