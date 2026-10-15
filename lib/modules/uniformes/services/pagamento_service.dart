import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/pagamento_model.dart';
import 'package:uai_capoeira/modules/associacao/services/associacao_financeiro_service.dart';

class PagamentoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AssociacaoFinanceiroService _financeiroAssociacao = AssociacaoFinanceiroService();

  // Registrar um novo pagamento
  Future<void> registrarPagamento({
    required String eventoId,
    required String participacaoId,
    required PagamentoModel pagamento,
  }) async {
    try {
      debugPrint('📝 Registrando pagamento...');
      debugPrint('   Evento: $eventoId');
      debugPrint('   Participação: $participacaoId');
      debugPrint('   Valor: ${pagamento.valor}');

      // Referência para a coleção de pagamentos
      final pagamentoRef = _firestore
          .collection('eventos')
          .doc(eventoId)
          .collection('participacoes')
          .doc(participacaoId)
          .collection('pagamentos')
          .doc();

      // Cria o pagamento com o ID gerado
      final novoPagamento = PagamentoModel(
        id: pagamentoRef.id,
        valor: pagamento.valor,
        formaPagamento: pagamento.formaPagamento,
        dataPagamento: pagamento.dataPagamento,
        observacoes: pagamento.observacoes,
        registroPor: pagamento.registroPor,
        registroPorNome: pagamento.registroPorNome,
        parcela: pagamento.parcela,
        anexo: pagamento.anexo,
        status: pagamento.status,
      );

      // Salva no Firestore
      await pagamentoRef.set(novoPagamento.toMap());
      debugPrint('✅ Pagamento registrado com ID: ${pagamentoRef.id}');

      // Central Financeira da Associação: cada pagamento de evento gera
      // uma única entrada idempotente vinculada ao pagamento de origem.
      try {
        final participacaoDoc = await _firestore
            .collection('eventos')
            .doc(eventoId)
            .collection('participacoes')
            .doc(participacaoId)
            .get();
        final pData = participacaoDoc.data() ?? const <String, dynamic>{};
        final alunoNome = (pData['aluno_nome'] ?? pData['nome_aluno'] ?? pData['nome'] ?? 'Participante').toString();
        final eventoNome = (pData['evento_nome'] ?? 'Evento').toString();
        final alunoId = (pData['aluno_id'] ?? '').toString();
        await _financeiroAssociacao.registrarMovimentacaoAutomatica(
          tipo: 'entrada',
          valor: pagamento.valor,
          descricao: 'Pagamento de evento • $alunoNome',
          categoria: 'Eventos',
          subcategoria: 'Participação / inscrição',
          origemModulo: 'eventos',
          origemId: '$eventoId::$participacaoId::${pagamentoRef.id}',
          origemDescricao: eventoNome,
          formaPagamento: pagamento.formaPagamento,
          dataCompetencia: pagamento.dataPagamento,
          alunoId: alunoId.isEmpty ? null : alunoId,
          eventoId: eventoId,
          observacoes: pagamento.observacoes ?? '',
        );
      } catch (e) {
        debugPrint('⚠️ Pagamento salvo, mas falhou sincronização com Associação: $e');
      }

      // 🔥 ATUALIZA O TOTAL PAGO NA PARTICIPAÇÃO (EM ANDAMENTO)
      await _atualizarTotalPago(eventoId, participacaoId);
    } catch (e) {
      debugPrint('❌ Erro ao registrar pagamento: $e');
      rethrow;
    }
  }

  // Listar pagamentos de uma participação
  Future<List<PagamentoModel>> listarPagamentos({
    required String eventoId,
    required String participacaoId,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('eventos')
          .doc(eventoId)
          .collection('participacoes')
          .doc(participacaoId)
          .collection('pagamentos')
          .orderBy('data_pagamento', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => PagamentoModel.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      debugPrint('❌ Erro ao listar pagamentos: $e');
      return [];
    }
  }

  // Calcular total pago em uma participação
  Future<double> calcularTotalPago({
    required String eventoId,
    required String participacaoId,
  }) async {
    try {
      final pagamentos = await listarPagamentos(
        eventoId: eventoId,
        participacaoId: participacaoId,
      );

      final total = pagamentos.fold<double>(0, (total, p) => total + p.valor);
      debugPrint('💰 Total pago: $total');
      return total;
    } catch (e) {
      debugPrint('❌ Erro ao calcular total pago: $e');
      return 0;
    }
  }

  // 🔥 ATUALIZA O TOTAL PAGO NA COLEÇÃO EM ANDAMENTO
  Future<void> _atualizarTotalPago(
    String eventoId,
    String participacaoId,
  ) async {
    try {
      final totalPago = await calcularTotalPago(
        eventoId: eventoId,
        participacaoId: participacaoId,
      );

      debugPrint('📊 Atualizando total_pago para: $totalPago');

      // 🔥 PRIMEIRO: Atualiza na coleção EM ANDAMENTO
      final participacaoRef = _firestore
          .collection('participacoes_eventos_em_andamento')
          .doc(participacaoId);

      final doc = await participacaoRef.get();

      if (doc.exists) {
        await participacaoRef.update({
          'total_pago': totalPago,
          'atualizado_em': FieldValue.serverTimestamp(),
        });
        debugPrint('✅ Total pago atualizado na EM ANDAMENTO');
      } else {
        // Se não existir em andamento, tenta na FINALIZADA
        await _firestore
            .collection('participacoes_eventos')
            .doc(participacaoId)
            .update({
              'total_pago': totalPago,
              'atualizado_em': FieldValue.serverTimestamp(),
            });
        debugPrint('✅ Total pago atualizado na FINALIZADA');
      }

      // 🔥 TAMBÉM ATUALIZA NA SUBCOLEÇÃO DO EVENTO
      await _firestore
          .collection('eventos')
          .doc(eventoId)
          .collection('participacoes')
          .doc(participacaoId)
          .update({
            'total_pago': totalPago,
            'atualizado_em': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('❌ Erro ao atualizar total_pago: $e');
    }
  }

  // Excluir um pagamento
  Future<void> excluirPagamento({
    required String eventoId,
    required String participacaoId,
    required String pagamentoId,
  }) async {
    try {
      await _firestore
          .collection('eventos')
          .doc(eventoId)
          .collection('participacoes')
          .doc(participacaoId)
          .collection('pagamentos')
          .doc(pagamentoId)
          .delete();

      try {
        await _financeiroAssociacao.estornarPorOrigem(
          origemModulo: 'eventos',
          origemId: '$eventoId::$participacaoId::$pagamentoId',
          motivo: 'Pagamento removido no módulo de Eventos.',
        );
      } catch (e) {
        debugPrint('⚠️ Falhou estorno automático na Associação: $e');
      }

      await _atualizarTotalPago(eventoId, participacaoId);
      debugPrint('✅ Pagamento excluído: $pagamentoId');
    } catch (e) {
      debugPrint('❌ Erro ao excluir pagamento: $e');
      rethrow;
    }
  }
}
