import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/pagamento_model.dart';
import 'package:uai_capoeira/core/services/uai_callable_client.dart';

class PagamentoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // O ID permanece estável para retry de uma operação cujo resultado é incerto.
  String? _pendingId;
  String? _pendingFingerprint;
  Future<void> registrarPagamento({
    required String eventoId,
    required String participacaoId,
    required PagamentoModel pagamento,
  }) async {
    final fingerprint =
        '$eventoId::$participacaoId::${pagamento.valor}::${pagamento.formaPagamento}::${pagamento.parcela}::${pagamento.observacoes}';
    if (_pendingFingerprint != fingerprint) {
      _pendingFingerprint = fingerprint;
      _pendingId = _firestore.collection('eventos').doc().id;
    }
    await UaiCallableClient.instance.call('salvarPagamentoEvento', {
      'acao': 'criar',
      'eventoId': eventoId,
      'participacaoId': participacaoId,
      'pagamentoId': _pendingId,
      'valor': pagamento.valor,
      'formaPagamento': pagamento.formaPagamento,
      'status': pagamento.status,
      'dataPagamento': pagamento.dataPagamento.toUtc().toIso8601String(),
      'observacoes': pagamento.observacoes,
      'parcela': pagamento.parcela,
      'anexo': pagamento.anexo,
    });
    _pendingId = null;
    _pendingFingerprint = null;
  }

  Future<void> editarPagamento({
    required String eventoId,
    required String participacaoId,
    required String pagamentoId,
    required double valor,
    required String formaPagamento,
    required String status,
    required String observacoes,
  }) async {
    await UaiCallableClient.instance.call('salvarPagamentoEvento', {
      'acao': 'editar',
      'eventoId': eventoId,
      'participacaoId': participacaoId,
      'pagamentoId': pagamentoId,
      'valor': valor,
      'formaPagamento': formaPagamento,
      'status': status,
      'observacoes': observacoes,
    });
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

      final total = pagamentos
          .where((p) => p.status == 'confirmado')
          .fold<double>(0, (total, p) => total + p.valor);
      debugPrint('💰 Total pago: $total');
      return total;
    } catch (e) {
      debugPrint('❌ Erro ao calcular total pago: $e');
      return 0;
    }
  }

  // A exclusão operacional é um estorno; o documento permanece auditável.
  Future<void> excluirPagamento({
    required String eventoId,
    required String participacaoId,
    required String pagamentoId,
  }) async {
    await UaiCallableClient.instance.call('salvarPagamentoEvento', {
      'acao': 'excluir',
      'eventoId': eventoId,
      'participacaoId': participacaoId,
      'pagamentoId': pagamentoId,
    });
  }
}
