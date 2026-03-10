import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

class AcademiaCacheService {
  // Cache em memória (rápido)
  List<Map<String, dynamic>> _academiasCache = [];
  DateTime? _ultimoCacheAcademias;
  static const Duration _cacheValidadeOnline = Duration(minutes: 5);

  // Cache persistente com Hive
  static const String _boxName = 'academias_cache';
  late Box _box;
  bool _boxAberto = false;

  final Connectivity _connectivity = Connectivity();

  // ========== INICIALIZAR HIVE ==========
  Future<void> _initHive() async {
    if (_boxAberto) return;

    try {
      // Diretório para armazenar os dados
      final appDocumentDir = await path_provider.getApplicationDocumentsDirectory();
      Hive.init(appDocumentDir.path);

      // Abrir box (ou criar se não existir)
      _box = await Hive.openBox(_boxName);
      _boxAberto = true;
      debugPrint('📦 Hive inicializado com sucesso');
    } catch (e) {
      debugPrint('❌ Erro ao inicializar Hive: $e');
    }
  }

  // ========== VERIFICAR INTERNET ==========
  Future<bool> temInternet() async {
    try {
      var connectivityResult = await _connectivity.checkConnectivity();
      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      debugPrint('Erro ao verificar internet: $e');
      return false;
    }
  }

  // ========== VERIFICAR SE PODE USAR CACHE ==========
  Future<bool> _podeUsarCache() async {
    if (_academiasCache.isEmpty) return false;
    if (_ultimoCacheAcademias == null) return false;

    final temInternetAgora = await temInternet();

    if (temInternetAgora) {
      // COM INTERNET: cache expira em 5 minutos
      final cacheValido = DateTime.now().difference(_ultimoCacheAcademias!) <= _cacheValidadeOnline;
      debugPrint('📱 Com internet - cache ${cacheValido ? 'válido' : 'expirado'}');
      return cacheValido;
    } else {
      // SEM INTERNET: cache NUNCA expira (enquanto app estiver rodando)
      debugPrint('📴 Sem internet - usando cache mesmo antigo');
      return true;
    }
  }

  // ========== SALVAR NO DISCO (HIVE) ==========
  Future<void> _salvarNoDisco(List<Map<String, dynamic>> academias) async {
    try {
      await _initHive();

      // Salva os dados
      await _box.put('academias', academias);
      await _box.put('timestamp', DateTime.now().toIso8601String());

      debugPrint('💾 Dados salvos no disco (${academias.length} academias)');
    } catch (e) {
      debugPrint('❌ Erro ao salvar no disco: $e');
    }
  }

  // ========== CARREGAR DO DISCO (HIVE) ==========
  Future<List<Map<String, dynamic>>> _carregarDoDisco() async {
    try {
      await _initHive();

      final academias = _box.get('academias', defaultValue: []);
      final timestampStr = _box.get('timestamp');

      if (academias.isEmpty) {
        debugPrint('📭 Nenhum dado encontrado no disco');
        return [];
      }

      // Converte para o formato correto
      final List<Map<String, dynamic>> academiasConvertidas = [];
      for (var item in academias) {
        if (item is Map) {
          academiasConvertidas.add(Map<String, dynamic>.from(item));
        }
      }

      // Atualiza o cache em memória
      _academiasCache = academiasConvertidas;
      if (timestampStr != null) {
        _ultimoCacheAcademias = DateTime.parse(timestampStr);
      }

      debugPrint('📀 Dados carregados do disco (${_academiasCache.length} academias)');
      return _academiasCache;

    } catch (e) {
      debugPrint('❌ Erro ao carregar do disco: $e');
      return [];
    }
  }

  // ========== LIMPAR CACHE ==========
  Future<void> limparCache() async {
    _academiasCache = [];
    _ultimoCacheAcademias = null;

    // Limpa também do disco
    try {
      await _initHive();
      await _box.clear();
      debugPrint('🧹 Cache (memória e disco) limpo');
    } catch (e) {
      debugPrint('❌ Erro ao limpar disco: $e');
    }
  }

  // ========== CONTAR ALUNOS DA ACADEMIA ==========
  Future<int> _contarAlunosAcademia(String academiaId) async {
    try {
      // Tenta cache primeiro
      final alunosSnapshot = await FirebaseFirestore.instance
          .collection('alunos')
          .where('academia_id', isEqualTo: academiaId)
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .get(const GetOptions(source: Source.cache));

      return alunosSnapshot.docs.length;
    } catch (e) {
      // Se falhar, tenta servidor
      try {
        final alunosSnapshot = await FirebaseFirestore.instance
            .collection('alunos')
            .where('academia_id', isEqualTo: academiaId)
            .where('status_atividade', isEqualTo: 'ATIVO(A)')
            .get(const GetOptions(source: Source.server));

        return alunosSnapshot.docs.length;
      } catch (e) {
        debugPrint('Erro ao contar alunos: $e');
        return 0;
      }
    }
  }

  // ========== PROCESSAR ACADEMIAS ==========
  Future<List<Map<String, dynamic>>> _processarAcademias(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) async {
    final List<Map<String, dynamic>> academias = [];

    for (var doc in docs) {
      try {
        final data = doc.data();
        final totalAlunos = await _contarAlunosAcademia(doc.id);

        academias.add({
          'id': doc.id,
          'nome': data['nome'] ?? 'Sem nome',
          'cidade': data['cidade'] ?? '',
          'turmas_count': data['turmas_count'] ?? 0,
          'endereco': data['endereco'] ?? '',
          'telefone': data['telefone'] ?? '',
          'whatsapp_url': data['whatsapp_url'] ?? '',
          'logo_url': data['logo_url'] ?? '',
          'modalidade': data['modalidade'] ?? '',
          'professor': data['professor'] ?? '',
          'professores_nomes': data['professores_nomes'] ?? [],
          'professores_ids': data['professores_ids'] ?? [],
          'alunos_count': totalAlunos,
        });
      } catch (e) {
        debugPrint('Erro ao processar academia ${doc.id}: $e');
        continue;
      }
    }

    return academias;
  }

  // ========== CARREGAR ACADEMIAS DO USUÁRIO ==========
  Future<List<Map<String, dynamic>>> carregarAcademiasComAlunos(String? userId) async {
    if (userId == null || userId.isEmpty) {
      debugPrint('❌ userId é nulo ou vazio');
      return [];
    }

    final temInternetAgora = await temInternet();

    // PRIORIDADE 1: Cache em memória válido
    if (_academiasCache.isNotEmpty) {
      final podeUsarCache = await _podeUsarCache();
      if (podeUsarCache) {
        debugPrint('📦 Usando cache em memória (${_academiasCache.length} itens)');
        return _academiasCache;
      }
    }

    // PRIORIDADE 2: Tentar carregar do disco
    final dadosDisco = await _carregarDoDisco();
    if (dadosDisco.isNotEmpty) {
      debugPrint('💿 Cache carregado do disco (${dadosDisco.length} itens)');

      // Se está sem internet, USA SEMPRE o cache do disco (ignora expiração)
      if (!temInternetAgora) {
        debugPrint('📴 Modo offline - usando cache do disco (ignorando expiração)');
        return dadosDisco;
      }

      // Se está com internet, verifica se o cache ainda é válido
      if (await _podeUsarCache()) {
        debugPrint('✅ Cache do disco ainda válido');
        return dadosDisco;
      }
    }

    // PRIORIDADE 3: Se está sem internet e não conseguiu carregar nada, tenta forçar o disco
    if (!temInternetAgora) {
      // Tenta uma última vez carregar do disco (ignorando qualquer erro)
      final dadosDiscoForcado = await _carregarDoDisco();
      if (dadosDiscoForcado.isNotEmpty) {
        debugPrint('⚠️ Forçando uso do cache do disco em modo offline');
        return dadosDiscoForcado;
      }

      debugPrint('❌ Sem internet e sem cache - lista vazia');
      return [];
    }

    debugPrint('🌐 Carregando academias do servidor para usuário: $userId');

    try {
      // Busca academias onde o usuário é professor
      final academiasSnapshot = await FirebaseFirestore.instance
          .collection('academias')
          .where('status', isEqualTo: 'ativa')
          .where('professores_ids', arrayContains: userId)
          .get(const GetOptions(source: Source.server));

      debugPrint('📊 Encontradas ${academiasSnapshot.docs.length} academias');

      // Processa as academias (conta alunos)
      final academias = await _processarAcademias(academiasSnapshot.docs);

      // Atualiza cache em memória
      _academiasCache = academias;
      _ultimoCacheAcademias = DateTime.now();

      // SALVA NO DISCO (persistente)
      await _salvarNoDisco(academias);

      debugPrint('✅ Cache atualizado com ${academias.length} academias');
      return academias;

    } catch (e) {
      debugPrint('❌ Erro ao carregar do servidor: $e');

      // Se falhou mas tem cache em memória, usa
      if (_academiasCache.isNotEmpty) {
        debugPrint('⚠️ Usando cache em memória como fallback');
        return _academiasCache;
      }

      // Se não tem em memória, tenta disco
      if (dadosDisco.isNotEmpty) {
        debugPrint('⚠️ Usando cache do disco como fallback');
        return dadosDisco;
      }

      // Se não tem nada, retorna lista vazia
      return [];
    }
  }

  // ========== CARREGAR ACADEMIAS FORÇANDO ATUALIZAÇÃO ==========
  Future<List<Map<String, dynamic>>> recarregarAcademias(String? userId) async {
    await limparCache();
    return carregarAcademiasComAlunos(userId);
  }

  // ========== OBTER ESTATÍSTICAS DO CACHE ==========
  Future<Map<String, dynamic>> getStatusCache() async {
    final temInternetAgora = await temInternet();

    return {
      'temCacheMemoria': _academiasCache.isNotEmpty,
      'quantidadeMemoria': _academiasCache.length,
      'ultimoCacheMemoria': _ultimoCacheAcademias,
      'cacheMemoriaValido': await _podeUsarCache(),
      'modo': temInternetAgora ? 'online' : 'offline',
      'cacheDisco': _boxAberto ? _box.containsKey('academias') : false,
    };
  }

  // ========== VERIFICAR SE USUÁRIO TEM ACADEMIAS ==========
  Future<bool> usuarioTemAcademias(String userId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('academias')
          .where('status', isEqualTo: 'ativa')
          .where('professores_ids', arrayContains: userId)
          .limit(1)
          .get(const GetOptions(source: Source.cache));

      if (snapshot.docs.isNotEmpty) return true;

      final snapshotServer = await FirebaseFirestore.instance
          .collection('academias')
          .where('status', isEqualTo: 'ativa')
          .where('professores_ids', arrayContains: userId)
          .limit(1)
          .get(const GetOptions(source: Source.server));

      return snapshotServer.docs.isNotEmpty;

    } catch (e) {
      debugPrint('Erro ao verificar academias do usuário: $e');
      return false;
    }
  }

  // ========== BUSCAR UMA ACADEMIA ESPECÍFICA ==========
  Future<Map<String, dynamic>?> buscarAcademia(String academiaId) async {
    // Procura no cache em memória primeiro
    try {
      final academiaCache = _academiasCache.firstWhere(
            (a) => a['id'] == academiaId,
        orElse: () => <String, dynamic>{},
      );

      if (academiaCache.isNotEmpty) {
        debugPrint('📦 Academia encontrada no cache em memória');
        return academiaCache;
      }
    } catch (e) {}

    // Procura no disco
    try {
      await _initHive();
      final academiasDisco = _box.get('academias', defaultValue: []);

      for (var academia in academiasDisco) {
        if (academia['id'] == academiaId) {
          debugPrint('💿 Academia encontrada no cache do disco');
          return Map<String, dynamic>.from(academia);
        }
      }
    } catch (e) {}

    // Se não achou no cache, busca no Firestore
    try {
      debugPrint('🌐 Buscando academia no servidor: $academiaId');

      final doc = await FirebaseFirestore.instance
          .collection('academias')
          .doc(academiaId)
          .get();

      if (!doc.exists) return null;

      final data = doc.data()!;
      final totalAlunos = await _contarAlunosAcademia(academiaId);

      final academia = {
        'id': doc.id,
        'nome': data['nome'] ?? 'Sem nome',
        'cidade': data['cidade'] ?? '',
        'turmas_count': data['turmas_count'] ?? 0,
        'endereco': data['endereco'] ?? '',
        'telefone': data['telefone'] ?? '',
        'whatsapp_url': data['whatsapp_url'] ?? '',
        'logo_url': data['logo_url'] ?? '',
        'modalidade': data['modalidade'] ?? '',
        'professor': data['professor'] ?? '',
        'professores_nomes': data['professores_nomes'] ?? [],
        'professores_ids': data['professores_ids'] ?? [],
        'alunos_count': totalAlunos,
      };

      // Atualiza cache
      _academiasCache.add(academia);
      await _salvarNoDisco(_academiasCache);

      return academia;

    } catch (e) {
      debugPrint('Erro ao buscar academia: $e');
      return null;
    }
  }
}