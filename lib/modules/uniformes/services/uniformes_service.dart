import 'uniformes_admin_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class UniformesService {
  UniformesService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final UniformesAdminService _backend = UniformesAdminService();

  User? get currentUser => _auth.currentUser;

  static const origemEstoque = 'estoque';
  static const origemForaEstoque = 'fora_do_estoque';
  static const origemEncomenda = 'encomenda';

  Future<String> adicionarItemEstoque(
    Map<String, dynamic> dados, {
    String? itemId,
  }) async {
    final result = await _backend.operar('salvar_produto', {
      'itemId': itemId,
      'produto': dados,
    });
    return result['id'].toString();
  }

  Future<void> registrarMovimentacao({
    required String itemId,
    required String itemNome,
    required String tipo,
    required int quantidade,
    required int quantidadeAnterior,
  }) async {
    await _backend.operar('ajustar_estoque', {
      'itemId': itemId,
      'tipo': tipo,
      'quantidade': quantidade,
      'motivo': 'Ajuste administrativo de estoque: $itemNome',
    });
  }

  Future<String> registrarVenda(
    Map<String, dynamic> dadosVenda, {
    String? formaPagamentoInicial,
  }) async {
    final result = await _backend.operar('criar_venda', {
      ...dadosVenda,
      'formaPagamentoInicial': formaPagamentoInicial,
    });
    return result['id'].toString();
  }

  Future<void> registrarPagamentoVenda({
    required String vendaId,
    required double valorPagamento,
    required String formaPagamento,
    Map<String, dynamic>? vendaData,
    String? pagamentoId,
  }) async {
    await _backend.operar('registrar_pagamento_venda', {
      'vendaId': vendaId,
      'valor': valorPagamento,
      'formaPagamento': formaPagamento,
    });
  }

  Future<void> atualizarVenda({
    required String vendaId,
    required List<Map<String, dynamic>> itens,
    required String observacoes,
  }) async {
    await _backend.operar('editar_venda', {
      'vendaId': vendaId,
      'itens': itens,
      'observacoes': observacoes,
    });
  }

  Future<void> registrarEntregaItem({
    required String vendaId,
    required int itemIndex,
    required bool entregue,
  }) async {
    await _backend.operar('registrar_entrega', {
      'vendaId': vendaId,
      'itemIndex': itemIndex,
      'entregue': entregue,
    });
  }

  Future<void> atualizarStatusEntregaVenda({
    required String vendaId,
    required String statusEntrega,
  }) async {
    if (!['aguardando', 'entregue'].contains(statusEntrega)) {
      throw StateError('Status de entrega inválido.');
    }
    await _backend.operar('registrar_entrega', {
      'vendaId': vendaId,
      'entregue': statusEntrega == 'entregue',
    });
  }

  String? _motivoBloqueioExclusao(Map<String, dynamic> data) {
    if ((data['status'] ?? 'ativa') != 'cancelada') {
      return 'Cancele a venda antes de excluí-la definitivamente.';
    }

    final pagamentos = List<Map<String, dynamic>>.from(
      data['pagamentos'] ?? const [],
    );
    final valorPago = (data['valor_pago'] as num?)?.toDouble() ?? 0;
    if (pagamentos.isNotEmpty || valorPago > 0.005) {
      return 'Esta venda possui histórico financeiro e deve permanecer para auditoria.';
    }

    final itens = List<Map<String, dynamic>>.from(data['itens'] ?? const []);
    if (itens.any(
      (item) => (item['status_entrega'] ?? '').toString() == 'entregue',
    )) {
      return 'Esta venda possui item entregue e deve permanecer para preservar o histórico do aluno.';
    }

    return null;
  }

  Future<String?> verificarExclusaoDefinitiva(String vendaId) async {
    final snap = await _firestore
        .collection('vendas_uniformes')
        .doc(vendaId)
        .get();
    if (!snap.exists) return 'Venda não encontrada.';

    return _motivoBloqueioExclusao(snap.data()!);
  }

  Future<void> excluirVendaDefinitivamente({
    required String vendaId,
    required String motivo,
  }) async {
    await _backend.operar('excluir_venda', {
      'vendaId': vendaId,
      'motivo': motivo,
      'confirmacao': true,
    });
  }

  Future<void> cancelarVenda({
    required String vendaId,
    required String motivo,
  }) async {
    await _backend.operar('cancelar_venda', {
      'vendaId': vendaId,
      'motivo': motivo,
    });
  }

  Future<String> criarPedido(Map<String, dynamic> dadosPedido) async {
    final result = await _backend.operar('criar_pedido', dadosPedido);
    return result['id'].toString();
  }

  Future<void> atualizarStatusPedido(String pedidoId, String status) async {
    await _backend.operar('status_pedido', {
      'pedidoId': pedidoId,
      'status': status,
    });
  }

  Future<void> registrarEntregaPedido(String pedidoId) async {
    await _backend.operar('registrar_entrega_pedido', {
      'pedidoId': pedidoId,
      'entregue': true,
    });
  }

  Future<void> registrarPagamentoPedido({
    required String pedidoId,
    required double valorPagamento,
    required String formaPagamento,
    required Map<String, dynamic> pedidoData,
  }) async {
    await _backend.operar('registrar_pagamento_pedido', {
      'pedidoId': pedidoId,
      'valor': valorPagamento,
      'formaPagamento': formaPagamento,
    });
  }

  String gerarIdPedido() {
    final now = DateTime.now();

    return 'PED-${DateFormat('yyyyMMdd').format(now)}-'
        '${DateFormat('HHmmss').format(now)}-'
        '${1000 + now.millisecond % 9000}';
  }
}
