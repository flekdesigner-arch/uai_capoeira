import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class GraduacaoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'graduacoes';

  // Cache para evitar buscas repetidas
  List<Map<String, dynamic>>? _cacheTodasGraduacoes;
  DateTime? _cacheTimestamp;

  /// Busca todas as graduações
  Future<List<Map<String, dynamic>>> buscarTodasGraduacoes({bool forceRefresh = false}) async {
    // Se tem cache e não passou 5 minutos, usa cache
    if (!forceRefresh &&
        _cacheTodasGraduacoes != null &&
        _cacheTimestamp != null &&
        DateTime.now().difference(_cacheTimestamp!) < const Duration(minutes: 5)) {
      return _cacheTodasGraduacoes!;
    }

    try {
      final snapshot = await _firestore
          .collection(_collection)
          .orderBy('nivel_graduacao')
          .get();

      _cacheTodasGraduacoes = snapshot.docs.map((doc) {
        return {
          'id': doc.id,
          ...doc.data(),
        };
      }).toList();

      _cacheTimestamp = DateTime.now();

      return _cacheTodasGraduacoes!;
    } catch (e) {
      debugPrint('Erro ao buscar graduações: $e');
      return [];
    }
  }

  /// 🔥 NOVO: Busca graduação por ID
  Future<Map<String, dynamic>?> buscarPorId(String id) async {
    try {
      final doc = await _firestore.collection(_collection).doc(id).get();

      if (doc.exists) {
        return {
          'id': doc.id,
          ...doc.data()!,
        };
      }
      return null;
    } catch (e) {
      debugPrint('Erro ao buscar graduação por ID: $e');
      return null;
    }
  }

  /// Busca graduações por tipo (ADULTO/INFANTIL)
  Future<List<Map<String, dynamic>>> buscarGraduacoesPorTipo(String tipo) async {
    try {
      final todas = await buscarTodasGraduacoes();
      return todas.where((g) =>
      g['tipo_publico']?.toString().toUpperCase() == tipo.toUpperCase()
      ).toList();
    } catch (e) {
      debugPrint('Erro ao buscar graduações por tipo: $e');
      return [];
    }
  }

  /// Busca próximas graduações baseado no nível atual
  Future<List<Map<String, dynamic>>> buscarProximasGraduacoes(
      int nivelAtual,
      String tipo,
      ) async {
    try {
      final todas = await buscarGraduacoesPorTipo(tipo);
      return todas.where((g) =>
      (g['nivel_graduacao'] ?? 0) > nivelAtual
      ).toList();
    } catch (e) {
      debugPrint('Erro ao buscar próximas graduações: $e');
      return [];
    }
  }

  /// 🔥 NOVO: Atualiza graduação do aluno
  Future<void> atualizarGraduacaoAluno({
    required String alunoId,
    required String novaGraduacaoId,
    required String novaGraduacaoNome,
    required DateTime dataGraduacao,
    required String eventoId,
  }) async {
    try {
      final alunoRef = _firestore.collection('alunos').doc(alunoId);

      await alunoRef.update({
        'graduacao_atual_id': novaGraduacaoId,
        'graduacao_atual': novaGraduacaoNome,
        'data_ultima_graduacao': Timestamp.fromDate(dataGraduacao),
        'ultimo_evento_graduacao': eventoId,
        'atualizado_em': FieldValue.serverTimestamp(),
      });

      // Adiciona ao histórico
      await _firestore.collection('historico_graduacoes').add({
        'aluno_id': alunoId,
        'aluno_nome': alunoRef,
        'graduacao_antiga_id': null, // Idealmente deveria vir do parâmetro
        'graduacao_nova_id': novaGraduacaoId,
        'graduacao_nova_nome': novaGraduacaoNome,
        'data_graduacao': Timestamp.fromDate(dataGraduacao),
        'evento_id': eventoId,
        'criado_em': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Graduação do aluno atualizada para: $novaGraduacaoNome');
    } catch (e) {
      debugPrint('❌ Erro ao atualizar graduação do aluno: $e');
      rethrow;
    }
  }
}