import 'package:cloud_firestore/cloud_firestore.dart';
import 'uniformes_admin_service.dart';

class RemessaService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final UniformesAdminService _backend = UniformesAdminService();

  Future<String> criarRemessa(Map<String, dynamic> dados) async {
    final result = await _backend.operar('salvar_remessa', {'remessa': dados});
    return result['id'].toString();
  }

  Future<void> atualizarRemessa(
    String remessaId,
    Map<String, dynamic> dados,
  ) async {
    await _backend.operar('salvar_remessa', {
      'remessaId': remessaId,
      'remessa': dados,
    });
  }

  Future<int> excluirRemessaComPedidos(
    String remessaId, {
    required String motivo,
  }) async {
    final result = await _backend.operar('excluir_remessa', {
      'remessaId': remessaId,
      'motivo': motivo,
      'confirmacao': true,
    });
    return (result['pedidosExcluidos'] as num?)?.toInt() ?? 0;
  }

  Future<void> excluirRemessa(
    String remessaId, {
    required String motivo,
  }) async {
    await excluirRemessaComPedidos(remessaId, motivo: motivo);
  }

  Future<void> excluirPedidoDefinitivamente(
    String pedidoId, {
    String? remessaId,
    required String motivo,
  }) async {
    await _backend.operar('excluir_pedido', {
      'pedidoId': pedidoId,
      'motivo': motivo,
      'confirmacao': true,
    });
  }

  Future<void> vincularPedido(String pedidoId, String remessaId) async {
    await _backend.operar('vincular_pedido', {
      'pedidoId': pedidoId,
      'remessaId': remessaId,
    });
  }

  Future<void> desvincularPedido(String pedidoId, String remessaId) async {
    await _backend.operar('desvincular_pedido', {
      'pedidoId': pedidoId,
      'remessaId': remessaId,
    });
  }

  Future<void> iniciarConfeccao(String id) async {
    await _backend.operar('iniciar_confeccao', {'remessaId': id});
  }

  Future<void> receberRemessa(String id) async {
    await _backend.operar('receber_remessa', {'remessaId': id});
  }

  Stream<QuerySnapshot> getPedidosDaRemessa(String remessaId) {
    return _firestore
        .collection('pedidos_uniformes')
        .where('remessa_id', isEqualTo: remessaId)
        .orderBy('data_pedido', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot> getTodasRemessas() {
    return _firestore
        .collection('remessas')
        .orderBy('criado_em', descending: true)
        .snapshots();
  }
}
