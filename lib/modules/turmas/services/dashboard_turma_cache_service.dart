import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'package:uai_capoeira/modules/turmas/models/aluno_snapshot_model.dart';

/// Serviço de Cache V2 para o Dashboard de Turmas.
///
/// Baseado na arquitetura de Visual Snapshot, onde os dados pesados
/// são processados no servidor e salvos em subcoleções de cache prontas para a UI.
class DashboardTurmaCacheService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Verifica se o App deve usar a lógica de Cache V2.
  ///
  /// Lê a flag `usar_dashboard_cache_v2` em `configuracoes_sistema/mobile_flags`.
  Future<bool> usarCacheV2() async {
    try {
      final doc = await _firestore
          .collection('configuracoes_sistema')
          .doc('mobile_flags')
          .get(const GetOptions(source: Source.serverAndCache));

      if (!doc.exists) return false;

      final data = doc.data();
      return data?['usar_dashboard_cache_v2'] == true;
    } catch (e) {
      debugPrint('⚠️ Erro ao verificar feature flag Cache V2: $e');
      return false;
    }
  }

  /// Carrega o documento de metadados do dashboard (resumo geral).
  Future<Map<String, dynamic>?> carregarMeta(
    String turmaId, {
    bool forceServer = false,
  }) async {
    try {
      final doc = await _firestore
          .collection('turmas')
          .doc(turmaId)
          .collection('dashboard_cache')
          .doc('meta')
          .get(
            GetOptions(
              source: forceServer ? Source.server : Source.serverAndCache,
            ),
          );

      return doc.exists ? doc.data() : null;
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar meta do cache: $e');
      return null;
    }
  }

  /// Carrega o documento de distribuições (dados para gráficos).
  Future<Map<String, dynamic>?> carregarDistribuicoes(
    String turmaId, {
    bool forceServer = false,
  }) async {
    try {
      final doc = await _firestore
          .collection('turmas')
          .doc(turmaId)
          .collection('dashboard_cache')
          .doc('distribuicoes')
          .get(
            GetOptions(
              source: forceServer ? Source.server : Source.serverAndCache,
            ),
          );

      return doc.exists ? doc.data() : null;
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar distribuições do cache: $e');
      return null;
    }
  }

  /// Carrega a lista de alunos da subcoleção de cache de forma estática (get).
  Future<List<Map<String, dynamic>>> carregarAlunosCache(
    String turmaId, {
    String orderBy = 'nome_busca',
    bool descending = false,
    bool forceServer = false,
  }) async {
    try {
      final query = _firestore
          .collection('turmas')
          .doc(turmaId)
          .collection('dashboard_cache_alunos')
          .orderBy(orderBy, descending: descending);

      final snapshot = await query.get(
        GetOptions(source: forceServer ? Source.server : Source.serverAndCache),
      );

      return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar alunos do cache: $e');
      return [];
    }
  }

  /// Carrega a lista de alunos da subcoleção de cache já tipada no modelo AlunoSnapshotModel.
  Future<List<AlunoSnapshotModel>> carregarAlunosSnapshot(
    String turmaId, {
    String orderBy = 'nome_busca',
    bool descending = false,
    bool forceServer = false,
  }) async {
    try {
      final query = _firestore
          .collection('turmas')
          .doc(turmaId)
          .collection('dashboard_cache_alunos')
          .orderBy(orderBy, descending: descending);

      final snapshot = await query.get(
        GetOptions(source: forceServer ? Source.server : Source.serverAndCache),
      );

      return snapshot.docs
          .map((doc) => AlunoSnapshotModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar snapshots de alunos: $e');
      return [];
    }
  }

  /// Retorna um stream para a subcoleção de cache de alunos.
  Stream<QuerySnapshot<Map<String, dynamic>>> streamAlunosCache(
    String turmaId, {
    String orderBy = 'nome_busca',
    bool descending = false,
  }) {
    return _firestore
        .collection('turmas')
        .doc(turmaId)
        .collection('dashboard_cache_alunos')
        .orderBy(orderBy, descending: descending)
        .snapshots();
  }

  /// Chama a Cloud Function para reconstruir o cache da turma.
  Future<Map<String, dynamic>> reconstruirCache(
    String turmaId, {
    bool force = false,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('reconstruirDashboardTurmaCache')
          .call(<String, dynamic>{'turmaId': turmaId, 'force': force});

      return Map<String, dynamic>.from(result.data as Map);
    } catch (e) {
      debugPrint('⚠️ Erro ao reconstruir cache no servidor: $e');
      return {
        "success": false,
        "message": "Function indisponível ou não implementada",
      };
    }
  }
}
