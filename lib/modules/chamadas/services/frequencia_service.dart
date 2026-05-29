import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/frequencia_model.dart';

class FrequenciaService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ------------------------------------------------------------
  // ✅ MÉTODO 1: Cálculo de frequência (apenas leitura)
  // ------------------------------------------------------------

  /// Calcula frequência a partir dos dados do contador (coleção correta)
  FrequenciaModel calcularFrequencia(Map<String, dynamic> contadorData) {
    final ultimoDiaPresente = contadorData['ultimo_dia_presente'] as Timestamp?;
    return FrequenciaModel.calcular(ultimoDiaPresente?.toDate());
  }

  /// Versão para DocumentSnapshot
  FrequenciaModel calcularFrequenciaDeDocumento(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return FrequenciaModel.vazia();
    return calcularFrequencia(data);
  }

  // ------------------------------------------------------------
  // ✅ MÉTODO 2: ATUALIZAÇÃO COMPLETA DO CONTADOR (ESCRITA CORRETA)
  // ------------------------------------------------------------

  /// ATUALIZA APENAS A COLEÇÃO /contador_presencas_alunos
  /// NÃO toca no documento do aluno (exceto ultimo_dia_presente separadamente)
  Future<void> atualizarContadorPresenca({
    required String alunoId,
    required String alunoNome,
    required DateTime dataPresenca,
    required String professorId,
    required String professorNome,
    required String turmaId,
    required String academiaId,
    required bool presente,
  }) async {
    try {
      if (!presente) {
        debugPrint('⏭️ Aluno ausente - contador não incrementado');
        return;
      }

      final contadorRef = _firestore.collection('contador_presencas_alunos').doc(alunoId);
      final contadorDoc = await contadorRef.get();

      final diaSemanaAbrev = _getDiaSemanaAbrev(dataPresenca);

      // Dados base para atualização
      final Map<String, dynamic> dadosContador = {
        'aluno_id': alunoId,
        'aluno_nome': alunoNome,
        'academia_id': academiaId,
        'turma_id': turmaId,
        'professor_atualizacao': professorNome,
        'professor_id_atualizacao': professorId,
        'ultima_chamada': Timestamp.fromDate(dataPresenca),
        'ultima_chamada_por': professorNome,
        'ultima_chamada_por_id': professorId,
        'ultimo_dia_presente': Timestamp.fromDate(dataPresenca),
        'atualizado_em': FieldValue.serverTimestamp(),
      };

      // ✅ Se documento NÃO EXISTE: criar com todos os dias zerados
      if (!contadorDoc.exists) {
        debugPrint('🆕 Criando contador para aluno: $alunoId');

        // Inicializar todos os dias com 0
        dadosContador['seg'] = 0;
        dadosContador['ter'] = 0;
        dadosContador['qua'] = 0;
        dadosContador['qui'] = 0;
        dadosContador['sex'] = 0;
        dadosContador['sab'] = 0;
        dadosContador['dom'] = 0;

        // Incrementar o dia atual
        dadosContador[diaSemanaAbrev] = 1;

        await contadorRef.set(dadosContador);
        debugPrint('✅ Contador criado e incrementado: $alunoId - $diaSemanaAbrev = 1');
      }
      // ✅ Se documento EXISTE: apenas incrementar o dia atual
      else {
        debugPrint('🔄 Atualizando contador existente: $alunoId');

        await contadorRef.update({
          ...dadosContador,
          diaSemanaAbrev: FieldValue.increment(1),
        });
        debugPrint('✅ Contador incrementado: $alunoId - $diaSemanaAbrev +1');
      }

    } catch (e) {
      debugPrint('❌ ERRO CRÍTICO em atualizarContadorPresenca: $e');
      rethrow;
    }
  }

  // ------------------------------------------------------------
  // ✅ MÉTODO 3: Atualizar apenas ultimo_dia_presente no aluno (cache rápido)
  // ------------------------------------------------------------

  /// ÚNICA escrita permitida no documento do aluno para frequência
  Future<void> atualizarUltimoDiaPresenteAluno({
    required String alunoId,
    required DateTime dataPresenca,
  }) async {
    try {
      final alunoRef = _firestore.collection('alunos').doc(alunoId);

      await alunoRef.update({
        'ultimo_dia_presente': Timestamp.fromDate(dataPresenca),
      });

      debugPrint('✅ ultimo_dia_presente atualizado no aluno: $alunoId');
    } catch (e) {
      debugPrint('❌ Erro ao atualizar ultimo_dia_presente no aluno: $e');
      // Não rethrow - não crítico
    }
  }

  // ------------------------------------------------------------
  // ✅ MÉTODO 4: Buscar dados do contador para exibição
  // ------------------------------------------------------------

  /// Busca os dados REAIS de frequência na coleção correta
  Future<Map<String, dynamic>?> buscarDadosContador(String alunoId) async {
    try {
      final doc = await _firestore.collection('contador_presencas_alunos').doc(alunoId).get();

      if (doc.exists) {
        return doc.data()!;
      }

      debugPrint('ℹ️ Contador não encontrado para aluno: $alunoId');
      return null;
    } catch (e) {
      debugPrint('❌ Erro ao buscar contador: $e');
      return null;
    }
  }

  // ------------------------------------------------------------
  // ✅ MÉTODO 5: Utilitários de histórico
  // ------------------------------------------------------------

  Stream<QuerySnapshot> getHistoricoAluno(String alunoId) {
    return _firestore
        .collection('log_presenca_alunos')
        .where('aluno_id', isEqualTo: alunoId)
        .orderBy('data_aula', descending: true)
        .snapshots();
  }

  List<Map<String, dynamic>> calcularDiferencasEntreAulas(
      List<QueryDocumentSnapshot> docs,
      ) {
    if (docs.isEmpty) return [];

    final resultados = <Map<String, dynamic>>[];

    for (int i = 0; i < docs.length; i++) {
      final doc = docs[i];
      final data = doc['data_aula'] as Timestamp;
      final dataAtual = data.toDate();

      int diasDesdeAnterior;
      if (i == 0) {
        final hoje = DateTime.now();
        diasDesdeAnterior = hoje.difference(dataAtual).inDays;
      } else {
        final dataAnterior = docs[i - 1]['data_aula'] as Timestamp;
        diasDesdeAnterior = dataAnterior.toDate().difference(dataAtual).inDays;
      }

      resultados.add({
        'doc': doc,
        'data': dataAtual,
        'dias_entre': diasDesdeAnterior,
        'presente': doc['presente'] ?? false,
        'tipo_aula': doc['tipo_aula'] ?? 'N/A',
        'professor': doc['professor_nome'] ?? 'Sistema',
        'cor': _getCorPorDias(diasDesdeAnterior),
      });
    }

    return resultados;
  }

  // ------------------------------------------------------------
  // 🔧 MÉTODOS PRIVADOS AUXILIARES
  // ------------------------------------------------------------

  String _getDiaSemanaAbrev(DateTime data) {
    switch (data.weekday) {
      case DateTime.monday: return 'seg';
      case DateTime.tuesday: return 'ter';
      case DateTime.wednesday: return 'qua';
      case DateTime.thursday: return 'qui';
      case DateTime.friday: return 'sex';
      case DateTime.saturday: return 'sab';
      case DateTime.sunday: return 'dom';
      default: return 'seg';
    }
  }

  Color _getCorPorDias(int dias) {
    if (dias <= 3) return Colors.blue;
    if (dias <= 6) return Colors.green;
    if (dias <= 14) return Colors.amber;
    if (dias <= 29) return Colors.orange;
    return Colors.red;
  }
}