import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // ← IMPORTANTE: Adicionar esta importação

class UniformesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? currentUser = FirebaseAuth.instance.currentUser;

  // Operações de Estoque
  Future<void> adicionarItemEstoque(Map<String, dynamic> dados, {String? itemId}) async {
    if (itemId == null) {
      dados.addAll({
        'criado_em': FieldValue.serverTimestamp(),
        'criado_por': currentUser?.uid,
      });
      await _firestore.collection('uniformes_estoque').add(dados);
    } else {
      dados.addAll({
        'ultima_atualizacao': FieldValue.serverTimestamp(),
        'atualizado_por': currentUser?.uid,
      });
      await _firestore.collection('uniformes_estoque').doc(itemId).update(dados);
    }
  }

  Future<void> registrarMovimentacao({
    required String itemId,
    required String itemNome,
    required String tipo,
    required int quantidade,
    required int quantidadeAnterior,
  }) async {
    await _firestore.collection('movimentacoes_estoque').add({
      'item_id': itemId,
      'item_nome': itemNome,
      'tipo': tipo,
      'quantidade': quantidade,
      'quantidade_anterior': quantidadeAnterior,
      'quantidade_nova': tipo == 'entrada'
          ? quantidadeAnterior + quantidade
          : quantidadeAnterior - quantidade,
      'usuario_id': currentUser?.uid,
      'data': FieldValue.serverTimestamp(),
    });
  }

  // Operações de Vendas
  Future<String> registrarVenda(Map<String, dynamic> dadosVenda) async {
    final docRef = await _firestore.collection('vendas_uniformes').add(dadosVenda);

    // Atualizar estoque
    for (var item in dadosVenda['itens']) {
      if (item['controla_estoque'] == true) {
        await _firestore
            .collection('uniformes_estoque')
            .doc(item['item_id'])
            .update({
          'quantidade': FieldValue.increment(-(item['quantidade'])),
        });
      }
    }

    return docRef.id;
  }

  Future<void> registrarPagamentoVenda({
    required String vendaId,
    required double valorPagamento,
    required String formaPagamento,
    required Map<String, dynamic> vendaData,
  }) async {
    double novoValorPago = (vendaData['valor_pago'] ?? 0) + valorPagamento;
    String novoStatus = novoValorPago >= (vendaData['valor_total'] ?? 0) ? 'pago' : 'parcial';

    await _firestore.collection('vendas_uniformes').doc(vendaId).update({
      'valor_pago': novoValorPago,
      'status_pagamento': novoStatus,
      'pagamentos': FieldValue.arrayUnion([
        {
          'valor': valorPagamento,
          'forma': formaPagamento,
          'data': DateTime.now().toIso8601String(),
          'usuario_id': currentUser?.uid,
        }
      ]),
    });
  }

  // Operações de Pedidos
  Future<String> criarPedido(Map<String, dynamic> dadosPedido) async {
    final docRef = await _firestore.collection('pedidos_uniformes').add(dadosPedido);
    return docRef.id;
  }

  Future<void> atualizarStatusPedido(String pedidoId, String status) async {
    Map<String, dynamic> updates = {
      'status': status,
    };

    if (status == 'em_confeccao') {
      updates['data_inicio_confeccao'] = FieldValue.serverTimestamp();
    } else if (status == 'finalizado') {
      updates['data_finalizacao'] = FieldValue.serverTimestamp();
    }

    await _firestore.collection('pedidos_uniformes').doc(pedidoId).update(updates);
  }

  Future<void> registrarPagamentoPedido({
    required String pedidoId,
    required double valorPagamento,
    required String formaPagamento,
    required Map<String, dynamic> pedidoData,
  }) async {
    double novoPago = (pedidoData['valor_pago'] ?? 0) + valorPagamento;
    double total = pedidoData['valor_total'] ?? 0;
    String novoStatus = novoPago >= total ? 'pago' : 'parcial';

    await _firestore.collection('pedidos_uniformes').doc(pedidoId).update({
      'valor_pago': novoPago,
      'status_pagamento': novoStatus,
      'pagamentos': FieldValue.arrayUnion([
        {
          'valor': valorPagamento,
          'forma': formaPagamento,
          'data': DateTime.now().toIso8601String(),
          'usuario_id': currentUser?.uid,
        }
      ]),
    });
  }

  // Métodos auxiliares
  String gerarIdPedido() {
    DateTime now = DateTime.now();
    // CORREÇÃO: Criar instâncias de DateFormat
    final DateFormat dateFormat = DateFormat('yyyyMMdd');
    final DateFormat timeFormat = DateFormat('HHmmss');

    String data = dateFormat.format(now);
    String hora = timeFormat.format(now);
    String random = (1000 + now.millisecond % 9000).toString();
    return 'PED-$data-$hora-$random';
  }
}