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

  // ═══════════════════════════════════════════════════════════
  // INICIALIZAR HIVE
  // ═══════════════════════════════════════════════════════════
  Future<void> _initHive() async {
    if (_boxAberto) return;

    try {
      final appDocumentDir =
      await path_provider.getApplicationDocumentsDirectory();

      // Evita erro caso outro serviço já tenha inicializado o Hive.
      if (!Hive.isBoxOpen(_boxName)) {
        Hive.init(appDocumentDir.path);
      }

      _box = await Hive.openBox(_boxName);
      _boxAberto = true;
      debugPrint('📦 Hive inicializado com sucesso');
    } catch (e) {
      debugPrint('❌ Erro ao inicializar Hive: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // VERIFICAR INTERNET
  // ═══════════════════════════════════════════════════════════
  Future<bool> temInternet() async {
    try {
      final connectivityResult = await _connectivity.checkConnectivity();

      // Compatível com versões que retornam ConnectivityResult
      // e versões que retornam List<ConnectivityResult>.
      if (connectivityResult is List<ConnectivityResult>) {
        return !connectivityResult.contains(ConnectivityResult.none);
      }

      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      debugPrint('Erro ao verificar internet: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // VERIFICAR SE PODE USAR CACHE
  // ═══════════════════════════════════════════════════════════
  Future<bool> _podeUsarCache() async {
    if (_academiasCache.isEmpty) return false;
    if (_ultimoCacheAcademias == null) return false;

    final temInternetAgora = await temInternet();

    if (temInternetAgora) {
      final cacheValido =
          DateTime.now().difference(_ultimoCacheAcademias!) <=
              _cacheValidadeOnline;

      debugPrint('📱 Com internet - cache ${cacheValido ? 'válido' : 'expirado'}');
      return cacheValido;
    } else {
      debugPrint('📴 Sem internet - usando cache mesmo antigo');
      return true;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // SALVAR NO DISCO (HIVE)
  // ═══════════════════════════════════════════════════════════
  Future<void> _salvarNoDisco(List<Map<String, dynamic>> academias) async {
    try {
      await _initHive();

      await _box.put('academias', academias);
      await _box.put('timestamp', DateTime.now().toIso8601String());

      debugPrint('💾 Dados salvos no disco (${academias.length} academias)');
    } catch (e) {
      debugPrint('❌ Erro ao salvar no disco: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // CARREGAR DO DISCO (HIVE)
  // ═══════════════════════════════════════════════════════════
  Future<List<Map<String, dynamic>>> _carregarDoDisco() async {
    try {
      await _initHive();

      final academias = _box.get('academias', defaultValue: []);
      final timestampStr = _box.get('timestamp');

      if (academias is! List || academias.isEmpty) {
        debugPrint('📭 Nenhum dado encontrado no disco');
        return [];
      }

      final List<Map<String, dynamic>> academiasConvertidas = [];

      for (final item in academias) {
        if (item is Map) {
          academiasConvertidas.add(Map<String, dynamic>.from(item));
        }
      }

      _academiasCache = academiasConvertidas;

      if (timestampStr != null) {
        try {
          _ultimoCacheAcademias = DateTime.parse(timestampStr.toString());
        } catch (_) {
          _ultimoCacheAcademias = null;
        }
      }

      debugPrint('📀 Dados carregados do disco (${_academiasCache.length} academias)');
      return _academiasCache;
    } catch (e) {
      debugPrint('❌ Erro ao carregar do disco: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // LIMPAR CACHE
  // ═══════════════════════════════════════════════════════════
  Future<void> limparCache() async {
    _academiasCache = [];
    _ultimoCacheAcademias = null;

    try {
      await _initHive();
      await _box.clear();
      debugPrint('🧹 Cache (memória e disco) limpo');
    } catch (e) {
      debugPrint('❌ Erro ao limpar disco: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════
  int _toInt(dynamic valor) {
    if (valor == null) return 0;

    if (valor is int) return valor;
    if (valor is num) return valor.toInt();

    if (valor is String) {
      return int.tryParse(valor.trim()) ?? 0;
    }

    return 0;
  }

  // ═══════════════════════════════════════════════════════════
  // CONTAR TURMAS DA ACADEMIA
  // ═══════════════════════════════════════════════════════════
  Future<int> _contarTurmasAcademia(String academiaId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('turmas')
          .where('academia_id', isEqualTo: academiaId)
          .where('status', isEqualTo: 'ATIVA')
          .get(const GetOptions(source: Source.server));

      return snapshot.docs.length;
    } catch (e) {
      debugPrint('⚠️ Erro ao contar turmas no servidor, tentando cache: $e');

      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('turmas')
            .where('academia_id', isEqualTo: academiaId)
            .where('status', isEqualTo: 'ATIVA')
            .get(const GetOptions(source: Source.cache));

        return snapshot.docs.length;
      } catch (e2) {
        debugPrint('❌ Erro ao contar turmas da academia $academiaId: $e2');
        return 0;
      }
    }
  }

  // ═══════════════════════════════════════════════════════════
  // CONTAR ALUNOS DA ACADEMIA
  //
  // CORREÇÃO:
  // Antes estava contando em alunos.where('academia_id').
  // No seu app as turmas já possuem alunos_ativos, e a tela de turmas
  // carrega corretamente por academia_id. Então a Home deve somar
  // alunos_ativos das turmas ATIVAS da academia.
  // ═══════════════════════════════════════════════════════════
  Future<int> _contarAlunosAcademia(String academiaId) async {
    try {
      final turmasSnapshot = await FirebaseFirestore.instance
          .collection('turmas')
          .where('academia_id', isEqualTo: academiaId)
          .where('status', isEqualTo: 'ATIVA')
          .get(const GetOptions(source: Source.server));

      int total = 0;

      for (final turmaDoc in turmasSnapshot.docs) {
        final data = turmaDoc.data();
        total += _toInt(data['alunos_ativos']);
      }

      debugPrint('👥 Academia $academiaId: total alunos ativos pelas turmas = $total');
      return total;
    } catch (e) {
      debugPrint('⚠️ Erro ao contar alunos pelo servidor, tentando cache: $e');

      try {
        final turmasSnapshot = await FirebaseFirestore.instance
            .collection('turmas')
            .where('academia_id', isEqualTo: academiaId)
            .where('status', isEqualTo: 'ATIVA')
            .get(const GetOptions(source: Source.cache));

        int total = 0;

        for (final turmaDoc in turmasSnapshot.docs) {
          final data = turmaDoc.data();
          total += _toInt(data['alunos_ativos']);
        }

        debugPrint('👥 Academia $academiaId: total alunos ativos pelo cache = $total');
        return total;
      } catch (e2) {
        debugPrint('❌ Erro ao contar alunos da academia $academiaId: $e2');
        return 0;
      }
    }
  }

  // ═══════════════════════════════════════════════════════════
  // PROCESSAR ACADEMIAS
  // ═══════════════════════════════════════════════════════════
  Future<List<Map<String, dynamic>>> _processarAcademias(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) async {
    final List<Map<String, dynamic>> academias = [];

    for (final doc in docs) {
      try {
        final data = doc.data();

        final totalAlunos = await _contarAlunosAcademia(doc.id);

        // Se o campo turmas_count do documento estiver errado ou ausente,
        // conta direto na coleção turmas.
        final turmasCountCampo = _toInt(data['turmas_count']);
        final totalTurmas = turmasCountCampo > 0
            ? turmasCountCampo
            : await _contarTurmasAcademia(doc.id);

        academias.add({
          'id': doc.id,
          'nome': data['nome'] ?? 'Sem nome',
          'cidade': data['cidade'] ?? '',
          'turmas_count': totalTurmas,
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

        debugPrint(
          '🏫 ${data['nome'] ?? doc.id} => alunos: $totalAlunos | turmas: $totalTurmas',
        );
      } catch (e) {
        debugPrint('Erro ao processar academia ${doc.id}: $e');
        continue;
      }
    }

    return academias;
  }

  // ═══════════════════════════════════════════════════════════
  // CARREGAR ACADEMIAS DO USUÁRIO
  // ═══════════════════════════════════════════════════════════
  Future<List<Map<String, dynamic>>> carregarAcademiasComAlunos(
      String? userId, {
        bool forcarAtualizacao = false,
      }) async {
    if (userId == null || userId.isEmpty) {
      debugPrint('❌ userId é nulo ou vazio');
      return [];
    }

    final temInternetAgora = await temInternet();

    // Se for forçar atualização, ignora cache em memória e disco.
    if (!forcarAtualizacao) {
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

        if (!temInternetAgora) {
          debugPrint('📴 Modo offline - usando cache do disco');
          return dadosDisco;
        }

        // Com internet, só usa cache do disco se ainda estiver válido.
        if (await _podeUsarCache()) {
          debugPrint('✅ Cache do disco ainda válido');
          return dadosDisco;
        }

        debugPrint('♻️ Cache do disco expirado. Buscando servidor...');
      }
    } else {
      debugPrint('🔄 Forçando atualização das academias no servidor...');
    }

    if (!temInternetAgora) {
      final dadosDiscoForcado = await _carregarDoDisco();

      if (dadosDiscoForcado.isNotEmpty) {
        debugPrint('⚠️ Sem internet - usando cache do disco');
        return dadosDiscoForcado;
      }

      debugPrint('❌ Sem internet e sem cache - lista vazia');
      return [];
    }

    debugPrint('🌐 Carregando academias do servidor para usuário: $userId');

    try {
      final academiasSnapshot = await FirebaseFirestore.instance
          .collection('academias')
          .where('status', isEqualTo: 'ativa')
          .where('professores_ids', arrayContains: userId)
          .get(const GetOptions(source: Source.server));

      debugPrint('📊 Encontradas ${academiasSnapshot.docs.length} academias');

      final academias = await _processarAcademias(academiasSnapshot.docs);

      _academiasCache = academias;
      _ultimoCacheAcademias = DateTime.now();

      await _salvarNoDisco(academias);

      debugPrint('✅ Cache atualizado com ${academias.length} academias');
      return academias;
    } catch (e) {
      debugPrint('❌ Erro ao carregar do servidor: $e');

      if (_academiasCache.isNotEmpty) {
        debugPrint('⚠️ Usando cache em memória como fallback');
        return _academiasCache;
      }

      final dadosDisco = await _carregarDoDisco();

      if (dadosDisco.isNotEmpty) {
        debugPrint('⚠️ Usando cache do disco como fallback');
        return dadosDisco;
      }

      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // CARREGAR ACADEMIAS FORÇANDO ATUALIZAÇÃO
  // ═══════════════════════════════════════════════════════════
  Future<List<Map<String, dynamic>>> recarregarAcademias(String? userId) async {
    await limparCache();
    return carregarAcademiasComAlunos(
      userId,
      forcarAtualizacao: true,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // OBTER ESTATÍSTICAS DO CACHE
  // ═══════════════════════════════════════════════════════════
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

  // ═══════════════════════════════════════════════════════════
  // VERIFICAR SE USUÁRIO TEM ACADEMIAS
  // ═══════════════════════════════════════════════════════════
  Future<bool> usuarioTemAcademias(String userId) async {
    try {
      final snapshotServer = await FirebaseFirestore.instance
          .collection('academias')
          .where('status', isEqualTo: 'ativa')
          .where('professores_ids', arrayContains: userId)
          .limit(1)
          .get(const GetOptions(source: Source.server));

      if (snapshotServer.docs.isNotEmpty) return true;

      final snapshotCache = await FirebaseFirestore.instance
          .collection('academias')
          .where('status', isEqualTo: 'ativa')
          .where('professores_ids', arrayContains: userId)
          .limit(1)
          .get(const GetOptions(source: Source.cache));

      return snapshotCache.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Erro ao verificar academias do usuário: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // BUSCAR UMA ACADEMIA ESPECÍFICA
  // ═══════════════════════════════════════════════════════════
  Future<Map<String, dynamic>?> buscarAcademia(String academiaId) async {
    try {
      final academiaCache = _academiasCache.firstWhere(
            (a) => a['id'] == academiaId,
        orElse: () => <String, dynamic>{},
      );

      if (academiaCache.isNotEmpty) {
        debugPrint('📦 Academia encontrada no cache em memória');
        return academiaCache;
      }
    } catch (_) {}

    try {
      await _initHive();

      final academiasDisco = _box.get('academias', defaultValue: []);

      if (academiasDisco is List) {
        for (final academia in academiasDisco) {
          if (academia is Map && academia['id'] == academiaId) {
            debugPrint('💿 Academia encontrada no cache do disco');
            return Map<String, dynamic>.from(academia);
          }
        }
      }
    } catch (_) {}

    try {
      debugPrint('🌐 Buscando academia no servidor: $academiaId');

      final doc = await FirebaseFirestore.instance
          .collection('academias')
          .doc(academiaId)
          .get(const GetOptions(source: Source.server));

      if (!doc.exists) return null;

      final data = doc.data()!;
      final totalAlunos = await _contarAlunosAcademia(academiaId);

      final turmasCountCampo = _toInt(data['turmas_count']);
      final totalTurmas = turmasCountCampo > 0
          ? turmasCountCampo
          : await _contarTurmasAcademia(academiaId);

      final academia = {
        'id': doc.id,
        'nome': data['nome'] ?? 'Sem nome',
        'cidade': data['cidade'] ?? '',
        'turmas_count': totalTurmas,
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

      final index = _academiasCache.indexWhere((a) => a['id'] == academiaId);

      if (index >= 0) {
        _academiasCache[index] = academia;
      } else {
        _academiasCache.add(academia);
      }

      _ultimoCacheAcademias = DateTime.now();
      await _salvarNoDisco(_academiasCache);

      return academia;
    } catch (e) {
      debugPrint('Erro ao buscar academia: $e');
      return null;
    }
  }
}
